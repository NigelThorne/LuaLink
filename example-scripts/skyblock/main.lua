-- Skyblock Script for LuaLink
-- Creates persistent per-player skyblock worlds
-- Uses minigame helpers for state management
-- Usage: /skyblock - Go to your skyblock world
--        /skyblock reset - Delete and reset your skyblock world
--        /play - Return to the main world

local Bukkit = import("org.bukkit.Bukkit")
local WorldCreator = import("org.bukkit.WorldCreator")
local Material = import("org.bukkit.Material")
local Location = import("org.bukkit.Location")
local WorldType = import("org.bukkit.WorldType")
local File = import("java.io.File")
local ItemStack = import("org.bukkit.inventory.ItemStack")

-- Load minigame helper
local minigame = require("common.minigame")

-- Configuration
local config = {
    mainWorldName = "world",
    worldPrefix = "skyblock_",
    spawnY = 64,
    islandSize = 5
}

-- Store pending reset confirmations (temporary state, OK in memory)
local pendingResets = {}
local pendingDeletions = {}



-- Create a simple starting island for the player
local function createStartingIsland(world, centerX, centerZ)
    local y = config.spawnY

    -- Create a small grass platform
    for x = centerX - 2, centerX + 2 do
        for z = centerZ - 2, centerZ + 2 do
            world:getBlockAt(x, y - 3, z):setType(Material.DIRT)
            world:getBlockAt(x, y - 2, z):setType(Material.DIRT)
            world:getBlockAt(x, y - 1, z):setType(Material.DIRT)
            world:getBlockAt(x, y, z):setType(Material.GRASS_BLOCK)
        end
    end

    -- Add a tree
    local treeX, treeZ = centerX + 1, centerZ + 1
    world:getBlockAt(treeX, y + 1, treeZ):setType(Material.OAK_LOG)
    world:getBlockAt(treeX, y + 2, treeZ):setType(Material.OAK_LOG)
    world:getBlockAt(treeX, y + 3, treeZ):setType(Material.OAK_LOG)

    -- Tree leaves
    for dx = -1, 1 do
        for dz = -1, 1 do
            for dy = 2, 4 do
                if not (dx == 0 and dz == 0 and dy < 4) then
                    world:getBlockAt(treeX + dx, y + dy, treeZ + dz):setType(Material.OAK_LEAVES)
                end
            end
        end
    end

    -- Add a chest with starter items
    local chest = world:getBlockAt(centerX - 1, y + 1, centerZ)
    chest:setType(Material.CHEST)

    scheduler:runDelayed(function()
        local chestBlock = world:getBlockAt(centerX - 1, y + 1, centerZ)
        if chestBlock:getType() == Material.CHEST then
            local chestState = chestBlock:getState()
            local Container = import("org.bukkit.block.Container")
            if Container.class:isInstance(chestState) then
                local inventory = chestState:getInventory()

                -- Cobblestone generator essentials
                inventory:setItem(0, ItemStack(Material.LAVA_BUCKET, 1))
                inventory:setItem(1, ItemStack(Material.WATER_BUCKET, 1))
                inventory:setItem(2, ItemStack(Material.ICE, 2))

                -- Farming and food
                inventory:setItem(3, ItemStack(Material.MELON_SEEDS, 1))
                inventory:setItem(4, ItemStack(Material.PUMPKIN_SEEDS, 1))
                inventory:setItem(5, ItemStack(Material.SUGAR_CANE, 1))
                inventory:setItem(6, ItemStack(Material.BONE_MEAL, 8))

                -- Extras for expansion
                inventory:setItem(7, ItemStack(Material.DIRT, 8))
            end
        end
    end, 1)
end

