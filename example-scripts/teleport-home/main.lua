-- Teleport Home Plugin
-- Demonstrates modern LuaLink best practices:
-- - Type annotations
-- - JSON persistence
-- - String formatting
-- - Class instance checking
-- - Proper error handling
-- - goto continue pattern

-- 1. Imports
local Player = import "org.bukkit.entity.Player"
local Location = import "org.bukkit.Location"
local Sound = import "org.bukkit.Sound"

-- 2. Module requires
local json = require "json"

-- 3. Constants
local MAX_HOMES = 5
local TELEPORT_DELAY_TICKS = 60 -- 3 seconds
local DATA_FILE_NAME = "homes.json"

-- 4. State variables
local pendingTeleports = {} -- {uuid = {location, ticksRemaining}}
local playerHomes = {}      -- Cached in memory, loaded from JSON

-- 5. Helper functions

local function getDataFile()
    return script:getDataFolder() .. "/" .. DATA_FILE_NAME
end

local function loadAllHomes()
    local file = io.open(getDataFile(), "r")
    if not file then
        return {}
    end

    local content = file:read("*a")
    file:close()

    if content == "" then
        return {}
    end

    local success, data = pcall(json.decode, content)
    if not success then
        script.logger:warning("Failed to parse homes JSON, starting fresh")
        return {}
    end

    return data or {}
end

local function saveAllHomes()
    local file = io.open(getDataFile(), "w")
    if not file then
        script.logger:severe("Failed to open homes file for writing!")
        return false
    end

    file:write(json.encode(playerHomes))
    file:close()
    return true
end

local function getPlayerHomes(uuid)
    return playerHomes[uuid] or {}
end

local function setHome(player, homeName)
    local uuid = player:getUniqueId():toString()
    local homes = getPlayerHomes(uuid)

    -- Check limit
    if not homes[homeName] then
        local count = 0
        for _ in pairs(homes) do
            count = count + 1
        end
        if count >= MAX_HOMES then
            return false, string.format("You can only have %d homes!", MAX_HOMES)
        end
    end

    -- Save location
    local loc = player:getLocation()
    homes[homeName] = {
        world = loc:getWorld():getName(),
        x = loc:getX(),
        y = loc:getY(),
        z = loc:getZ(),
        yaw = loc:getYaw(),
        pitch = loc:getPitch(),
        timestamp = os.time()
    }

    playerHomes[uuid] = homes
    saveAllHomes()

    return true, string.format("Home '%s' set!", homeName)
end

local function deleteHome(player, homeName)
    local uuid = player:getUniqueId():toString()
    local homes = getPlayerHomes(uuid)

    if not homes[homeName] then
        return false, string.format("Home '%s' doesn't exist!", homeName)
    end

    homes[homeName] = nil
    playerHomes[uuid] = homes
    saveAllHomes()

    return true, string.format("Home '%s' deleted!", homeName)
end

local function getHomeLocation(player, homeName)
    local uuid = player:getUniqueId():toString()
    local homes = getPlayerHomes(uuid)
    local home = homes[homeName]

    if not home then
        return nil
    end

    local world = server:getWorld(home.world)
    if not world then
        return nil
    end

    return Location(world, home.x, home.y, home.z, home.yaw, home.pitch)
end

local function startTeleport(player, location, homeName)
    local uuid = player:getUniqueId():toString()

    -- Cancel existing teleport
    if pendingTeleports[uuid] then
        player:sendRichMessage("<yellow>Previous teleport cancelled</yellow>")
    end

    pendingTeleports[uuid] = {
        location = location,
        homeName = homeName,
        ticksRemaining = TELEPORT_DELAY_TICKS,
        originalLocation = player:getLocation()
    }

    player:sendRichMessage(string.format(
        "<green>Teleporting to <white>%s</white> in <white>3</white> seconds... Don't move!",
        homeName
    ))
end

local function cancelTeleport(player)
    local uuid = player:getUniqueId():toString()
    if pendingTeleports[uuid] then
        pendingTeleports[uuid] = nil
        player:sendRichMessage("<red>Teleport cancelled!</red>")
    end
end

