-- Common Utilities for LuaLink Scripts
-- Shared functions used across multiple plugins
-- Usage: local utils = require("common.utils")

local M = {}

-- Broadcast a rich message to all online players
-- @param message string The message to broadcast (supports MiniMessage formatting)
function M.broadcastMessage(message)
    local worlds = server:getWorlds()
    for i = 0, worlds:size() - 1 do
        local world = worlds:get(i)
        local players = world:getPlayers()
        for j = 0, players:size() - 1 do
            local player = players:get(j)
            player:sendRichMessage(message)
        end
    end
end

-- Iterate over all online players
-- @param callback function Function to call for each player: callback(player)
function M.forEachPlayer(callback)
    local worlds = server:getWorlds()
    for i = 0, worlds:size() - 1 do
        local world = worlds:get(i)
        local players = world:getPlayers()
        for j = 0, players:size() - 1 do
            local player = players:get(j)
            callback(player)
        end
    end
end

-- Get a data directory for a plugin
-- @param pluginName string Name of the subdirectory under LuaLink data folder
-- @return File The directory (created if it doesn't exist)
function M.getDataDir(pluginName)
    local File = import("java.io.File")
    local pluginDataFolder = server:getPluginManager():getPlugin("LuaLink"):getDataFolder()
    local dataDir = File(pluginDataFolder, pluginName)
    if not dataDir:exists() then
        dataDir:mkdirs()
    end
    return dataDir
end

-- Save data to a YAML file
-- @param file File The file to save to
-- @param data table Key-value pairs to save
function M.saveYaml(file, data)
    local YamlConfiguration = import("org.bukkit.configuration.file.YamlConfiguration")
    local config = YamlConfiguration()

    for key, value in pairs(data) do
        config:set(key, value)
    end

    config:save(file)
end

-- Load data from a YAML file
-- @param file File The file to load from
-- @return table|nil The loaded data, or nil if file doesn't exist
function M.loadYaml(file)
    if not file:exists() then
        return nil
    end

    local YamlConfiguration = import("org.bukkit.configuration.file.YamlConfiguration")

    local success, result = pcall(function()
        local config = YamlConfiguration:loadConfiguration(file)
        local data = {}

        -- Get all keys at root level
        local keys = config:getKeys(false)
        if keys ~= nil then
            local keysArray = java.luaify(keys:toArray())
            for _, key in ipairs(keysArray) do
                data[key] = config:get(key)
            end
        end

        return data
    end)

    if not success then
        return nil
    end

    return result
end

-- Format a UUID string (replace dashes with underscores for file names)
-- @param uuid string The UUID to format
-- @return string The formatted UUID
function M.formatUuid(uuid)
    return uuid:gsub("-", "_")
end

-- Check if a string is empty or nil
-- @param str string|nil The string to check
-- @return boolean True if empty or nil
function M.isEmpty(str)
    return str == nil or str == ""
end

-- Count the number of players online
-- @return number The count of online players
function M.getPlayerCount()
    local count = 0
    M.forEachPlayer(function(player)
        count = count + 1
    end)
    return count
end

-- Get an online player by name
-- @param name string The player name to find
-- @return Player|nil The player if found, nil otherwise
function M.getPlayerByName(name)
    local foundPlayer = nil
    M.forEachPlayer(function(player)
        if player:getName() == name then
            foundPlayer = player
        end
    end)
    return foundPlayer
end

return M
