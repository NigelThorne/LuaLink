# Teleport Home Example

A modern LuaLink plugin demonstrating current best practices and patterns.

## What It Does

Players can set multiple home locations and teleport to them with a countdown timer.

## Features

- Set up to 5 homes per player
- 3-second teleport countdown
- Teleport cancelled if player moves or takes damage
- JSON data persistence
- Clean, organized code structure

## Commands

- `/home` - List all your homes
- `/home <name>` - Teleport to a home
- `/sethome <name>` - Set a home at your current location
- `/delhome <name>` - Delete a home

## Permissions

- `teleport.home` - Use /home command
- `teleport.sethome` - Use /sethome command
- `teleport.delhome` - Use /delhome command

## Best Practices Demonstrated

This example showcases modern LuaLink development patterns:

### 1. Type Annotations
```lua
if not Player.class:isInstance(sender) then
    sender:sendRichMessage("<red>Only players can use this command!</red>")
    return
end
---@cast sender org.bukkit.entity.Player
```

### 2. String Formatting
```lua
-- Good: Uses string.format
player:sendRichMessage(string.format(
    "<green>Teleporting to <white>%s</white> in <white>3</white> seconds!",
    homeName
))

-- Avoid: String concatenation
player:sendRichMessage("<green>Teleporting to " .. homeName .. " in 3 seconds!")
```

### 3. JSON Data Persistence
```lua
local json = require "json"

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
```

### 4. Class Instance Checking
```lua
if not Player.class:isInstance(entity) then
    return
end
---@cast entity org.bukkit.entity.Player
```

### 5. Proper Error Handling
```lua
local success, data = pcall(json.decode, content)
if not success then
    script.logger:warning("Failed to parse homes JSON, starting fresh")
    return {}
end
```

### 6. goto continue Pattern
```lua
for uuid, pending in pairs(pendingTeleports) do
    local player = server:getPlayer(UUID:fromString(uuid))
    
    -- Skip if player offline
    if not player then
        goto continue
    end
    
    -- Process player...
    
    ::continue::
end
```

### 7. Code Organization
The file follows a clear structure:
1. Imports
2. Module requires
3. Constants
4. State variables
5. Helper functions
6. Commands
7. Event listeners
8. Lifecycle hooks

### 8. File I/O Best Practices
```lua
-- Always check file operations
local file = io.open(getDataFile(), "r")
if not file then
    return {}
end

local content = file:read("*a")
file:close()  -- Always close files
```

## Data Storage

Homes are stored in `plugins/LuaLink/data/teleport-home/homes.json`:

```json
{
  "uuid-here": {
    "home1": {
      "world": "world",
      "x": 100.5,
      "y": 64.0,
      "z": -200.3,
      "yaw": 90.0,
      "pitch": 0.0,
      "timestamp": 1234567890
    }
  }
}
```

## Learning Points

1. **Type Safety**: Use `---@cast` after type checks for better IDE support
2. **Readable Strings**: `string.format()` is clearer than concatenation
3. **Structured Data**: JSON is better than YAML for complex nested data
4. **Null Safety**: Always check if objects exist before using them
5. **Resource Management**: Close file handles, cancel tasks on unload
6. **User Feedback**: Clear messages with colour coding using MiniMessage format
7. **Clean Code**: Consistent naming, organized structure, appropriate abstraction

## Comparison with Other Examples

- **vanish/** - Simple state persistence with YAML
- **skyblock/** - World management with minigame helpers
- **eggfight/** - Complex game logic with arena management
- **teleport-home/** - Modern patterns with JSON persistence

This example sits between simple (vanish) and complex (eggfight) examples, focusing on demonstrating best practices rather than complex features.