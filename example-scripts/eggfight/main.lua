-- EggFight Plugin
-- Players compete by throwing eggs to destroy wool platforms
-- Uses disk-based state persistence

local Material = import("org.bukkit.Material")
local Location = import("org.bukkit.Location")
local File = import("java.io.File")
local ItemStack = import("org.bukkit.inventory.ItemStack")
local YamlConfiguration = import("org.bukkit.configuration.file.YamlConfiguration")
local GameMode = import("org.bukkit.GameMode")
local GameRule = import("org.bukkit.GameRule")
local Player = import("org.bukkit.entity.Player")

-- Load shared utilities
local utils = require("common.utils")
local minigame = require("common.minigame")

local games = {}
local nextArenaX = 0
local ARENA_SPACING = 200
local FALL_Y = 50
local COUNTDOWN_SECONDS = 5

-- Block decay configuration (store names as strings, not Material objects)
local DECAY_STAGES = {
    { materialName = "WHITE_WOOL",      health = 100 },
    { materialName = "LIGHT_GRAY_WOOL", health = 75 },
    { materialName = "GRAY_WOOL",       health = 50 },
    { materialName = "BLACK_WOOL",      health = 25 }
}
local DECAY_RATE_STANDING = 15 -- Health lost per tick when standing
local DECAY_RATE_IDLE = 0      -- Health lost per tick when not standing (disabled)
local DECAY_TICK_INTERVAL = 10 -- Ticks between decay updates





-- Arena configuration based on player count
local function getArenaDiameter(playerCount)
    if playerCount <= 4 then
        return 30
    elseif playerCount <= 8 then
        return 40
    elseif playerCount <= 15 then
        return 50
    else
        return 60
    end
end



-- Arena generation
local function buildWoolPlatform(world, centerX, centerZ, y, radius)
    for x = -radius, radius do
        for z = -radius, radius do
            local distSq = x * x + z * z
            if distSq <= radius * radius then
                local blockX = centerX + x
                local blockZ = centerZ + z
                local isGrey = (x + z) % 2 == 0
                local material = isGrey and Material.LIGHT_GRAY_WOOL or Material.WHITE_WOOL
                local block = world:getBlockAt(blockX, y, blockZ)
                block:setBlockData(material:createBlockData())
            end
        end
    end
end

