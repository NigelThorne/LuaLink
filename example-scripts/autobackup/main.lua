-- AutoBackup Plugin
-- Automatically backs up all worlds with tiered retention

-- Imports
local File = import("java.io.File")
local YamlConfiguration = import("org.bukkit.configuration.file.YamlConfiguration")
local ArchiveFormat = import("org.rauschig.jarchivelib.ArchiveFormat")
local ArchiverFactory = import("org.rauschig.jarchivelib.ArchiverFactory")
local CompressionType = import("org.rauschig.jarchivelib.CompressionType")
local Bukkit = import("org.bukkit.Bukkit")

-- Module requires
local utils = require("common.utils")

-- Constants
local PLUGIN_NAME = "autobackup"
local DEFAULT_INTERVAL_HOURS = 1
local DEFAULT_HOURLY_KEEP = 10
local DEFAULT_DAILY_KEEP = 7
local DEFAULT_MONTHLY_KEEP = 12

-- Create archiver for tar.xz compression
local ARCHIVER = ArchiverFactory:createArchiver(ArchiveFormat.TAR, CompressionType.XZ)

-- State
local backupTask = nil
local config = {}

-- Helper Functions

local function getBackupDir()
    local dataDir = utils.getDataDir(PLUGIN_NAME)
    local backupDir = File(dataDir, "backups")
    if not backupDir:exists() then
        backupDir:mkdirs()
    end
    return backupDir
end

local function getConfigFile()
    local dataDir = utils.getDataDir(PLUGIN_NAME)
    return File(dataDir, "config.yml")
end

local function loadConfig()
    local configFile = getConfigFile()
    local cfg = YamlConfiguration:loadConfiguration(configFile)

    config.intervalHours = cfg:getInt("interval-hours", DEFAULT_INTERVAL_HOURS)
    config.hourlyKeep = cfg:getInt("retention.hourly", DEFAULT_HOURLY_KEEP)
    config.dailyKeep = cfg:getInt("retention.daily", DEFAULT_DAILY_KEEP)
    config.monthlyKeep = cfg:getInt("retention.monthly", DEFAULT_MONTHLY_KEEP)

    script.logger:info("Loaded config: interval=" .. config.intervalHours .. "h, retention=" ..
        config.hourlyKeep .. "h/" .. config.dailyKeep .. "d/" .. config.monthlyKeep .. "m")
end

local function saveDefaultConfig()
    local configFile = getConfigFile()
    if configFile:exists() then
        return
    end

    local cfg = YamlConfiguration()
    cfg:set("interval-hours", DEFAULT_INTERVAL_HOURS)
    cfg:set("retention.hourly", DEFAULT_HOURLY_KEEP)
    cfg:set("retention.daily", DEFAULT_DAILY_KEEP)
    cfg:set("retention.monthly", DEFAULT_MONTHLY_KEEP)
    cfg:save(configFile)

    script.logger:info("Created default config")
end



local function parseBackupTimestamp(filename)
    -- Format: backup_YYYY-MM-DD_HH-MM-SS.tar.xz
    local year, month, day, hour, min, sec = filename:match("backup_(%d+)%-(%d+)%-(%d+)_(%d+)%-(%d+)%-(%d+)%.tar%.xz$")

    if not year then
        return nil
    end

    return {
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = tonumber(sec),
        filename = filename
    }
end

local function getBackupList()
    local backupDir = getBackupDir()
    local files = backupDir:listFiles()

    if files == nil then
        return {}
    end

    local backups = {}
    local filesTable = java.luaify(files)
    for _, file in ipairs(filesTable) do
        if file:isFile() and file:getName():match("^backup_.*%.tar%.xz$") then
            local timestamp = parseBackupTimestamp(file:getName())
            if timestamp then
                timestamp.file = file
                table.insert(backups, timestamp)
            end
        end
    end

    -- Sort by date (newest first)
    table.sort(backups, function(a, b)
        if a.year ~= b.year then return a.year > b.year end
        if a.month ~= b.month then return a.month > b.month end
        if a.day ~= b.day then return a.day > b.day end
        if a.hour ~= b.hour then return a.hour > b.hour end
        if a.min ~= b.min then return a.min > b.min end
        return a.sec > b.sec
    end)

    return backups
end