-- Get or create a player's skyblock world
local function getOrCreateSkyblockWorld(player)
    local uuid = player:getUniqueId():toString():gsub("-", "_")
    local worldName = config.worldPrefix .. uuid

    local world = Bukkit:getWorld(worldName)

    if world == nil then
        script.logger:info("Creating new skyblock world for " .. player:getName())

        local creator = WorldCreator(worldName)
        creator:type(WorldType.FLAT)
        creator:generateStructures(false)
        creator:generatorSettings('{"layers": [], "biome":"plains"}')

        world = creator:createWorld()

        if world ~= nil then
            world:setSpawnLocation(0, config.spawnY + 1, 0)
            world:setKeepSpawnInMemory(false)

            createStartingIsland(world, 0, 0)
            script.logger:info("Created starting island for " .. player:getName())
        else
            script.logger:warning("Failed to create skyblock world for " .. player:getName())
        end
    end

    return world
end

-- /skyblock command
script:registerCommand(function(sender, args)
    if not sender:getClass():getName():match("CraftPlayer") then
        sender:sendRichMessage("<red>Only players can use this command!</red>")
        return
    end

    local player = sender
    local uuid = player:getUniqueId():toString():gsub("-", "_")

    if pendingDeletions[uuid] then
        player:sendRichMessage("<red>Your skyblock world is currently being reset. Please wait...</red>")
        return
    end

    -- Check if this is a reset command
    if #args > 0 and args[1]:lower() == "reset" then
        if pendingResets[uuid] then
            -- Confirmed! Reset the world
            local worldName = config.worldPrefix .. uuid
            local world = Bukkit:getWorld(worldName)

            pendingDeletions[uuid] = true

            -- Failsafe timeout
            scheduler:runDelayed(function()
                if pendingDeletions[uuid] then
                    pendingDeletions[uuid] = nil
                    script.logger:warning("Cleared stale deletion flag for " .. player:getName())
                end
            end, 100)

            local isInSkyblock = world ~= nil and player:getWorld():getName() == worldName

            if isInSkyblock then
                -- Save skyblock state before reset
                minigame.savePlayerState("skyblock_sb", player)

                -- Restore main world state
                if minigame.restorePlayerState("skyblock_main", player) then
                    player:sendRichMessage("<gray>Your state has been restored</gray>")
                end
            end

            -- Clear the world
            if world ~= nil then
                local clearRadius = 100
                local clearHeight = 128

                for x = -clearRadius, clearRadius do
                    for z = -clearRadius, clearRadius do
                        for y = 0, clearHeight do
                            world:getBlockAt(x, y, z):setType(Material.AIR)
                        end
                    end
                end

                createStartingIsland(world, 0, 0)
                script.logger:info("Reset skyblock world for " .. player:getName())
            end

            -- Delete skyblock state file
            minigame.deletePlayerState("skyblock_sb", uuid)

            pendingResets[uuid] = nil
            pendingDeletions[uuid] = nil

            player:sendRichMessage("<green>✓ Your skyblock world has been reset!</green>")
            player:sendRichMessage("<gray>Use /skyblock to return to your fresh island</gray>")
            player:playSound(player:getLocation(), "entity.generic.explode", 0.5, 1.0)
            return
        else
            -- First confirmation
            pendingResets[uuid] = true
            player:sendRichMessage("<red><bold>⚠ WARNING ⚠</bold></red>")
            player:sendRichMessage("<yellow>This will DELETE your entire skyblock world!</yellow>")
            player:sendRichMessage("<yellow>All your progress will be lost!</yellow>")
            player:sendRichMessage(
                "<yellow>Type <white>/skyblock reset</white> again within 10 seconds to confirm.</yellow>")
            player:playSound(player:getLocation(), "block.note_block.bass", 1.0, 0.5)

            scheduler:runDelayed(function()
                if pendingResets[uuid] then
                    pendingResets[uuid] = nil
                    player:sendRichMessage("<gray>Skyblock reset cancelled.</gray>")
                end
            end, 200)
            return
        end
    end

    -- Regular teleport to skyblock
    -- Save main world state (location, inventory, everything)
    if minigame.savePlayerState("skyblock_main", player) then
        player:sendRichMessage("<gray>Your state has been saved</gray>")
    end

    local skyblockWorld = getOrCreateSkyblockWorld(player)

    if skyblockWorld ~= nil then
        local spawnLoc = Location(skyblockWorld, 0.5, config.spawnY + 1, 0.5)
        player:teleport(spawnLoc)

        -- Set time to day and clear weather
        skyblockWorld:setTime(1000)
        skyblockWorld:setStorm(false)
        skyblockWorld:setThundering(false)

        -- Restore skyblock state if it exists
        if minigame.restorePlayerState("skyblock_sb", player) then
            player:sendRichMessage("<gray>Your skyblock state has been restored</gray>")
        end

        player:sendRichMessage("<aqua>✨ Welcome to your Skyblock world!</aqua>")
        player:sendRichMessage("<gray>Use /play to return to the main world</gray>")
        player:sendRichMessage("<gray>Use /skyblock reset to reset your world</gray>")
        player:playSound(player:getLocation(), "entity.enderman.teleport", 1.0, 1.0)

        script.logger:info(player:getName() .. " teleported to their skyblock world")
    else
        player:sendRichMessage("<red>Failed to load your skyblock world!</red>")
    end
end, {
    name = "skyblock",
    aliases = { "sb" },
    permission = "scripts.command.skyblock",
    description = "Go to your personal skyblock world. Use 'reset' to delete it.",
    usage = "/skyblock [reset]"
})