local function buildRainbowArch(world, centerX, centerZ, y, radius)
    local colors = {
        Material.RED_WOOL, Material.ORANGE_WOOL, Material.YELLOW_WOOL,
        Material.LIME_WOOL, Material.LIGHT_BLUE_WOOL, Material.BLUE_WOOL,
        Material.PURPLE_WOOL
    }

    local archRadius = radius + 5
    local archHeight = 15

    for angle = 0, 180, 5 do
        local rad = math.rad(angle)
        local x = math.floor(archRadius * math.cos(rad))
        local heightOffset = math.floor(archHeight * math.sin(rad))

        local colorIndex = math.floor(angle / 180 * #colors) + 1
        local material = colors[math.min(colorIndex, #colors)]

        -- Build along Z axis
        for zOffset = -3, 3 do
            local block = world:getBlockAt(centerX + x, y + heightOffset, centerZ + zOffset)
            block:setBlockData(material:createBlockData())
        end
    end
end

local function createArena(playerCount)
    local worldName = "world_eggfight"
    local world = server:getWorld(worldName)

    if world == nil then
        local WorldCreator = import("org.bukkit.WorldCreator")
        local WorldType = import("org.bukkit.WorldType")

        local creator = WorldCreator(worldName)
        creator:type(WorldType.FLAT)
        creator:generateStructures(false)
        creator:generatorSettings('{"layers": [{"block":"air","height":1}], "biome":"plains"}')

        world = creator:createWorld()
        world:setKeepSpawnInMemory(false)

        -- Set to day and disable day/night cycle
        world:setTime(1000)
        world:setGameRule(GameRule.DO_DAYLIGHT_CYCLE, false)

        -- Clear weather and keep it clear
        world:setStorm(false)
        world:setThundering(false)
        world:setWeatherDuration(999999)

        script.logger:info("Created eggfight world")
    end

    local centerX = nextArenaX
    local centerZ = 0
    local platformY = 100
    local diameter = getArenaDiameter(playerCount)
    local radius = math.floor(diameter / 2)

    nextArenaX = nextArenaX + ARENA_SPACING

    -- Ensure world is always daytime and clear weather
    world:setTime(1000)
    world:setStorm(false)
    world:setThundering(false)

    buildWoolPlatform(world, centerX, centerZ, platformY, radius)
    buildRainbowArch(world, centerX, centerZ, platformY, radius)

    return {
        world = world,
        centerX = centerX,
        centerZ = centerZ,
        platformY = platformY,
        radius = radius
    }
end

-- Game instance
local function createGame(initiator)
    local game = {
        id = #games + 1,
        initiator = initiator:getName(),
        participants = { initiator:getName() },
        arena = nil,
        activePlayers = {},
        spectators = {},
        state = "COUNTDOWN",
        blockHealth = {}, -- Tracks health of each block: "x,y,z" -> health value
        decayTask = nil   -- The repeating task for block decay
    }

    table.insert(games, game)
    return game
end

local function findPlayerGame(playerName)
    for _, game in ipairs(games) do
        if game.state ~= "FINISHED" then
            for _, name in ipairs(game.participants) do
                if name == playerName then
                    return game
                end
            end
        end
    end
    return nil
end

local function removeFinishedGames()
    local activeGames = {}
    for _, game in ipairs(games) do
        if game.state ~= "FINISHED" then
            table.insert(activeGames, game)
        end
    end
    games = activeGames
end

-- Block decay system
local function getBlockKey(x, y, z)
    return x .. "," .. y .. "," .. z
end

local function getBlockHealth(game, x, y, z)
    local key = getBlockKey(x, y, z)
    return game.blockHealth[key] or 100
end

local function setBlockHealth(game, x, y, z, health)
    local key = getBlockKey(x, y, z)
    game.blockHealth[key] = health
end

local function updateBlockAppearance(world, x, y, z, health)
    local block = world:getBlockAt(x, y, z)
    local blockType = block:getType()

    -- Only update wool blocks
    if not blockType:toString():match("WOOL") then
        return
    end

    -- Find appropriate stage based on health
    for _, stage in ipairs(DECAY_STAGES) do
        if health >= stage.health then
            local material = Material:getMaterial(stage.materialName)

            if material == nil then
                script.logger:warning(string.format("Could not find material: %s", stage.materialName))
                return
            end

            if block:getType() ~= material then
                block:setBlockData(material:createBlockData())
            end
            return
        end
    end

    -- Health is below minimum, destroy block
    block:setBlockData(Material.AIR:createBlockData())
end

local function startBlockDecay(game)
    game.decayTask = scheduler:runRepeating(function()
        if game.state ~= "ACTIVE" then
            return
        end

        -- Get all players' standing positions
        local standingBlocks = {}
        for playerName, _ in pairs(game.activePlayers) do
            local player = server:getPlayer(playerName)
            if player ~= nil then
                local loc = player:getLocation()
                local blockY = math.floor(loc:getY()) - 1 -- Block below player
                local blockX = math.floor(loc:getX())
                local blockZ = math.floor(loc:getZ())
                local key = getBlockKey(blockX, blockY, blockZ)
                standingBlocks[key] = true
            end
        end

        -- Decay all blocks in the arena
        local world = game.arena.world
        local centerX = game.arena.centerX
        local centerZ = game.arena.centerZ
        local platformY = game.arena.platformY
        local radius = game.arena.radius

        for x = -radius, radius do
            for z = -radius, radius do
                local distSq = x * x + z * z
                if distSq <= radius * radius then
                    local blockX = centerX + x
                    local blockZ = centerZ + z
                    local key = getBlockKey(blockX, platformY, blockZ)

                    local health = getBlockHealth(game, blockX, platformY, blockZ)

                    -- Only decay if someone is standing on it
                    if standingBlocks[key] then
                        health = health - DECAY_RATE_STANDING
                        setBlockHealth(game, blockX, platformY, blockZ, health)
                        updateBlockAppearance(world, blockX, platformY, blockZ, health)
                    end
                end
            end
        end
    end, DECAY_TICK_INTERVAL, DECAY_TICK_INTERVAL)
end



local function startGame(game)
    script.logger:info(string.format("Starting egg fight game with %d participants", #game.participants))
    game.state = "ACTIVE"
    game.arena = createArena(#game.participants)
    script.logger:info(string.format("Arena created at X=%d Y=%d", game.arena.centerX, game.arena.platformY))

    local spawnY = game.arena.platformY + 1
    local spawnRadius = math.floor(game.arena.radius * 0.7)

    for i, playerName in ipairs(game.participants) do
        script.logger:info(string.format("Teleporting player: %s", playerName))
        local player = server:getPlayer(playerName)
        if player ~= nil then
            minigame.savePlayerState("eggfight", player)

            local angle = (i - 1) * (360 / #game.participants)
            local rad = math.rad(angle)
            local spawnX = game.arena.centerX + math.floor(spawnRadius * math.cos(rad))
            local spawnZ = game.arena.centerZ + math.floor(spawnRadius * math.sin(rad))

            local location = Location(game.arena.world, spawnX + 0.5, spawnY, spawnZ + 0.5)
            script.logger:info(string.format("Teleporting %s to %d,%d,%d", playerName, spawnX, spawnY, spawnZ))
            player:teleport(location)
            player:setGameMode(GameMode.SURVIVAL)
            player:setAllowFlight(false)
            player:setFlying(false)
            player:setHealth(20.0)
            player:setFoodLevel(20)

            minigame.giveInfiniteItem(player, Material.EGG, 64)
            game.activePlayers[playerName] = true

            player:sendRichMessage("<gold><bold>EGG FIGHT!</bold> <yellow>Last one standing wins!")
        end
    end

    -- Start block decay system
    startBlockDecay(game)
end

local function eliminatePlayer(game, playerName)
    game.activePlayers[playerName] = nil
    game.spectators[playerName] = true

    local player = server:getPlayer(playerName)
    if player ~= nil then
        player:setGameMode(GameMode.SPECTATOR)
        player:sendRichMessage("<red><bold>You fell!</bold> <gray>Now spectating...")
    end

    local remainingCount = 0
    local winner = nil
    for name, _ in pairs(game.activePlayers) do
        remainingCount = remainingCount + 1
        winner = name
    end

    if remainingCount == 1 then
        endGame(game, winner)
    elseif remainingCount == 0 then
        endGame(game, nil)
    end
end

function endGame(game, winnerName)
    script.logger:info("Ending game. Winner: " .. (winnerName or "none"))
    game.state = "FINISHED"

    if winnerName then
        utils.broadcastMessage(string.format("<gold><bold>%s wins the Egg Fight!", winnerName))
    else
        utils.broadcastMessage("<gold><bold>Egg Fight ended with no winner!</bold>")
    end

    script.logger:info("Restoring " .. #game.participants .. " participants")
    for _, playerName in ipairs(game.participants) do
        script.logger:info("Processing player: " .. playerName)
        local player = server:getPlayer(playerName)
        if player ~= nil then
            local restored = minigame.restorePlayerState("eggfight", player)
            if restored then
                player:sendRichMessage("<green>You've been returned to your original location!")
            else
                script.logger:warning("Failed to restore state for " .. playerName)
                player:sendRichMessage("<red>Failed to restore your state!")
            end
        else
            script.logger:warning("Player " .. playerName .. " is not online")
        end
    end

    -- Cancel decay task
    if game.decayTask then
        scheduler:cancel(game.decayTask)
        game.decayTask = nil
    end

    removeFinishedGames()
end

-- Command handler
script:registerCommand(function(sender, args)
    if not Player.class:isInstance(sender) then
        sender:sendRichMessage("<red>Only players can start an egg fight!</red>")
        return
    end
    ---@cast sender org.bukkit.entity.Player

    local player = sender

    -- Convert Java args array to Lua table
    local argsTable = java.luaify(args)

    -- Handle quit subcommand
    if #argsTable > 0 and argsTable[1] == "quit" then
        local game = findPlayerGame(player:getName())

        if not game then
            player:sendRichMessage("<red>You're not in an egg fight!</red>")
            return
        end

        if game.state == "COUNTDOWN" then
            -- Remove from countdown
            local newParticipants = {}
            for _, name in ipairs(game.participants) do
                if name ~= player:getName() then
                    table.insert(newParticipants, name)
                end
            end
            game.participants = newParticipants

            -- Restore player state
            if minigame.restorePlayerState("eggfight", player) then
                player:sendRichMessage(
                    "<green>You've left the egg fight and been returned to your original location!</green>")
                utils.broadcastMessage(string.format(
                    "<gray>%s left the egg fight. <gray>(%d players)",
                    player:getName(), #game.participants))
            else
                player:sendRichMessage("<red>Failed to restore your state!</red>")
            end

            -- Cancel game if no one left
            if #game.participants == 0 then
                game.state = "FINISHED"
                removeFinishedGames()
            end
        elseif game.state == "ACTIVE" then
            -- Eliminate from active game
            if game.activePlayers[player:getName()] then
                eliminatePlayer(game, player:getName())
                player:sendRichMessage("<green>You've left the egg fight!</green>")
            else
                player:sendRichMessage("<red>You're already eliminated!</red>")
            end
        end

        return
    end

    script.logger:info(string.format("%s used /eggfight command", player:getName()))
    local existingGame = findPlayerGame(player:getName())

    if existingGame then
        script.logger:info(string.format("%s is already in game %s with state %s",
            player:getName(), existingGame.id, existingGame.state))
        if existingGame.state == "COUNTDOWN" then
            player:sendRichMessage("<yellow>You're already in the egg fight!</yellow>")
        else
            player:sendRichMessage("<red>You're currently in an active egg fight!</red>")
        end
        return
    end

    script.logger:info(string.format("%s is not in any game, proceeding...", player:getName()))

    local pendingGame = nil
    for _, game in ipairs(games) do
        if game.state == "COUNTDOWN" then
            pendingGame = game
            break
        end
    end

    if pendingGame then
        table.insert(pendingGame.participants, player:getName())
        utils.broadcastMessage("<yellow>" .. player:getName() .. " <gold>joined the egg fight! <gray>(" ..
            #pendingGame.participants .. " players)")
    else
        local game = createGame(player)
        script.logger:info("Created new game, starting countdown")
        utils.broadcastMessage("<gold><bold>🥚 EGG FIGHT!</bold> <yellow>" .. player:getName() ..
            " wants an egg fight! Type <gold>/eggfight <yellow>to join! <gray>(" .. COUNTDOWN_SECONDS .. " seconds)")

        scheduler:runDelayed(function()
            script.logger:info("Join period finished. Game state: " .. game.state)
            if game.state == "COUNTDOWN" then
                -- 3-2-1 countdown
                for _, playerName in ipairs(game.participants) do
                    local player = server:getPlayer(playerName)
                    if player ~= nil then
                        player:sendRichMessage("<gold><bold>3")
                    end
                end

                scheduler:runDelayed(function()
                    for _, playerName in ipairs(game.participants) do
                        local player = server:getPlayer(playerName)
                        if player ~= nil then
                            player:sendRichMessage("<gold><bold>2")
                        end
                    end

                    scheduler:runDelayed(function()
                        for _, playerName in ipairs(game.participants) do
                            local player = server:getPlayer(playerName)
                            if player ~= nil then
                                player:sendRichMessage("<gold><bold>1")
                            end
                        end

                        scheduler:runDelayed(function()
                            for _, playerName in ipairs(game.participants) do
                                local player = server:getPlayer(playerName)
                                if player ~= nil then
                                    player:sendRichMessage("<green><bold>GO!")
                                end
                            end

                            if game.state == "COUNTDOWN" then
                                startGame(game)
                            else
                                script.logger:warning("Game state is not COUNTDOWN, aborting start")
                            end
                        end, 20)
                    end, 20)
                end, 20)
            else
                script.logger:warning("Game state is not COUNTDOWN, aborting start")
            end
        end, COUNTDOWN_SECONDS * 20)
    end
end, {
    name = "eggfight",
    description = "Start or join an egg fight battle",
    usage = "/eggfight [quit]",
    aliases = { "ef" },
    tabComplete = function(sender, args)
        local argsTable = java.luaify(args)
        if #argsTable == 0 then
            return { "quit" }
        elseif #argsTable == 1 then
            local partial = argsTable[1]
            if string.sub("quit", 1, #partial) == partial then
                return { "quit" }
            end
        end
        return {}
    end
})

-- Event listeners
script:registerListener("org.bukkit.event.player.PlayerEggThrowEvent", function(event)
    local player = event:getPlayer()
    local game = findPlayerGame(player:getName())

    if game ~= nil and game.state == "ACTIVE" then
        scheduler:runDelayed(function()
            minigame.giveInfiniteItem(player, Material.EGG, 64)
        end, 1)
    end
end)

script:registerListener("org.bukkit.event.entity.ProjectileHitEvent", function(event)
    local entityType = event:getEntityType():toString()
    if entityType ~= "EGG" then return end

    local projectile = event:getEntity()
    local shooter = projectile:getShooter()
    if shooter == nil or not shooter:getClass():getName():match("CraftPlayer") then return end

    local game = findPlayerGame(shooter:getName())
    if game == nil or game.state ~= "ACTIVE" then return end

    local hitBlock = event:getHitBlock()
    if hitBlock ~= nil then
        local blockType = hitBlock:getType():toString()
        if blockType:match("WOOL") then
            hitBlock:setBlockData(Material.AIR:createBlockData())
        end
    end
end)

script:registerListener("org.bukkit.event.player.PlayerMoveEvent", function(event)
    local player = event:getPlayer()
    local game = findPlayerGame(player:getName())

    if game ~= nil and game.state == "ACTIVE" and game.activePlayers[player:getName()] then
        if player:getLocation():getY() < FALL_Y then
            eliminatePlayer(game, player:getName())
        end
    end
end)

script:registerListener("org.bukkit.event.player.PlayerQuitEvent", function(event)
    local player = event:getPlayer()
    local game = findPlayerGame(player:getName())

    if game ~= nil then
        if game.state == "COUNTDOWN" then
            -- Restore player state when they quit during countdown
            minigame.restorePlayerState("eggfight", player)

            local newParticipants = {}
            for _, name in ipairs(game.participants) do
                if name ~= player:getName() then
                    table.insert(newParticipants, name)
                end
            end
            game.participants = newParticipants

            if #game.participants == 0 then
                game.state = "FINISHED"
                removeFinishedGames()
            end
        elseif game.state == "ACTIVE" and game.activePlayers[player:getName()] then
            eliminatePlayer(game, player:getName())
        end
    end
end)

script:onLoad(function()
    script.logger:info("EggFight plugin loaded!")
    script.logger:info("Command: /eggfight")
    script.logger:info("States stored in: " .. minigame.getStateDir("eggfight"):getAbsolutePath())
end)

script:onUnload(function()
    script.logger:info("EggFight plugin unloaded!")
    games = {}
end)
