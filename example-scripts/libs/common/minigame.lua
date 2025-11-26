-- Minigame Helper Module
-- Provides utilities for saving/restoring player state when entering/leaving minigames
-- Usage: local minigame = require("common.minigame")

local M = {}

local File = import("java.io.File")
local YamlConfiguration = import("org.bukkit.configuration.file.YamlConfiguration")
local ItemStack = import("org.bukkit.inventory.ItemStack")
local Location = import("org.bukkit.Location")
local GameMode = import("org.bukkit.GameMode")
local Material = import("org.bukkit.Material")
local Vector = import("org.bukkit.util.Vector")

-- Get state data directory for a minigame
-- @param minigameName string Name of the minigame (e.g., "eggfight", "spleef")
-- @return File The directory (created if it doesn't exist)
function M.getStateDir(minigameName)
    local pluginDataFolder = server:getPluginManager():getPlugin("LuaLink"):getDataFolder()
    local stateDir = File(pluginDataFolder, minigameName .. "/states")
    if not stateDir:exists() then
        stateDir:mkdirs()
    end
    return stateDir
end

-- Get state file for a player
-- @param minigameName string Name of the minigame
-- @param uuid string Player's UUID (formatted with underscores)
-- @return File The state file
function M.getStateFile(minigameName, uuid)
    local stateDir = M.getStateDir(minigameName)
    return File(stateDir, uuid .. ".yml")
end

-- Save player state to disk
-- @param minigameName string Name of the minigame
-- @param player Player The player to save
-- @return boolean True if successful
function M.savePlayerState(minigameName, player)
    local uuid = player:getUniqueId():toString():gsub("-", "_")
    local file = M.getStateFile(minigameName, uuid)
    local config = YamlConfiguration()

    -- Location
    local loc = player:getLocation()
    config:set("world", loc:getWorld():getName())
    config:set("x", loc:getX())
    config:set("y", loc:getY())
    config:set("z", loc:getZ())
    config:set("yaw", loc:getYaw())
    config:set("pitch", loc:getPitch())

    -- Inventory - using Bukkit serialization with error handling
    local inventory = player:getInventory()
    local itemsSaved = 0
    for i = 0, inventory:getSize() - 1 do
        local item = inventory:getItem(i)
        if item ~= nil and item:getType() ~= Material.AIR then
            local success, serialized = pcall(function()
                return item:serialize()
            end)
            if success and serialized ~= nil then
                config:set("items." .. i, serialized)
                itemsSaved = itemsSaved + 1
            end
        end
    end

    -- Player stats
    config:set("health", player:getHealth())
    config:set("foodLevel", player:getFoodLevel())
    config:set("gameMode", player:getGameMode():toString())
    config:set("saturation", player:getSaturation())
    config:set("exhaustion", player:getExhaustion())

    -- Booleans as strings
    config:set("allowFlight", player:getAllowFlight() and "true" or "false")
    config:set("flying", player:isFlying() and "true" or "false")

    -- Experience
    config:set("exp", player:getExp())
    config:set("level", player:getLevel())
    config:set("totalExperience", player:getTotalExperience())

    local success, err = pcall(function()
        config:save(file)
    end)

    if success then
        return true
    else
        return false
    end
end

-- Restore player state from disk
-- @param minigameName string Name of the minigame
-- @param player Player The player to restore
-- @return boolean True if successful
function M.restorePlayerState(minigameName, player)
    local uuid = player:getUniqueId():toString():gsub("-", "_")
    local file = M.getStateFile(minigameName, uuid)

    if not file:exists() then
        return false
    end

    local success, result = pcall(function()
        local config = YamlConfiguration:loadConfiguration(file)

        -- Restore inventory
        local inventory = player:getInventory()
        inventory:clear()

        local itemsSection = config:getConfigurationSection("items")
        if itemsSection ~= nil then
            local keys = java.luaify(itemsSection:getKeys(false):toArray())
            for _, key in ipairs(keys) do
                local slot = tonumber(key)
                if slot ~= nil then
                    local itemData = itemsSection:getConfigurationSection(key)
                    if itemData ~= nil then
                        local itemSuccess, item = pcall(function()
                            return ItemStack:deserialize(itemData:getValues(true))
                        end)
                        if itemSuccess and item ~= nil then
                            inventory:setItem(slot, item)
                        end
                    end
                end
            end
        end

        -- Restore player stats
        player:setHealth(config:getDouble("health", 20.0))
        player:setFoodLevel(config:getInt("foodLevel", 20))
        player:setSaturation(config:getDouble("saturation", 5.0))
        player:setExhaustion(config:getDouble("exhaustion", 0.0))

        local gameModeStr = config:getString("gameMode", "SURVIVAL")
        player:setGameMode(GameMode:valueOf(gameModeStr))

        -- Restore booleans
        local allowFlightStr = config:getString("allowFlight", "false")
        player:setAllowFlight(allowFlightStr == "true")

        local flyingStr = config:getString("flying", "false")
        player:setFlying(flyingStr == "true")

        -- Restore experience
        player:setExp(config:getDouble("exp", 0.0))
        player:setLevel(config:getInt("level", 0))
        player:setTotalExperience(config:getInt("totalExperience", 0))

        -- Restore location
        local worldName = config:getString("world")
        local world = server:getWorld(worldName)
        if world ~= nil then
            local x = config:getDouble("x")
            local y = config:getDouble("y")
            local z = config:getDouble("z")
            local yaw = config:getDouble("yaw")
            local pitch = config:getDouble("pitch")
            local location = Location(world, x, y, z, yaw, pitch)
            player:teleport(location)

            -- Reset velocity and fall distance to prevent fall damage
            player:setVelocity(Vector(0, 0, 0))
            player:setFallDistance(0)
        end

        -- Delete the state file
        file:delete()
        return true
    end)

    if not success then
        -- Delete corrupted file
        file:delete()
        return false
    end

    return result
end

-- Delete a player's saved state
-- @param minigameName string Name of the minigame
-- @param uuid string Player's UUID (formatted with underscores)
function M.deletePlayerState(minigameName, uuid)
    local file = M.getStateFile(minigameName, uuid)
    if file:exists() then
        file:delete()
    end
end

-- Clear player's inventory and give them a specific item
-- @param player Player The player
-- @param material Material The material to give
-- @param amount number Amount per slot (default: 64)
-- @param slots number Number of slots to fill (default: 36, entire inventory)
function M.giveInfiniteItem(player, material, amount, slots)
    amount = amount or 64
    slots = slots or 36

    player:getInventory():clear()
    local itemStack = ItemStack(material, amount)
    for slot = 0, slots - 1 do
        player:getInventory():setItem(slot, itemStack)
    end
end

-- Prepare player for minigame (heal, feed, clear effects)
-- @param player Player The player
-- @param gameMode GameMode The game mode to set (default: SURVIVAL)
function M.preparePlayer(player, gameMode)
    gameMode = gameMode or GameMode.SURVIVAL

    player:setGameMode(gameMode)
    player:setHealth(20.0)
    player:setFoodLevel(20)
    player:setSaturation(5.0)
    player:setExhaustion(0.0)
    player:setFireTicks(0)
    player:setFallDistance(0)

    -- Clear all potion effects
    local effects = java.luaify(player:getActivePotionEffects():toArray())
    for _, effect in ipairs(effects) do
        player:removePotionEffect(effect:getType())
    end
end

-- Check if player has a saved state
-- @param minigameName string Name of the minigame
-- @param player Player The player to check
-- @return boolean True if state file exists
function M.hasPlayerState(minigameName, player)
    local uuid = player:getUniqueId():toString():gsub("-", "_")
    local file = M.getStateFile(minigameName, uuid)
    return file:exists()
end

return M