local function countKeys(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- 6. Commands

script:registerCommand(function(sender, args)
    if not Player.class:isInstance(sender) then
        sender:sendRichMessage("<red>Only players can use this command!</red>")
        return
    end
    ---@cast sender org.bukkit.entity.Player

    local argsTable = java.luaify(args)

    -- /home - List homes
    if #argsTable == 0 then
        local uuid = sender:getUniqueId():toString()
        local homes = getPlayerHomes(uuid)

        if countKeys(homes) == 0 then
            sender:sendRichMessage("<yellow>You don't have any homes set!</yellow>")
            sender:sendRichMessage("<gray>Use <white>/sethome <name></white> to set one</gray>")
            return
        end

        sender:sendRichMessage("<gold><bold>Your Homes:</bold></gold>")
        for name, _ in pairs(homes) do
            sender:sendRichMessage(string.format("<gray>•</gray> <white>%s</white>", name))
        end
        sender:sendRichMessage(string.format(
            "<gray>Use <white>/home <name></white> to teleport (%d/%d homes)",
            countKeys(homes), MAX_HOMES
        ))
        return
    end

    -- /home <name> - Teleport to home
    local homeName = argsTable[1]
    local location = getHomeLocation(sender, homeName)

    if not location then
        sender:sendRichMessage(string.format("<red>Home '%s' not found!</red>", homeName))
        return
    end

    startTeleport(sender, location, homeName)
end, {
    name = "home",
    description = "Teleport to your home",
    usage = "/home [name]",
    permission = "teleport.home"
})

script:registerCommand(function(sender, args)
    if not Player.class:isInstance(sender) then
        sender:sendRichMessage("<red>Only players can use this command!</red>")
        return
    end
    ---@cast sender org.bukkit.entity.Player

    local argsTable = java.luaify(args)

    if #argsTable == 0 then
        sender:sendRichMessage("<red>Usage: /sethome <name></red>")
        return
    end

    local homeName = argsTable[1]:lower()

    -- Validate name
    if not homeName:match("^[a-z0-9_]+$") then
        sender:sendRichMessage("<red>Home name can only contain letters, numbers, and underscores!</red>")
        return
    end

    local success, message = setHome(sender, homeName)
    if success then
        sender:sendRichMessage("<green>" .. message .. "</green>")
        sender:playSound(sender:getLocation(), Sound.ENTITY_EXPERIENCE_ORB_PICKUP, 1.0, 1.0)
    else
        sender:sendRichMessage("<red>" .. message .. "</red>")
    end
end, {
    name = "sethome",
    description = "Set a home location",
    usage = "/sethome <name>",
    permission = "teleport.sethome"
})

script:registerCommand(function(sender, args)
    if not Player.class:isInstance(sender) then
        sender:sendRichMessage("<red>Only players can use this command!</red>")
        return
    end
    ---@cast sender org.bukkit.entity.Player

    local argsTable = java.luaify(args)

    if #argsTable == 0 then
        sender:sendRichMessage("<red>Usage: /delhome <name></red>")
        return
    end

    local homeName = argsTable[1]:lower()
    local success, message = deleteHome(sender, homeName)

    if success then
        sender:sendRichMessage("<green>" .. message .. "</green>")
    else
        sender:sendRichMessage("<red>" .. message .. "</red>")
    end
end, {
    name = "delhome",
    aliases = { "removehome" },
    description = "Delete a home",
    usage = "/delhome <name>",
    permission = "teleport.delhome"
})

-- 7. Event listeners

-- Cancel teleport on movement
script:registerListener("org.bukkit.event.player.PlayerMoveEvent", function(event)
    ---@cast event org.bukkit.event.player.PlayerMoveEvent
    local player = event:getPlayer()
    local uuid = player:getUniqueId():toString()
    local pending = pendingTeleports[uuid]

    if not pending then
        return
    end

    -- Check if player moved more than 0.5 blocks
    local from = event:getFrom()
    local to = event:getTo()

    if to == nil then
        return
    end

    local distance = from:distance(to)
    if distance > 0.5 then
        cancelTeleport(player)
    end
end)

-- Cancel teleport on damage
script:registerListener("org.bukkit.event.entity.EntityDamageEvent", function(event)
    ---@cast event org.bukkit.event.entity.EntityDamageEvent
    local entity = event:getEntity()

    if not Player.class:isInstance(entity) then
        return
    end
    ---@cast entity org.bukkit.entity.Player

    cancelTeleport(entity)
end)

-- Clean up on quit
script:registerListener("org.bukkit.event.player.PlayerQuitEvent", function(event)
    local uuid = event:getPlayer():getUniqueId():toString()
    pendingTeleports[uuid] = nil
end)

-- 8. Lifecycle hooks

script:onLoad(function()
    -- Initialize JSON file
    local file = io.open(getDataFile(), "a")
    if file then
        file:close()
    end

    -- Load homes
    playerHomes = loadAllHomes()

    local homeCount = 0
    for _ in pairs(playerHomes) do
        homeCount = homeCount + 1
    end

    script.logger:info(string.format("Teleport Home loaded! %d players with homes", homeCount))

    -- Start teleport countdown ticker
    scheduler:runRepeating(function()
        local toRemove = {}

        for uuid, pending in pairs(pendingTeleports) do
            local player = server:getPlayer(java.import("java.util.UUID"):fromString(uuid))

            -- Skip if player offline
            if not player then
                goto continue
            end

            pending.ticksRemaining = pending.ticksRemaining - 1

            if pending.ticksRemaining <= 0 then
                -- Execute teleport
                player:teleport(pending.location)
                player:sendRichMessage(string.format(
                    "<green>✨ Teleported to <white>%s</white>!</green>",
                    pending.homeName
                ))
                player:playSound(player:getLocation(), Sound.ENTITY_ENDERMAN_TELEPORT, 1.0, 1.0)
                table.insert(toRemove, uuid)
            elseif pending.ticksRemaining % 20 == 0 then
                -- Show countdown every second
                local secondsLeft = math.floor(pending.ticksRemaining / 20)
                player:sendRichMessage(string.format(
                    "<green>Teleporting in <white>%d</white>...</green>",
                    secondsLeft
                ))
            end

            ::continue::
        end

        -- Clean up completed teleports
        for _, uuid in ipairs(toRemove) do
            pendingTeleports[uuid] = nil
        end
    end, 0, 1)
end)

script:onUnload(function()
    -- Save homes
    saveAllHomes()

    -- Cancel pending teleports
    for uuid, _ in pairs(pendingTeleports) do
        local player = server:getPlayer(java.import("java.util.UUID"):fromString(uuid))
        if player then
            player:sendRichMessage("<yellow>Teleport cancelled due to plugin reload</yellow>")
        end
    end

    pendingTeleports = {}

    script.logger:info("Teleport Home unloaded!")
end)
