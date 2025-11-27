-- Vanish Plugin for LuaLink
-- Persists vanish state for ops and suppresses command feedback

local File = import("java.io.File")
local YamlConfiguration = import("org.bukkit.configuration.file.YamlConfiguration")
local PotionEffect = import("org.bukkit.potion.PotionEffect")
local PotionEffectType = import("org.bukkit.potion.PotionEffectType")
local Player = import("org.bukkit.entity.Player")

-- Load shared utilities directly
local function loadUtils()
    local pluginDataFolder = server:getPluginManager():getPlugin("LuaLink"):getDataFolder()
    local utilsFile = File(pluginDataFolder, "scripts/common/utils.lua")
    local luaState = script:getLuaState()
    luaState:loadFile(utilsFile:getAbsolutePath())
    luaState:pCall(0, 1)
    return luaState:get(-1)
end

local utils = loadUtils()

-- Track vanished players in memory
local vanishedPlayers = {}

-- Get vanish data directory
local function getVanishDir()
    return utils.getDataDir("vanish")
end

-- Get vanish state file for a player
local function getVanishFile(uuid)
    local vanishDir = getVanishDir()
    return File(vanishDir, uuid .. ".yml")
end

-- Save vanish state
local function saveVanishState(player, isVanished)
    local uuid = player:getUniqueId():toString():gsub("-", "_")
    local file = getVanishFile(uuid)
    local config = YamlConfiguration()

    config:set("vanished", isVanished and "true" or "false")
    config:set("lastUpdate", tostring(os.time()))

    config:save(file)
    script.logger:info(string.format("Saved vanish state for %s: %s", player:getName(), tostring(isVanished)))
end

-- Load vanish state
local function loadVanishState(player)
    local uuid = player:getUniqueId():toString():gsub("-", "_")
    local file = getVanishFile(uuid)

    if not file:exists() then
        return false
    end

    local success, result = pcall(function()
        local config = YamlConfiguration:loadConfiguration(file)
        local vanishedStr = config:getString("vanished", "false")
        return vanishedStr == "true"
    end)

    if not success then
        script.logger:warning("Failed to load vanish state for " .. player:getName())
        return false
    end

    return result
end

-- Apply vanish effect to player
local function applyVanish(player)
    local playerName = player:getName()
    vanishedPlayers[playerName] = true

    -- Hide from player list for non-ops
    player:setPlayerListName("")

    -- Hide from non-ops
    utils.forEachPlayer(function(otherPlayer)
        if not otherPlayer:isOp() and otherPlayer:getName() ~= playerName then
            otherPlayer:hidePlayer(player)
        end
    end)

    -- Add invisibility effect (infinite duration)
    local invisEffect = PotionEffect(PotionEffectType.INVISIBILITY, 999999, 1)
    player:addPotionEffect(invisEffect)

    player:sendRichMessage("<gray>You are now <bold>vanished</bold>")
    script.logger:info(string.format("%s is now vanished", playerName))
end

-- Remove vanish effect from player
local function removeVanish(player)
    local playerName = player:getName()
    vanishedPlayers[playerName] = nil

    -- Restore player list name
    player:setPlayerListName(playerName)

    -- Make visible to all players
    utils.forEachPlayer(function(otherPlayer)
        otherPlayer:showPlayer(player)
    end)

    -- Remove invisibility effect
    player:removePotionEffect(PotionEffectType.INVISIBILITY)

    player:sendRichMessage("<gray>You are now <bold>visible</bold>")
    script.logger:info(string.format("%s is now visible", playerName))
end

-- Check if player is vanished
local function isVanished(player)
    return vanishedPlayers[player:getName()] == true
end

-- /vanish command
script:registerCommand(function(sender, args)
    if not Player.class:isInstance(sender) then
        sender:sendRichMessage("<red>Only players can use this command!</red>")
        return
    end
    ---@cast sender org.bukkit.entity.Player

    local player = sender

    if not player:isOp() then
        player:sendRichMessage("<red>You must be an operator to use this command!</red>")
        return
    end

    local currentlyVanished = isVanished(player)

    if currentlyVanished then
        removeVanish(player)
        saveVanishState(player, false)
    else
        applyVanish(player)
        saveVanishState(player, true)
    end
end, {
    name = "vanish",
    aliases = { "v" },
    description = "Toggle vanish mode (ops only)",
    usage = "/vanish"
})

-- Restore vanish state on join
script:registerListener("org.bukkit.event.player.PlayerJoinEvent", function(event)
    local player = event:getPlayer()

    if player:isOp() then
        local wasVanished = loadVanishState(player)
        if wasVanished then
            -- Suppress join message for vanished ops
            event:joinMessage(nil)
            -- Small delay to ensure player is fully loaded
            scheduler:runDelayed(function()
                applyVanish(player)
            end, 10)
        end
    else
        -- Non-op joining - hide all vanished ops from them
        scheduler:runDelayed(function()
            utils.forEachPlayer(function(otherPlayer)
                if otherPlayer:isOp() and isVanished(otherPlayer) then
                    player:hidePlayer(otherPlayer)
                end
            end)
        end, 5)
    end
end)

-- Save vanish state on quit
script:registerListener("org.bukkit.event.player.PlayerQuitEvent", function(event)
    local player = event:getPlayer()
    if player:isOp() then
        local currentlyVanished = isVanished(player)
        -- Suppress quit message for vanished ops
        if currentlyVanished then
            event:quitMessage(nil)
        end
        saveVanishState(player, currentlyVanished)
    end
end)

-- Suppress command feedback when vanished (log commands for debugging)
script:registerListener("org.bukkit.event.player.PlayerCommandPreprocessEvent", function(event)
    local player = event:getPlayer()
    if isVanished(player) then
        script.logger:info("Command by vanished player " .. player:getName() .. ": " .. event:getMessage())
    end
end)

script:onLoad(function()
    script.logger:info("Vanish plugin loaded!")
    script.logger:info("Commands: /vanish or /v")
    script.logger:info(string.format("Vanish states stored in: %s", getVanishDir():getAbsolutePath()))
end)

script:onUnload(function()
    script.logger:info("Vanish plugin unloaded!")
    -- Clear vanished players
    vanishedPlayers = {}
end)
