-- AutoBackup Async Plugin (BROKEN VERSION)
-- This version fails with Java method resolution errors in async threads
-- Submitted for help from LuaLink experts

-- Imports
local File = import("java.io.File")
local FileInputStream = import("java.io.FileInputStream")
local FileOutputStream = import("java.io.FileOutputStream")
local ZipOutputStream = import("java.util.zip.ZipOutputStream")
local ZipEntry = import("java.util.zip.ZipEntry")
local YamlConfiguration = import("org.bukkit.configuration.file.YamlConfiguration")
local Files = import("java.nio.file.Files")
local Paths = import("java.nio.file.Paths")
local StandardCopyOption = import("java.nio.file.StandardCopyOption")

-- Module requires
local utils = require("common.utils")

-- Constants
local PLUGIN_NAME = "autobackup-async-broken"
local DEFAULT_INTERVAL_HOURS = 1

-- State
local backupInProgress = false

-- Helper Functions

local function getBackupDir()
    local dataDir = utils.getDataDir(PLUGIN_NAME)
    local backupDir = File(dataDir, "backups")
    if not backupDir:exists() then
        backupDir:mkdirs()
    end
    return backupDir
end

-- APPROACH 1: Using Java NIO Files.copy()
-- FAILS with: "bad argument #1 to 'copy' (__jclass__ expected, got userdata)"
local function copyFileNIO(source, dest)
    local sourcePath = source:toPath()
    local destPath = dest:toPath()
    -- This line fails in async thread:
    Files.copy(sourcePath, destPath, StandardCopyOption.REPLACE_EXISTING)
end

-- APPROACH 2: Using Java streams with byte array
-- FAILS with: "bad argument #1 to 'java.new': __jclass__ or __jobject__ expected"
local function copyFileWithByteArray(source, dest)
    local fis = FileInputStream(source)
    local fos = FileOutputStream(dest)
    -- This line fails in async thread:
    local buffer = java.new("byte[]", 8192)
    local len = fis:read(buffer)

    while len > 0 do
        fos:write(buffer, 0, len)
        len = fis:read(buffer)
    end

    fis:close()
    fos:close()
end

-- APPROACH 3: Using Java NIO Files.walk()
-- FAILS with: "bad argument #1 to 'walk' (__jclass__ expected, got userdata)"
local function copyDirectoryNIO(sourcePath, destPath)
    -- This line fails in async thread:
    local stream = Files.walk(sourcePath)
    local pathIterator = stream:iterator()

    while pathIterator:hasNext() do
        local path = pathIterator:next()

        if not Files.isDirectory(path) then
            local fileName = path:getFileName():toString()
            if fileName ~= "session.lock" then
                local relativePath = sourcePath:relativize(path)
                local targetPath = destPath:resolve(relativePath)

                local parent = targetPath:getParent()
                if parent ~= nil and not Files.exists(parent) then
                    Files.createDirectories(parent)
                end

                Files.copy(path, targetPath, StandardCopyOption.REPLACE_EXISTING)
            end
        end
    end

    stream:close()
end

-- APPROACH 4: Traditional File methods
-- FAILS with: "no matching method found" on file:exists() or file:listFiles()
local function copyDirectory(source, dest)
    -- This line sometimes fails in async:
    if not dest:exists() then
        dest:mkdirs()
    end

    -- This line often fails in async:
    local files = source:listFiles()
    if files ~= nil then
        local filesTable = java.luaify(files)
        for _, file in ipairs(filesTable) do
            local destFile = File(dest, file:getName())

            if file:isDirectory() then
                copyDirectory(file, destFile)
            else
                -- Choose one of the failing approaches above
                copyFileNIO(file, destFile)
            end
        end
    end
end

local function createBackup()
    if backupInProgress then
        script.logger:warning("Backup already in progress")
        return
    end

    backupInProgress = true
    script.logger:info("Starting async backup process...")

    -- Step 1: Save all loaded worlds (on main thread - this works)
    scheduler:run(function()
        local loadedWorlds = java.luaify(server:getWorlds():toArray())
        for _, world in ipairs(loadedWorlds) do
            script.logger:info("Saving world: " .. world:getName())
            world:save()
        end

        -- Get server directory and find all world folders
        local serverDirFile = File("."):getAbsoluteFile():getParentFile()
        local serverDirPath = serverDirFile:getAbsolutePath()
        local serverFiles = serverDirFile:listFiles()
        local worldFolders = {}

        if serverFiles ~= nil then
            local filesTable = java.luaify(serverFiles)
            for _, file in ipairs(filesTable) do
                if file:isDirectory() then
                    local dirName = file:getName()
                    local levelDat = File(file, "level.dat")

                    if levelDat:exists() or dirName:match("_nether$") or dirName:match("_the_end$") then
                        table.insert(worldFolders, dirName)
                    end
                end
            end
        end

        -- Step 2: Copy in async thread (THIS IS WHERE IT BREAKS)
        scheduler:runAsync(function()
            local timestamp = os.date("%Y-%m-%d_%H-%M-%S")
            local backupName = "backup_" .. timestamp

            local backupDir = getBackupDir()
            local backupDirPath = backupDir:getAbsolutePath()
            local tempDirPath = backupDirPath .. "/" .. backupName
            local tempDir = File(tempDirPath)

            -- This might fail in async:
            tempDir:mkdirs()

            local copySuccess = true
            for _, worldName in ipairs(worldFolders) do
                local sourceWorld = File(serverDirPath, worldName)
                local destWorld = File(tempDirPath, worldName)

                script.logger:info("Copying world (async): " .. worldName)

                local success, err = pcall(function()
                    -- Create destination
                    destWorld:mkdirs()

                    -- Try NIO approach (fails)
                    local sourcePath = sourceWorld:toPath()
                    local destPath = destWorld:toPath()
                    copyDirectoryNIO(sourcePath, destPath)

                    -- OR try traditional approach (also fails)
                    -- copyDirectory(sourceWorld, destWorld)
                end)

                if not success then
                    script.logger:severe("Failed to copy world " .. worldName .. ": " .. tostring(err))
                    copySuccess = false
                    break
                end
            end

            if not copySuccess then
                scheduler:run(function()
                    utils.broadcastMessage("<red>Backup failed! Check console.</red>")
                end)
                backupInProgress = false
                return
            end

            scheduler:run(function()
                utils.broadcastMessage("<green>Backup complete!</green>")
            end)

            backupInProgress = false
        end)
    end)
end

-- Commands
script:registerCommand(function(sender, args)
    if not sender:hasPermission("autobackup.backup") then
        sender:sendRichMessage("<red>No permission!</red>")
        return
    end

    if backupInProgress then
        sender:sendRichMessage("<yellow>Backup already in progress!</yellow>")
        return
    end

    sender:sendRichMessage("<yellow>Starting async backup...</yellow>")
    createBackup()
end, {
    name = "backup-async-test",
    description = "Test async backup (broken)",
    usage = "/backup-async-test",
    permission = "autobackup.backup"
})

-- Lifecycle
script:onLoad(function()
    script.logger:info("AutoBackup Async (BROKEN) plugin loaded")
    script.logger:info("This version demonstrates async Java method failures")
end)

script:onUnload(function()
    script.logger:info("AutoBackup Async (BROKEN) plugin unloaded")
end)