-- /play command
script:registerCommand(function(sender, args)
    if not sender:getClass():getName():match("CraftPlayer") then
        sender:sendRichMessage("<red>Only players can use this command!</red>")
        return
    end

    local player = sender
    local uuid = player:getUniqueId():toString():gsub("-", "_")

    local skyblockWorldName = config.worldPrefix .. uuid
    local skyblockWorld = Bukkit:getWorld(skyblockWorldName)
    local isInSkyblock = skyblockWorld ~= nil and player:getWorld():getName() == skyblockWorldName

    if not isInSkyblock then
        player:sendRichMessage("<yellow>You're not in your skyblock world!</yellow>")
        return
    end

    -- Save skyblock state
    if minigame.savePlayerState("skyblock_sb", player) then
        player:sendRichMessage("<gray>Your skyblock state has been saved</gray>")
    end

    -- Restore main world state (location, inventory, everything)
    if minigame.restorePlayerState("skyblock_main", player) then
        player:sendRichMessage("<gray>Your state has been restored</gray>")
    else
        -- Fallback to spawn if no saved state
        local mainWorld = Bukkit:getWorld(config.mainWorldName)
        if mainWorld ~= nil then
            player:teleport(mainWorld:getSpawnLocation())
            player:sendRichMessage("<yellow>No saved state found, teleported to spawn</yellow>")
        else
            player:sendRichMessage("<red>Main world not found!</red>")
            return
        end
    end

    player:sendRichMessage("<green>✨ Welcome back to the main world!</green>")
    player:playSound(player:getLocation(), "entity.enderman.teleport", 1.0, 1.0)

    script.logger:info(player:getName() .. " returned to the main world")
end, {
    name = "play",
    permission = "scripts.command.play",
    description = "Return to the main world",
    usage = "/play"
})

-- Clean up temporary storage when players leave
script:registerListener("org.bukkit.event.player.PlayerQuitEvent", function(event)
    local uuid = event:getPlayer():getUniqueId():toString():gsub("-", "_")
    pendingResets[uuid] = nil
    pendingDeletions[uuid] = nil
    -- Inventory data persists in JSON files
end)

script:onLoad(function()
    script.logger:info("Skyblock script loaded!")
    script.logger:info("Commands: /skyblock [reset], /play")
    script.logger:info("Using minigame helpers for state management")
end)

script:onUnload(function()
    script.logger:info("Skyblock script unloaded!")
    pendingResets = {}
    pendingDeletions = {}
    -- State data persists in files via minigame helpers
end)
