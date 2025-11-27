# LuaLink Plugin Development Guide

A comprehensive guide to writing Minecraft plugins using LuaLink and Lua.

## Table of Contents

- [Project Structure](#project-structure)
- [Basic Plugin Setup](#basic-plugin-setup)
- [Importing Java Classes](#importing-java-classes)
- [Loading Shared Modules](#loading-shared-modules)
- [Common Patterns](#common-patterns)
- [Minigame Development](#minigame-development)
- [Gotchas and Solutions](#gotchas-and-solutions)
- [Limitations and Known Issues](#limitations-and-known-issues)
- [Best Practices](#best-practices)
- [API Reference](#api-reference)
- [Example Plugins](#example-plugins)
- [Third-Party Plugin Integration](./INTEGRATION_EXAMPLES.md)
- [Getting Help](#getting-help)

## Project Structure

```
plugins/LuaLink/
├── libs/                      # Shared libraries (global)
│   └── common/
│       ├── utils.lua         # Common utilities
│       └── minigame.lua      # Minigame state management
└── scripts/                   # Individual plugins
    ├── myplugin/
    │   └── main.lua          # Entry point (required)
    └── anotherplugin/
        └── main.lua
```

**Key Points:**
- Each plugin must be in its own folder under `scripts/`
- Entry point must be named `main.lua`
- Shared libraries go in `libs/` (accessible to all plugins)
- Use plugin name for commands: `/lualink load myplugin`, `/lualink reload myplugin`

## Basic Plugin Setup

### Minimal Plugin

```lua
-- myplugin/main.lua

-- Lifecycle hooks
script:onLoad(function()
    script.logger:info("Plugin loaded!")
end)

script:onUnload(function()
    script.logger:info("Plugin unloaded!")
end)
```

### With Commands

```lua
script:registerCommand(function(sender, args)
    if not sender:getClass():getName():match("CraftPlayer") then
        sender:sendRichMessage("<red>Only players can use this!</red>")
        return
    end
    
    local player = sender
    player:sendRichMessage("<green>Hello!</green>")
end, {
    name = "hello",
    aliases = {"hi"},
    description = "Say hello",
    usage = "/hello",
    permission = "myplugin.hello"
})
```

### With Event Listeners

```lua
script:registerListener("org.bukkit.event.player.PlayerJoinEvent", function(event)
    local player = event:getPlayer()
    player:sendRichMessage("<green>Welcome!</green>")
end)
```

## Importing Java Classes

Always import Java classes at the top of your file:

```lua
local Material = import("org.bukkit.Material")
local Location = import("org.bukkit.Location")
local ItemStack = import("org.bukkit.inventory.ItemStack")
local GameMode = import("org.bukkit.GameMode")
local File = import("java.io.File")
local YamlConfiguration = import("org.bukkit.configuration.file.YamlConfiguration")
```

**Common Imports:**
- Bukkit API: `org.bukkit.*`
- Paper API: `io.papermc.paper.*`
- Java I/O: `java.io.File`
- Java Utils: `java.util.*`

**Documentation:**
- Paper Javadocs: https://jd.papermc.io/
- Bukkit API: https://hub.spigotmc.org/javadocs/bukkit/

## Loading Shared Modules

### Using require()

LuaLink uses standard Lua `require()` for modules:

```lua
local utils = require("common.utils")
local minigame = require("common.minigame")
```

**Module Search Paths:**
1. `scripts/yourplugin/` - Plugin-local modules
2. `scripts/libs/` - Global shared libraries

**Example Structure:**
```lua
-- In your plugin
local myHelper = require("helper")  -- Loads scripts/yourplugin/helper.lua
local utils = require("common.utils")  -- Loads scripts/libs/common/utils.lua
```

### Creating a Module

```lua
-- scripts/libs/common/mymodule.lua
local M = {}

function M.doSomething(param)
    return "Result: " .. param
end

return M  -- MUST return the module table
```

**Real-World Module Example:**

The [repairall plugin](https://codeberg.org/Saturn745/LuaLink-Scripts/src/branch/master/repairall/experience.lua) includes a reusable `experience.lua` module for XP calculations:

```lua
-- experience.lua - Reusable XP utility module
local experience = {}

function experience.getExpFromLevel(level)
    if level > 30 then
        return math.floor(4.5 * level * level - 162.5 * level + 2220)
    elseif level > 15 then
        return math.floor(2.5 * level * level - 40.5 * level + 360)
    else
        return level * level + 6 * level
    end
end

function experience.getPlayerExp(player)
    local level = player:getLevel()
    local progress = player:getExp()
    return experience.getExpFromLevel(level) + math.floor(getExpToNext(level) * progress + 0.5)
end

function experience.setPlayerExp(player, exp)
    -- Calculate level and progress, then set
    player:setLevel(level)
    player:setExp(progress)
end

return experience
```

This can be used by any plugin needing XP calculations.

## Common Patterns

### Iterating Java Collections

**GOTCHA:** Java collections aren't directly iterable in Lua. Use `java.luaify()`:

```lua
-- ❌ WRONG - This will error
for i, player in ipairs(world:getPlayers()) do
    -- ERROR: Can't iterate Java ArrayList
end

-- ✅ CORRECT - Convert to Lua table first
local worlds = server:getWorlds()
for i = 0, worlds:size() - 1 do
    local world = worlds:get(i)
    local players = java.luaify(world:getPlayers():toArray())
    for _, player in ipairs(players) do
        -- Works!
    end
end
```

### Null Checks

**GOTCHA:** Java methods can return null. Always check!

```lua
local player = server:getPlayer("PlayerName")
if player ~= nil then
    player:sendMessage("Hello!")
else
    script.logger:warning("Player not found")
end
```

### Error Handling

**GOTCHA:** Java exceptions need pcall() to catch:

```lua
local success, result = pcall(function()
    return ItemStack:deserialize(data)
end)

if success then
    inventory:setItem(slot, result)
else
    script.logger:warning("Failed to deserialize: " .. tostring(result))
end
```

### YAML Configuration

```lua
local config = YamlConfiguration()
config:set("key", "value")
config:set("number", 42)
config:set("nested.key", "value")
config:save(file)

-- Loading
local config = YamlConfiguration:loadConfiguration(file)
local value = config:getString("key", "default")
local number = config:getInt("number", 0)
```

## Minigame Development

Use the minigame helper module for automatic state management:

### Basic Minigame Structure

```lua
local minigame = require("common.minigame")

-- When player joins minigame
function startMinigame(player)
    -- Save their current state (location, inventory, health, etc.)
    minigame.savePlayerState("mygame", player)
    
    -- Prepare player for minigame
    minigame.preparePlayer(player, GameMode.SURVIVAL)
    
    -- Give them items
    minigame.giveInfiniteItem(player, Material.SNOWBALL, 16)
    
    -- Teleport to arena
    player:teleport(arenaLocation)
end

-- When minigame ends
function endMinigame(player)
    -- Restore everything (teleports back, restores inventory, etc.)
    if minigame.restorePlayerState("mygame", player) then
        player:sendRichMessage("<green>State restored!</green>")
    end
end
```

### Available Minigame Functions

```lua
-- State Management
minigame.savePlayerState(minigameName, player) -- Returns boolean
minigame.restorePlayerState(minigameName, player) -- Returns boolean
minigame.hasPlayerState(minigameName, player) -- Check if state exists
minigame.deletePlayerState(minigameName, uuid) -- Manual cleanup

-- Player Preparation
minigame.preparePlayer(player, gameMode) -- Heal, feed, clear effects
minigame.giveInfiniteItem(player, material, amount, slots) -- Fill inventory

-- File Management
minigame.getStateDir(minigameName) -- Get state directory
minigame.getStateFile(minigameName, uuid) -- Get state file
```

### What savePlayerState() Saves

- Location (world, x, y, z, yaw, pitch)
- Inventory (all items, handles modern components)
- Health, food level, saturation, exhaustion
- Game mode
- Flight status
- Experience (level, exp, total exp)
- Fall distance and velocity (resets on restore)

## Gotchas and Solutions

### 1. Item Serialization (Modern Minecraft)

**PROBLEM:** Modern Minecraft (1.20.5+) uses components, not NBT. `ItemStack:serialize()` and `ItemStack:deserialize()` don't work reliably.

**SOLUTION:** Use byte serialization with Base64 encoding:

```lua
local Base64 = import("java.util.Base64")

-- Saving items
local success, serialized = pcall(function()
    local bytes = item:serializeAsBytes()
    return Base64:getEncoder():encodeToString(bytes)
end)

if success and serialized ~= nil then
    config:set("items." .. slot, serialized)
end

-- Loading items
local base64Data = config:getString("items." .. slot)
if base64Data ~= nil then
    local success, item = pcall(function()
        local bytes = Base64:getDecoder():decode(base64Data)
        return ItemStack:deserializeBytes(bytes)
    end)
    if success and item ~= nil then
        inventory:setItem(slot, item)
    end
end
```

The minigame helper (v1.1+) already does this for you.

### 2. Block Operations

**PROBLEM:** Block operations can throw "no matching method found" errors.

**SOLUTION:** Wrap in pcall() and add null checks:

```lua
local success, err = pcall(function()
    local block = world:getBlockAt(x, y, z)
    if block == nil then return end
    
    local blockType = block:getType()
    if blockType == nil then return end
    
    block:setType(Material.AIR)
end)

if not success then
    script.logger:warning("Error updating block: " .. tostring(err))
end
```

### 3. Loading Modules

**PROBLEM:** Old examples might use `script:getLuaState()` which doesn't exist.

**SOLUTION:** Use standard Lua `require()`:

```lua
-- ❌ WRONG - Old API
local luaState = script:getLuaState()
luaState:loadFile(path)

-- ✅ CORRECT - Standard Lua
local utils = require("common.utils")
```

### 4. Accessing Server Globals

Available globals in your scripts:
- `server` - Bukkit.getServer()
- `script` - Your script instance
- `scheduler` - Task scheduler

```lua
local player = server:getPlayer("PlayerName")
scheduler:runDelayed(function()
    -- Do something later
end, 20) -- 20 ticks = 1 second
```

### 5. String Formatting UUIDs

**PROBLEM:** File names can't contain dashes.

**SOLUTION:** Replace dashes with underscores:

```lua
local uuid = player:getUniqueId():toString():gsub("-", "_")
local file = File(dataDir, uuid .. ".yml")
```

### 6. Boolean Storage in YAML

**PROBLEM:** Lua booleans don't always serialize correctly to YAML.

**SOLUTION:** Store as strings:

```lua
-- Saving
config:set("allowFlight", player:getAllowFlight() and "true" or "false")

-- Loading
local allowFlightStr = config:getString("allowFlight", "false")
player:setAllowFlight(allowFlightStr == "true")
```

The minigame helper does this automatically.

### 7. Java Collection Iteration

**PROBLEM:** "bad argument #1" errors when iterating Java collections like Lists, Sets, or Arrays.

**CAUSE:** Java collections aren't directly iterable with Lua's `ipairs()` or `for` loops. You need to convert them first.

**SOLUTION:** Use `java.luaify()` to convert Java collections to Lua tables:

```lua
-- ❌ WRONG - Can't iterate Java ArrayList directly
for i, player in ipairs(world:getPlayers()) do
    -- ERROR: bad argument #1
end

-- ✅ CORRECT - Convert to Lua table first
local players = java.luaify(world:getPlayers():toArray())
for _, player in ipairs(players) do
    player:sendMessage("Hello!")
end

-- ✅ ALTERNATIVE - Use Java's iteration methods
local players = world:getPlayers()
for i = 0, players:size() - 1 do
    local player = players:get(i)
    player:sendMessage("Hello!")
end

-- ✅ ALTERNATIVE - Use Java Streams API
world:getPlayers():forEach(function(player)
    player:sendMessage("Hello!")
end)
```



### 8. Scheduler Tasks

```lua
-- Run once, immediately
scheduler:run(function() end)

-- Run after delay (20 ticks = 1 second)
scheduler:runDelayed(function() end, 20)

-- Run repeatedly (delay, then period)
scheduler:runRepeating(function() end, 20, 20)

-- Async versions available (scheduler wrapper handles synchronization)
scheduler:runAsync(function() end)
```

### 9. Rich Messages (MiniMessage Format)

```lua
player:sendRichMessage("<green>Colored text</green>")
player:sendRichMessage("<gold><bold>Bold gold text</bold></gold>")
player:sendRichMessage("<gradient:blue:green>Gradient text</gradient>")
player:sendRichMessage("<rainbow>Rainbow text!</rainbow>")
```

Documentation: https://docs.advntr.dev/minimessage/

## Limitations and Known Issues

This section documents things we haven't figured out how to do properly yet, or behaviours that don't work as expected.

### Async Thread Behaviour (CONFIRMED LIMITATION)

**ISSUE:** Java method resolution does NOT work reliably in `scheduler:runAsync()` threads.

**CONFIRMED BEHAVIOURS:**
- Java instance method calls fail: `file:exists()` → "no matching method found"
- Java static method calls fail: `Files.copy()` → "bad argument #1 to 'copy' (__jclass__ expected, got userdata)"
- Java array creation fails: `java.new("byte[]", 8192)` → "bad argument #1 to 'java.new'"
- The same code works perfectly in `scheduler:run()` (sync tasks)
- Even wrapping in `synchronized()` doesn't fix async issues

**WHY THIS HAPPENS:**
LuaLink's Java bridge doesn't properly resolve method signatures when called from async threads, even though the Java objects themselves are valid.

**WHAT WORKS IN ASYNC:**
- Pure Lua code and logic
- Lua's native I/O: `io.open()`, `io.read()`, `io.write()`
- String manipulation, table operations
- Math operations

**WHAT DOESN'T WORK IN ASYNC:**
- Any Java method calls on objects
- Creating Java objects
- Static method calls on Java classes
- Java collections (even with `java.luaify()`)

**SOLUTION:** Use synchronous tasks for Java operations:

```lua
-- ✅ CORRECT - All Java calls on main thread
scheduler:run(function()
    local file = File("path")
    if file:exists() then
        -- Do work with Java API
    end
end)

-- ✅ ALTERNATIVE - Java data collection on main, processing in async
scheduler:run(function()
    -- Collect data using Java API
    local paths = {}
    local files = dir:listFiles()
    local filesTable = java.luaify(files)
    for _, file in ipairs(filesTable) do
        table.insert(paths, file:getAbsolutePath())
    end
    
    -- Now process in async using only Lua I/O
    scheduler:runAsync(function()
        for _, path in ipairs(paths) do
            local f = io.open(path, "r")
            -- Process with Lua I/O
            f:close()
        end
    end)
end)

-- ❌ WRONG - Don't call Java methods in async
scheduler:runAsync(function()
    local file = File("path")
    file:exists()  -- ERROR: no matching method found
end)
```

**IMPACT:** For most use cases, brief pauses on the main thread are acceptable. Hourly backups, periodic saves, etc. can all run synchronously without noticeable lag.

### File Compression in Lua

**ISSUE:** Creating compressed archives (`.zip`, `.tar.gz`, etc.) from Lua is extremely difficult due to Java bridge limitations.

**WHY IT'S HARD:**
1. Java's `ZipOutputStream` requires byte arrays created with `java.new("byte[]", size)` - this fails in LuaLink
2. Writing strings byte-by-byte to `ZipOutputStream` produces corrupt archives
3. Java NIO's `Files.copy()` and `Files.walk()` fail with method resolution errors
4. No native Lua compression libraries available in LuaLink

**WHAT WE'VE TRIED:**

```lua
-- ❌ Doesn't work - java.new fails
local buffer = java.new("byte[]", 8192)

-- ❌ Doesn't work - produces corrupt zip
for i = 1, #content do
    zipStream:write(content:byte(i))
end

-- ❌ Doesn't work - static method resolution fails
Files.copy(sourcePath, destPath, StandardCopyOption.REPLACE_EXISTING)
```

**WHAT WORKS:**

```lua
-- ✅ Lua native I/O works perfectly
local source = io.open(sourcePath, "rb")
local dest = io.open(destPath, "wb")
local chunk = source:read(8192)
while chunk do
    dest:write(chunk)
    chunk = source:read(8192)
end
source:close()
dest:close()
```

**RECOMMENDED APPROACH:**
Store backups uncompressed. For a typical Minecraft server:
- Disk space is cheap
- Retention policies (hourly/daily/monthly) keep space manageable
- Uncompressed folders are easier to browse and restore
- No corruption risk from failed compression

**ALTERNATIVE:** If compression is essential, shell out to system commands (platform-specific):

```lua
-- macOS/Linux only
os.execute('tar -czf backup.tar.gz world/')

-- Not portable to Windows!
```

**FUTURE:** This might be fixed if LuaLink improves Java array handling or adds native compression support.

### Add Your Issues Here

If you discover limitations or problems you can't solve, document them here with:
- What you're trying to do
- What errors you get
- What you've tried
- Any partial workarounds

This helps others and might lead to solutions.

## Best Practices

### 1. Use Shared Utilities

Don't duplicate code. Use the common utilities:

```lua
local utils = require("common.utils")

-- Broadcasting
utils.broadcastMessage("<green>Server message</green>")

-- Iterating players
utils.forEachPlayer(function(player)
    player:sendMessage("Hello")
end)

-- Data directories
local dataDir = utils.getDataDir("myplugin")

-- YAML helpers
utils.saveYaml(file, {key = "value"})
local data = utils.loadYaml(file)

-- Player lookup
local player = utils.getPlayerByName("PlayerName")
local count = utils.getPlayerCount()
```

### 2. Clean Up Resources

```lua
script:onUnload(function()
    -- Cancel tasks
    if myTask then
        scheduler:cancel(myTask)
    end
    
    -- Clear tables
    myTable = {}
    
    -- Note: File-based state persists automatically
end)
```

### 3. Logging

```lua
script.logger:info("Information message")
script.logger:warning("Warning message")
script.logger:severe("Error message")
```

### 4. Data Storage

**Persistent Data:** Use files in your plugin's data directory

```lua
local dataDir = utils.getDataDir("myplugin")
local file = File(dataDir, "data.yml")

-- Or use minigame helpers for state management
```

**Temporary Data:** Use Lua tables (cleared on reload)

```lua
local games = {}  -- Lives only while plugin is loaded
```

### 5. Player Validation

```lua
function handleCommand(sender, args)
    -- Check if sender is a player
    if not sender:getClass():getName():match("CraftPlayer") then
        sender:sendRichMessage("<red>Players only!</red>")
        return
    end
    
    local player = sender
    
    -- Check permission
    if not player:hasPermission("myplugin.command") then
        player:sendRichMessage("<red>No permission!</red>")
        return
    end
    
    -- Your code here
end
```

### 6. Code Organization

```lua
-- 1. Imports
local Material = import("org.bukkit.Material")

-- 2. Module requires
local utils = require("common.utils")

-- 3. Constants
local COUNTDOWN_SECONDS = 5

-- 4. State variables
local games = {}

-- 5. Helper functions
local function createGame() end

-- 6. Commands
script:registerCommand(...)

-- 7. Event listeners
script:registerListener(...)

-- 8. Lifecycle hooks
script:onLoad(function() end)
script:onUnload(function() end)
```

**Modular Command Organization:**

For larger plugins, split commands into separate files:

```lua
-- main.lua
print("Loading commands...")
require("cmds.init")

-- cmds/init.lua
require("cmds.teleport")
require("cmds.home")
require("cmds.warp")

-- cmds/teleport.lua
script:registerCommand(function(sender, args)
    -- teleport logic
end, {name = "tp"})
```

### 7. Type Annotations

Use Lua type annotations for better IDE support:

```lua
script:registerCommand(function(sender, args)
    -- Cast sender to Player type
    ---@cast sender org.bukkit.entity.Player
    
    -- Now IDE knows sender is a Player
    local inventory = sender:getInventory()
    local health = sender:getHealth()
end, {name = "mycommand"})

-- Cast after checking instance type
local meta = item:getItemMeta()
if Damageable.class:isInstance(meta) then
    ---@cast meta org.bukkit.inventory.meta.Damageable
    local damage = meta:getDamage()
end
```

### 8. Loop Optimization with goto

Use `goto continue` to skip loop iterations cleanly:

```lua
for i = 0, inventory:getSize() - 1 do
    local item = inventory:getItem(i)
    
    -- Skip empty slots
    if not item or item:isEmpty() then
        goto continue
    end
    
    -- Skip items without meta
    local meta = item:getItemMeta()
    if not meta then
        goto continue
    end
    
    -- Process valid items
    processItem(item, meta)
    
    ::continue::
end
```

### 9. Java Class Instance Checking

Check if an object is an instance of a Java class:

```lua
local Damageable = import "org.bukkit.inventory.meta.Damageable"
local Player = import "org.bukkit.entity.Player"

-- Check if meta is damageable
if Damageable.class:isInstance(meta) then
    ---@cast meta org.bukkit.inventory.meta.Damageable
    meta:setDamage(0)
end

-- Check if sender is a player
if Player.class:isInstance(sender) then
    ---@cast sender org.bukkit.entity.Player
    sender:sendMessage("Hello player!")
end
```

### 10. String Formatting

Use `string.format` for cleaner string construction:

```lua
-- Instead of concatenation
sender:sendRichMessage("<green>You have " .. balance .. " coins</green>")

-- Use string.format
sender:sendRichMessage(string.format(
    "<green>You have <gold>%.2f</gold> coins</green>",
    balance
))

-- Multiple values
sender:sendRichMessage(string.format(
    "<green>Repaired %d items for %.1f XP</green>",
    itemCount,
    xpCost
))
```

### 11. File I/O Best Practices

Always close file handles and handle errors:

```lua
local DATA_FILE = script:getDataFolder() .. "/data.txt"

-- Reading
local function readData()
    local file = io.open(DATA_FILE, "r")
    if not file then
        print("Could not open file for reading")
        return nil
    end
    
    local content = file:read("*a")  -- Read all
    file:close()
    return content
end

-- Writing
local function writeData(content)
    local file = io.open(DATA_FILE, "w")
    if not file then
        print("Could not open file for writing")
        return false
    end
    
    file:write(content)
    file:close()
    return true
end

-- Ensure file exists on load
script:onLoad(function()
    local file = io.open(DATA_FILE, "a")  -- Append mode creates if missing
    if file then
        file:close()
    end
end)
```

### 12. Service Provider Integration

Load plugin APIs through the service manager:

```lua
local VAULT_ECONOMY = import "net.milkbowl.vault.economy.Economy"
local econ = nil

script:onLoad(function()
    local registration = server:getServicesManager():getRegistration(VAULT_ECONOMY.class)
    if registration ~= nil then
        econ = registration:getProvider()
        print("Economy service loaded")
    else
        print("Economy not available")
    end
end)

-- Always check before use
if econ then
    local balance = econ:getBalance(player)
end
```

See [INTEGRATION_EXAMPLES.md](./INTEGRATION_EXAMPLES.md) for detailed integration guides for PlaceholderAPI, Vault, LuckPerms, and more.

### 13. CompletableFuture Patterns

Handle async operations from modern APIs:

```lua
-- Use :join() to wait synchronously
local user = api:loadUser(uuid):join()
print("Loaded: " .. user:getName())

-- Use :thenAccept() for async callbacks
api:getUserHomes(player):thenAccept(function(homes)
    ---@cast homes java.util.List
    for i = 1, homes:size() do
        local home = homes:get(i - 1)
        print("Home: " .. home:getName())
    end
end)
```

## API Reference

### Script Object

```lua
script.logger:info(message)      -- Logging
script:registerCommand(...)       -- Register command
script:registerListener(...)      -- Register event listener
script:onLoad(function() end)     -- Called after load
script:onUnload(function() end)   -- Called before unload
```

### Scheduler

```lua
scheduler:run(function() end)
scheduler:runDelayed(function() end, ticks)
scheduler:runRepeating(function() end, delay, period)
scheduler:runAsync(function() end)  -- Use with caution!
scheduler:cancel(task)
```

### Server

```lua
server:getPlayer(name)           -- Get online player by name
server:getWorld(name)            -- Get world by name
server:getWorlds()               -- Get all worlds (Java collection)
server:getOnlinePlayers()        -- Get all online players (Java collection)
server:broadcastMessage(msg)     -- Broadcast to everyone
```

### Common Utils (require("common.utils"))

```lua
utils.broadcastMessage(message)
utils.forEachPlayer(callback)
utils.getDataDir(pluginName)
utils.saveYaml(file, data)
utils.loadYaml(file)
utils.formatUuid(uuid)
utils.isEmpty(str)
utils.getPlayerCount()
utils.getPlayerByName(name)
```

### Minigame Utils (require("common.minigame"))

```lua
minigame.savePlayerState(minigameName, player)
minigame.restorePlayerState(minigameName, player)
minigame.hasPlayerState(minigameName, player)
minigame.deletePlayerState(minigameName, uuid)
minigame.giveInfiniteItem(player, material, amount, slots)
minigame.preparePlayer(player, gameMode)
minigame.getStateDir(minigameName)
minigame.getStateFile(minigameName, uuid)
```

## Example Plugins

### Built-in Examples

See the example scripts in this repository for complete working examples:

- **eggfight/** - Full minigame with arenas, state management
- **skyblock/** - Persistent world with state swapping
- **vanish/** - Simple utility plugin with disk persistence

### Real-World Examples

The [Saturn745/LuaLink-Scripts](https://codeberg.org/Saturn745/LuaLink-Scripts) repository contains production-ready examples:

- **baltop-rank/** - PlaceholderAPI & LuckPerms integration, scheduled tasks, file persistence
- **repairall/** - Command with XP calculations, inventory iteration, custom utility modules
- **chat-manager/** - Event listeners for chat/commands/signs, modular design with sub-listeners
- **launch-command/** - Vector manipulation, player velocity
- **clear-dropped-items/** - World entity management, scheduled cleanup tasks
- **vault-test/** - Vault Economy service provider integration
- **json-test/** - JSON data persistence patterns
- **papi-parse-exploit-fix/** - String manipulation, security patterns
- **no-goat-horn-delay/** - Simple event listener, material cooldowns
- **huskhomes-gui/** - CompletableFuture patterns, Floodgate API integration

These examples demonstrate best practices for:
- Third-party plugin integration (PlaceholderAPI, Vault, LuckPerms, Floodgate)
- Modular code organization
- File and JSON persistence
- Async/CompletableFuture patterns
- Type annotations and class instance checking

## Getting Help

1. Check Paper Javadocs: https://jd.papermc.io/
2. Check Bukkit API docs: https://hub.spigotmc.org/javadocs/bukkit/
3. Look at example plugins in `example-scripts/`
4. Test with `/lualink reload <plugin>` to see errors

## Quick Troubleshooting

**"attempt to call global X (a nil value)"**
- Did you import the Java class? `local X = import("...")`
- Did you require the module? `local utils = require("common.utils")`
- Check spelling and case sensitivity

**"no matching method found"**
- Add null checks: `if obj ~= nil then`
- Wrap in pcall() for better error messages
- Check the Paper Javadocs for correct method signature

**"Module 'X' not found"**
- Is the module in `scripts/libs/`?
- Check the path: `require("common.utils")` → `libs/common/utils.lua`
- Does the module `return M` at the end?

**Items not saving/loading**
- Use minigame helpers instead of manual serialization
- Modern Minecraft components may not serialize well
- Add pcall() around item serialization

**Player state not restoring**
- Check logs for "Failed to restore state"
- Verify state file exists in data directory
- Use minigame.restorePlayerState() with error checking