local function cleanupOldBackups()
    local backups = getBackupList()
    local toKeep = {}
    local seenDays = {}
    local seenMonths = {}

    script.logger:info("Running backup cleanup, found " .. #backups .. " backups")

    -- First pass: Keep last N hourly backups
    for i = 1, math.min(#backups, config.hourlyKeep) do
        toKeep[backups[i].filename] = true
    end

    -- Second pass: Keep one per day for last N days
    for _, backup in ipairs(backups) do
        local dayKey = string.format("%04d-%02d-%02d", backup.year, backup.month, backup.day)

        if not seenDays[dayKey] then
            seenDays[dayKey] = true
            toKeep[backup.filename] = true

            if #utils.keys(seenDays) >= config.dailyKeep then
                break
            end
        end
    end

    -- Third pass: Keep one per month for last N months
    seenMonths = {}
    for _, backup in ipairs(backups) do
        local monthKey = string.format("%04d-%02d", backup.year, backup.month)

        if not seenMonths[monthKey] then
            seenMonths[monthKey] = true
            toKeep[backup.filename] = true

            if #utils.keys(seenMonths) >= config.monthlyKeep then
                break
            end
        end
    end

    -- Delete backups not in keep list
    local deleted = 0
    for _, backup in ipairs(backups) do
        if not toKeep[backup.filename] then
            local success, err = pcall(function()
                backup.file:delete()
            end)

            if success then
                deleted = deleted + 1
                script.logger:info("Deleted old backup: " .. backup.filename)
            else
                script.logger:warning("Failed to delete " .. backup.filename .. ": " .. tostring(err))
            end
        end
    end

    script.logger:info("Cleanup complete: kept " .. #utils.keys(toKeep) .. ", deleted " .. deleted)
end

local function createBackup()
    script.logger:info("Starting backup process...")

    -- Save all loaded worlds
    local onlinePlayers = java.luaify(server:getOnlinePlayers():toArray())
    for _, player in ipairs(onlinePlayers) do
        if player:isOp() then
            player:sendRichMessage("<yellow>Starting world backup...</yellow>")
        end
    end

    local loadedWorlds = java.luaify(server:getWorlds():toArray())
    for _, world in ipairs(loadedWorlds) do
        script.logger:info("Saving world: " .. world:getName())
        world:save()
    end

    -- Create timestamp
    local timestamp = os.date("%Y-%m-%d_%H-%M-%S")
    local backupName = "backup_" .. timestamp

    -- Create backup directory
    local backupDir = getBackupDir()
    local backupDirPath = backupDir:getAbsolutePath()

    -- Find all world folders in server directory (including unloaded worlds)
    local serverDir = File("."):getAbsoluteFile():getParentFile()
    local serverDirPath = serverDir:getAbsolutePath()
    local serverFiles = serverDir:listFiles()
    local worldFolders = {}

    if serverFiles ~= nil then
        local filesTable = java.luaify(serverFiles)
        for _, file in ipairs(filesTable) do
            if file:isDirectory() then
                local dirName = file:getName()
                -- Check if this looks like a world folder
                local levelDat = File(file, "level.dat")

                -- It's a world if it has level.dat or is a dimension folder pattern
                if levelDat:exists() or dirName:match("_nether$") or dirName:match("_the_end$") then
                    table.insert(worldFolders, file)
                end
            end
        end
    end

    script.logger:info("Found " .. #worldFolders .. " world folders to backup")

    -- Create compressed archive using jarchivelib
    script.logger:info("Creating compressed backup...")

    local archivePath = backupDirPath .. "/" .. backupName .. ".tar.xz"
    local archiveFile = File(archivePath)

    local success, err = pcall(function()
        synchronized(function()
            -- Create archive with all world folders
            -- Pass lua table directly - LuaLink should handle varargs conversion
            ARCHIVER:create(archiveFile:getName(), File(backupDirPath), table.unpack(worldFolders))
        end)
    end)

    if not success then
        script.logger:severe("Failed to create backup archive: " .. tostring(err))
        local onlinePlayers = java.luaify(server:getOnlinePlayers():toArray())
        for _, player in ipairs(onlinePlayers) do
            if player:isOp() then
                player:sendRichMessage("<red>Backup failed! Check console.</red>")
            end
        end
        return false
    end

    -- Calculate backup size
    local sizeMB = math.floor(archiveFile:length() / 1024 / 1024 * 10) / 10
    script.logger:info("Backup complete: " .. backupName .. ".tar.xz (" .. sizeMB .. " MB)")

    local onlinePlayers = java.luaify(server:getOnlinePlayers():toArray())
    for _, player in ipairs(onlinePlayers) do
        if player:isOp() then
            player:sendRichMessage("<green>Backup complete! (" .. sizeMB .. " MB)</green>")
        end
    end

    -- Clean up old backups
    cleanupOldBackups()

    return true
end

function copyDirectory(source, dest)
    script.logger:info("copyDirectory START")
    script.logger:info("  source type: " .. tostring(type(source)))
    script.logger:info("  dest type: " .. tostring(type(dest)))

    script.logger:info("  Getting source path...")
    local sourcePath = source:getAbsolutePath()
    script.logger:info("  Source path: " .. tostring(sourcePath))

    script.logger:info("  Getting dest path...")
    local destPath = dest:getAbsolutePath()
    script.logger:info("  Dest path: " .. tostring(destPath))

    script.logger:info("  Checking if dest exists...")
    local success, err = pcall(function()
        local exists = dest:exists()
        script.logger:info("  dest:exists() returned: " .. tostring(exists))
        if not exists then
            script.logger:info("  Creating dest directory...")
            dest:mkdirs()
            script.logger:info("  mkdirs() completed")
        end
    end)

    if not success then
        error("Failed to create dest directory: " .. tostring(err))
    end

    script.logger:info("  Listing source files...")
    local files
    success, err = pcall(function()
        files = source:listFiles()
        script.logger:info("  listFiles() returned: " .. tostring(files))
    end)

    if not success then
        error("Failed to list files in source: " .. tostring(err))
    end

    if files == nil then
        script.logger:warning("listFiles returned nil for: " .. tostring(sourcePath))
        return
    end

    -- Convert Java array to Lua table
    local filesTable = java.luaify(files)
    script.logger:info("  Converted to Lua table, count: " .. #filesTable)

    for _, file in ipairs(filesTable) do
        local fileName = file:getName()
        script.logger:info("  Processing file: " .. fileName)
        local destFile = File(dest, fileName)

        if file:isDirectory() then
            copyDirectory(file, destFile)
        else
            copyFile(file, destFile)
        end
    end
end

function copyFile(source, dest)
    local success, err = pcall(function()
        -- Use Lua native file I/O
        local sourcePath = source:getAbsolutePath()
        local destPath = dest:getAbsolutePath()

        local sourceFile = io.open(sourcePath, "rb")
        if not sourceFile then
            error("Could not open source file: " .. sourcePath)
        end

        local destFile = io.open(destPath, "wb")
        if not destFile then
            sourceFile:close()
            error("Could not open dest file: " .. destPath)
        end

        -- Copy in chunks to avoid memory issues with large files
        local chunkSize = 8192
        while true do
            local chunk = sourceFile:read(chunkSize)
            if not chunk then break end
            destFile:write(chunk)
        end

        sourceFile:close()
        destFile:close()
    end)

    if not success then
        error("Failed to copy file " .. tostring(source:getName()) .. ": " .. tostring(err))
    end
end

function deleteDirectory(dir)
    local files = dir:listFiles()
    if files ~= nil then
        local filesTable = java.luaify(files)
        for _, file in ipairs(filesTable) do
            if file:isDirectory() then
                deleteDirectory(file)
            else
                file:delete()
            end
        end
    end
    dir:delete()
end

-- Add missing utility function
if not utils.keys then
    utils.keys = function(tbl)
        local keys = {}
        for k, _ in pairs(tbl) do
            table.insert(keys, k)
        end
        return keys
    end
end

-- Commands

script:registerCommand(function(sender, args)
    if not sender:hasPermission("autobackup.backup") then
        sender:sendRichMessage("<red>No permission!</red>")
        return
    end

    sender:sendRichMessage("<yellow>Starting manual backup...</yellow>")
    createBackup()
end, {
    name = "backup",
    description = "Manually trigger a backup",
    usage = "/backup",
    permission = "autobackup.backup"
})

script:registerCommand(function(sender, args)
    if not sender:hasPermission("autobackup.list") then
        sender:sendRichMessage("<red>No permission!</red>")
        return
    end

    local backups = getBackupList()

    if #backups == 0 then
        sender:sendRichMessage("<yellow>No backups found</yellow>")
        return
    end

    sender:sendRichMessage("<gold><bold>Available Backups:</bold></gold>")

    for i, backup in ipairs(backups) do
        local size = backup.file:length()
        local sizeMB = math.floor(size / 1024 / 1024 * 10) / 10
        local dateStr = string.format("%04d-%02d-%02d %02d:%02d:%02d",
            backup.year, backup.month, backup.day, backup.hour, backup.min, backup.sec)

        sender:sendRichMessage("<gray>" ..
            i .. ".</gray> <white>" .. dateStr .. "</white> <gray>(" .. sizeMB .. " MB)</gray>")
    end
end, {
    name = "backups",
    description = "List all backups",
    usage = "/backups",
    permission = "autobackup.list",
    aliases = { "listbackups" }
})

script:registerCommand(function(sender, args)
    if not sender:hasPermission("autobackup.reload") then
        sender:sendRichMessage("<red>No permission!</red>")
        return
    end

    loadConfig()

    -- Restart task with new interval
    if backupTask then
        scheduler:cancel(backupTask)
    end

    local intervalTicks = config.intervalHours * 60 * 60 * 20
    backupTask = scheduler:runRepeating(function()
        createBackup()
    end, intervalTicks, intervalTicks)

    sender:sendRichMessage("<green>Config reloaded!</green>")
end, {
    name = "autobackup-reload",
    description = "Reload autobackup configuration",
    usage = "/autobackup-reload",
    permission = "autobackup.reload"
})

-- Lifecycle

script:onLoad(function()
    saveDefaultConfig()
    loadConfig()

    script.logger:info("AutoBackup plugin loaded")

    -- Schedule automatic backups
    local intervalTicks = config.intervalHours * 60 * 60 * 20
    backupTask = scheduler:runRepeating(function()
        createBackup()
    end, intervalTicks, intervalTicks)

    script.logger:info("Scheduled backups every " .. config.intervalHours .. " hour(s)")
end)

script:onUnload(function()
    if backupTask then
        scheduler:cancel(backupTask)
    end

    script.logger:info("AutoBackup plugin unloaded")
end)
