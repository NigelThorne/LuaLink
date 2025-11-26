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
- [Best Practices](#best-practices)
- [API Reference](#api-reference)

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

**PROBLEM:** Modern Minecraft (1.20.5+) uses components, not NBT. `ItemStack:serialize()` can fail.

**SOLUTION:** Always wrap in pcall():

```lua
local success, serialized = pcall(function()
    return item:serialize()
end)

if success and serialized ~= nil then
    config:set("items." .. slot, serialized)
else
    script.logger:warning("Failed to serialize item in slot " .. slot)
end
```

The minigame helper already does this for you.

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

### 7. Java Method Calls in Async Threads

**PROBLEM:** Java method resolution fails in `scheduler:runAsync()` threads.

**SYMPTOMS:**
- "no matching method found" errors
- "bad argument #1" errors for valid Java objects
- Static method calls like `Files.walk()` fail

**EXPLANATION:** LuaLink's Java bridge doesn't properly resolve Java methods when called from async threads, even when wrapped in `synchronized()`.

**SOLUTION:** Use synchronous tasks for Java-heavy operations:

```lua
-- ❌ WRONG - Java calls will fail in async
scheduler:runAsync(function()
    local file = File("path")
    file:exists()  -- ERROR: no matching method found
end)

-- ✅ CORRECT - Use sync for Java operations
scheduler:run(function()
    local file = File("path")
    file:exists()  -- Works fine
end)

-- ✅ ALTERNATIVE - Split work across main/async threads
scheduler:run(function()
    -- Do Java API calls on main thread
    local data = collectDataFromJavaAPI()
    
    scheduler:runAsync(function()
        -- Do pure Lua/IO work async
        processData(data)
    end)
end)
```

**NOTE:** For file I/O, brief pauses on main thread are usually acceptable. Heavy processing should be designed to work without Java API access.

### 8. Scheduler Tasks

```lua
-- Run once, immediately
scheduler:run(function() end)

-- Run after delay (20 ticks = 1 second)
scheduler:runDelayed(function() end, 20)

-- Run repeatedly (delay, then period)
scheduler:runRepeating(function() end, 20, 20)

-- Async versions available
scheduler:runAsync(function() end)
-- WARNING: Java API calls don't work reliably in async! See Gotcha #7
```

### 9. Rich Messages (MiniMessage Format)

```lua
player:sendRichMessage("<green>Colored text</green>")
player:sendRichMessage("<gold><bold>Bold gold text</bold></gold>")
player:sendRichMessage("<gradient:blue:green>Gradient text</gradient>")
player:sendRichMessage("<rainbow>Rainbow text!</rainbow>")
```

Documentation: https://docs.advntr.dev/minimessage/

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

See the example scripts for complete working examples:

- **eggfight/** - Full minigame with arenas, state management
- **skyblock/** - Persistent world with state swapping
- **vanish/** - Simple utility plugin with disk persistence

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