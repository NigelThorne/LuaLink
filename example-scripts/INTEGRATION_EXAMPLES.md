# LuaLink Third-Party Plugin Integration Examples

This guide demonstrates how to integrate LuaLink scripts with popular Bukkit/Paper plugins.

## Table of Contents

- [PlaceholderAPI](#placeholderapi)
- [Vault Economy](#vault-economy)
- [LuckPerms](#luckperms)
- [CompletableFuture Patterns](#completablefuture-patterns)
- [Floodgate API](#floodgate-api)
- [JSON Data Persistence](#json-data-persistence)
- [Service Provider Pattern](#service-provider-pattern)

---

## PlaceholderAPI

PlaceholderAPI allows you to use placeholders from other plugins in your scripts.

### Basic Usage

```lua
local PlaceholderAPI = import "me.clip.placeholderapi.PlaceholderAPI"

-- Get a placeholder value for a specific player
local player = server:getPlayer("PlayerName")
local balance = PlaceholderAPI:setPlaceholders(player, "%vault_eco_balance%")
print("Player balance: " .. balance)

-- Get a placeholder without a player context (pass nil)
local topPlayer = PlaceholderAPI:setPlaceholders(nil, "%ajlb_lb_vault_eco_balance_1_alltime_name%")
print("Top player: " .. topPlayer)
```

### Handling Loading States

Some placeholders may return "Loading" or "---" while data is being fetched:

```lua
local function checkBaltop()
    local topPlayerName = PlaceholderAPI:setPlaceholders(nil, "%ajlb_lb_vault_eco_balance_1_alltime_name%")
    
    -- Check for invalid states
    if not topPlayerName or topPlayerName == "" or topPlayerName == "---" then
        print("No baltop player found.")
        return
    end
    
    if topPlayerName == "Loading" then
        print("Data still loading, retrying in 30 seconds...")
        scheduler:runDelayedAsync(checkBaltop, 30 * 20)
        return 
    end
    
    -- Process the valid result
    print("Top player: " .. topPlayerName)
end
```

### Common Placeholders

```lua
-- Player-specific placeholders
local name = PlaceholderAPI:setPlaceholders(player, "%player_name%")
local displayName = PlaceholderAPI:setPlaceholders(player, "%player_displayname%")
local health = PlaceholderAPI:setPlaceholders(player, "%player_health%")
local level = PlaceholderAPI:setPlaceholders(player, "%player_level%")

-- Economy placeholders (requires Vault)
local balance = PlaceholderAPI:setPlaceholders(player, "%vault_eco_balance%")
local formatted = PlaceholderAPI:setPlaceholders(player, "%vault_eco_balance_formatted%")

-- LuckPerms placeholders
local prefix = PlaceholderAPI:setPlaceholders(player, "%luckperms_prefix%")
local group = PlaceholderAPI:setPlaceholders(player, "%luckperms_primary_group_name%")
```

---

## Vault Economy

Vault provides a unified API for economy plugins.

### Setup

```lua
local VAULT_ECONOMY = import "net.milkbowl.vault.economy.Economy"
local econ = nil

script:onLoad(function()
    local rsp = server:getServicesManager():getRegistration(VAULT_ECONOMY.class)
    if rsp ~= nil then
        econ = rsp:getProvider()
        print("Vault Economy loaded successfully")
    else
        print("Vault Economy not found. Economy features disabled.")
    end
end)
```

### Check Balance

```lua
script:registerCommand(function(sender, args)
    ---@cast sender org.bukkit.entity.Player
    
    if not econ then
        sender:sendRichMessage("<red>Economy is not available.</red>")
        return
    end
    
    local balance = econ:getBalance(sender)
    sender:sendRichMessage(string.format(
        "<green>Your balance: <gold>$%.2f</gold></green>", 
        balance
    ))
end, {name = "balance"})
```

### Deposit and Withdraw

```lua
-- Deposit money
local response = econ:depositPlayer(sender, 100.0)
if response:transactionSuccess() then
    sender:sendRichMessage("<green>Deposited $100.00</green>")
else
    sender:sendRichMessage("<red>Transaction failed: " .. response:errorMessage .. "</red>")
end

-- Withdraw money
local response = econ:withdrawPlayer(sender, 50.0)
if response:transactionSuccess() then
    sender:sendRichMessage("<green>Withdrew $50.00</green>")
    local newBalance = response:balance
else
    sender:sendRichMessage("<red>Insufficient funds</red>")
end
```

### Check if Player Can Afford

```lua
local function canAfford(player, amount)
    if not econ then return false end
    return econ:has(player, amount)
end

-- Usage
if canAfford(sender, 500.0) then
    econ:withdrawPlayer(sender, 500.0)
    -- Give player something
else
    sender:sendRichMessage("<red>You need $500.00 for this!</red>")
end
```

### Working with Offline Players

```lua
local offlinePlayer = server:getOfflinePlayer("PlayerName")
if econ:hasAccount(offlinePlayer) then
    local balance = econ:getBalance(offlinePlayer)
    print("Offline player balance: " .. balance)
end
```

---

## LuckPerms

LuckPerms provides advanced permission management.

### Basic Setup

```lua
local LuckPermsProvider = import "net.luckperms.api.LuckPermsProvider"
local luckPerms = LuckPermsProvider:get()
```

### Loading Users

```lua
local UUID = import "java.util.UUID"

-- Load online player
local player = server:getPlayer("PlayerName")
local lpUser = luckPerms:getUserManager():loadUser(
    player:getUniqueId(),
    player:getName()
):join()

-- Load offline player by UUID
local uuid = UUID:fromString("00000000-0000-0000-0000-000000000000")
local lpUser = luckPerms:getUserManager():loadUser(uuid):join()
```

### Adding and Removing Groups

```lua
local InheritanceNode = import "net.luckperms.api.node.types.InheritanceNode"

-- Add a group
local node = InheritanceNode:builder("vip")
    :value(true)
    :build()
lpUser:data():add(node)
luckPerms:getUserManager():saveUser(lpUser)

-- Remove a group
lpUser:data():remove(node)
luckPerms:getUserManager():saveUser(lpUser)
```

### Groups with Server Context

Useful for multi-server networks:

```lua
local InheritanceNode = import "net.luckperms.api.node.types.InheritanceNode"

-- Add group to specific servers
local node = InheritanceNode:builder("champion")
    :value(true)
    :withContext("server", "survival")
    :withContext("server", "creative")
    :build()

lpUser:data():add(node)
luckPerms:getUserManager():saveUser(lpUser)
```

### Multiple Server Contexts (Loop)

```lua
local serverNames = {"survival", "creative", "skyblock"}

local builder = InheritanceNode:builder("vip"):value(true)
for i = 1, #serverNames do
    builder:withContext("server", serverNames[i])
end

lpUser:data():add(builder:build())
luckPerms:getUserManager():saveUser(lpUser)
```

### Checking Permissions

```lua
-- Check if user has permission
local hasPermission = lpUser:getCachedData():getPermissionData():checkPermission("my.permission"):asBoolean()

if hasPermission then
    print("User has permission")
end
```

### Getting User's Primary Group

```lua
local primaryGroup = lpUser:getPrimaryGroup()
print("Primary group: " .. primaryGroup)
```

---

## CompletableFuture Patterns

Many modern APIs return CompletableFutures for async operations.

### Basic Pattern with :thenAccept()

```lua
local HuskHomesAPI = import "net.william278.huskhomes.api.HuskHomesAPI"

local homes = {}
HuskHomesAPI:getUserHomes(huskUser):thenAccept(function(homeList)
    ---@cast homeList java.util.List
    for i = 1, homeList:size() do
        local home = homeList:get(i - 1)
        table.insert(homes, {
            name = home:getMeta():getName(),
            x = home:getPosition():getX(),
            y = home:getPosition():getY(),
            z = home:getPosition():getZ()
        })
    end
    
    print("Loaded " .. #homes .. " homes")
end)
```

### Chaining Futures

```lua
api:getUserData(player)
    :thenAccept(function(userData)
        -- Process user data
        return api:getAdditionalData(userData:getId())
    end)
    :thenAccept(function(additionalData)
        -- Process additional data
        print("Processing complete")
    end)
```

### Using :join() for Synchronous Wait

```lua
-- This blocks until the future completes
local lpUser = luckPerms:getUserManager():loadUser(uuid):join()

-- Now you can use lpUser immediately
print("Loaded user: " .. lpUser:getUsername())
```

### Error Handling

```lua
api:getSomeData(player)
    :thenAccept(function(data)
        if data == nil then
            print("No data found")
            return
        end
        -- Process data
    end)
    :exceptionally(function(error)
        print("Error loading data: " .. tostring(error))
        return nil
    end)
```

---

## Floodgate API

Floodgate allows Bedrock Edition players to join Java servers.

### Detecting Bedrock Players

```lua
local FloodgateAPI = import "org.geysermc.floodgate.api.FloodgateApi"

local function isBedrockPlayer(player)
    return FloodgateAPI:getInstance():isFloodgatePlayer(player:getUniqueId())
end

-- Usage
if isBedrockPlayer(sender) then
    sender:sendRichMessage("<green>Welcome, Bedrock player!</green>")
    -- Show form-based UI instead of chat-based
else
    sender:sendRichMessage("<green>Welcome, Java player!</green>")
    -- Show standard UI
end
```

### Getting Bedrock Username

```lua
if FloodgateAPI:getInstance():isFloodgatePlayer(player:getUniqueId()) then
    local floodgatePlayer = FloodgateAPI:getInstance():getPlayer(player:getUniqueId())
    local bedrockUsername = floodgatePlayer:getUsername()
    print("Bedrock username: " .. bedrockUsername)
end
```

---

## JSON Data Persistence

The built-in `json` module allows you to save/load structured data.

### Basic Setup

```lua
local json = require "json"

local DATA_FILE = script:getDataFolder() .. "/data.json"

-- Initialize file on load
script:onLoad(function()
    local file = io.open(DATA_FILE, "r")
    if not file then
        -- Create file with empty array
        file = io.open(DATA_FILE, "w")
        if file then
            file:write("[]")
            file:close()
        else
            error("Could not create data.json")
        end
    else
        file:close()
    end
end)
```

### Reading JSON Data

```lua
local function loadData()
    local file = io.open(DATA_FILE, "r")
    if not file then
        return {}
    end
    
    local content = file:read("*a")
    file:close()
    
    if content == "" then
        return {}
    end
    
    local data = json.decode(content)
    return data or {}
end

-- Usage
local myData = loadData()
for i, record in ipairs(myData) do
    print("Record " .. i .. ": " .. record.name)
end
```

### Writing JSON Data

```lua
local function saveData(data)
    local file = io.open(DATA_FILE, "w")
    if not file then
        error("Could not write to data.json")
    end
    
    file:write(json.encode(data))
    file:close()
end

-- Usage
local data = loadData()
table.insert(data, {
    name = "John Doe",
    score = 100,
    timestamp = os.time()
})
saveData(data)
```

### Complex Data Structures

```lua
local playerData = {
    uuid = player:getUniqueId():toString(),
    name = player:getName(),
    stats = {
        kills = 10,
        deaths = 5,
        playtime = 3600
    },
    inventory = {
        "diamond_sword",
        "iron_helmet"
    },
    lastLogin = os.date("%Y-%m-%d %H:%M:%S")
}

-- Save it
local allData = loadData()
table.insert(allData, playerData)
saveData(allData)

-- Load and access nested data
local data = loadData()
for _, record in ipairs(data) do
    print(record.name .. " has " .. record.stats.kills .. " kills")
end
```

### Pretty Printing (Manual)

Lua's json module may not support pretty printing directly, but you can format manually:

```lua
-- Basic pretty print for debugging
local function prettyPrint(data, indent)
    indent = indent or 0
    local spacing = string.rep("  ", indent)
    
    if type(data) == "table" then
        for k, v in pairs(data) do
            if type(v) == "table" then
                print(spacing .. k .. ":")
                prettyPrint(v, indent + 1)
            else
                print(spacing .. k .. ": " .. tostring(v))
            end
        end
    end
end

prettyPrint(loadData())
```

---

## Service Provider Pattern

Many plugins expose their APIs through Bukkit's ServicesManager.

### General Pattern

```lua
local function getService(className)
    local serviceClass = import(className)
    local registration = server:getServicesManager():getRegistration(serviceClass.class)
    
    if registration ~= nil then
        return registration:getProvider()
    end
    
    return nil
end

-- Usage
local economy = getService("net.milkbowl.vault.economy.Economy")
if economy then
    print("Economy service loaded")
else
    print("Economy service not available")
end
```

### Multiple Service Providers

```lua
local services = {}

script:onLoad(function()
    -- Try to load multiple services
    services.economy = getService("net.milkbowl.vault.economy.Economy")
    services.permissions = getService("net.milkbowl.vault.permission.Permission")
    services.chat = getService("net.milkbowl.vault.chat.Chat")
    
    -- Log what's available
    for name, service in pairs(services) do
        if service then
            print(name .. " service loaded")
        else
            print(name .. " service not available")
        end
    end
end)

-- Use services with null checks
if services.economy then
    local balance = services.economy:getBalance(player)
end
```

### Lazy Loading Pattern

```lua
local economy = nil

local function getEconomy()
    if economy == nil then
        local registration = server:getServicesManager():getRegistration(
            import("net.milkbowl.vault.economy.Economy").class
        )
        if registration ~= nil then
            economy = registration:getProvider()
        end
    end
    return economy
end

-- Usage - only loads when first needed
script:registerCommand(function(sender, args)
    local econ = getEconomy()
    if not econ then
        sender:sendRichMessage("<red>Economy not available</red>")
        return
    end
    
    -- Use economy
end, {name = "balance"})
```

---

## Complete Integration Example

Here's a complete example combining multiple integrations:

```lua
-- Baltop Rank Manager with multiple plugin integrations
local PlaceholderAPI = import "me.clip.placeholderapi.PlaceholderAPI"
local LuckPermsProvider = import "net.luckperms.api.LuckPermsProvider"
local InheritanceNode = import "net.luckperms.api.node.types.InheritanceNode"
local UUID = import "java.util.UUID"
local json = require "json"

local config = {
    checkInterval = 30, -- minutes
    rank = "Champion",
    serverNames = {"survival", "creative"}
}

local DATA_FILE = script:getDataFolder() .. "/baltop.json"

-- Initialize
script:onLoad(function()
    local file = io.open(DATA_FILE, "a")
    if file then
        file:close()
    end
end)

-- Load/save last winner
local function loadLastWinner()
    local file = io.open(DATA_FILE, "r")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    if content == "" then return nil end
    return json.decode(content)
end

local function saveWinner(uuid, name)
    local file = io.open(DATA_FILE, "w")
    if not file then return end
    file:write(json.encode({uuid = uuid, name = name, timestamp = os.time()}))
    file:close()
end

-- Check baltop and update rank
local function check()
    -- Get top player from PlaceholderAPI
    local topName = PlaceholderAPI:setPlaceholders(nil, "%ajlb_lb_vault_eco_balance_1_alltime_name%")
    
    if not topName or topName == "" or topName == "---" or topName == "Loading" then
        return
    end
    
    local topPlayer = server:getOfflinePlayer(topName)
    local topUUID = topPlayer:getUniqueId():toString()
    
    -- Check if winner changed
    local lastWinner = loadLastWinner()
    if lastWinner and lastWinner.uuid == topUUID then
        return -- No change
    end
    
    -- Update LuckPerms
    local lp = LuckPermsProvider:get()
    local newWinner = lp:getUserManager():loadUser(topPlayer:getUniqueId(), topName):join()
    
    -- Add rank with server contexts
    local builder = InheritanceNode:builder(config.rank):value(true)
    for i = 1, #config.serverNames do
        builder:withContext("server", config.serverNames[i])
    end
    
    newWinner:data():add(builder:build())
    lp:getUserManager():saveUser(newWinner)
    
    -- Remove from previous winner
    if lastWinner then
        local oldWinner = lp:getUserManager():loadUser(UUID:fromString(lastWinner.uuid)):join()
        oldWinner:data():remove(builder:build())
        lp:getUserManager():saveUser(oldWinner)
        print("Removed " .. config.rank .. " from " .. lastWinner.name)
    end
    
    saveWinner(topUUID, topName)
    print("Gave " .. config.rank .. " to " .. topName)
end

-- Schedule checks
scheduler:runRepeatingAsync(check, 0, config.checkInterval * 60 * 20)
```

---

## Tips and Best Practices

1. **Always check for nil** when loading service providers
2. **Use :join() carefully** - it blocks the thread until completion
3. **Cache service providers** in the onLoad function
4. **Handle "Loading" states** for PlaceholderAPI
5. **Always close file handles** after reading/writing
6. **Use type annotations** (`---@cast`) for better IDE support
7. **Save and load CompletableFuture results** to variables if needed later
8. **Check plugin availability** before using APIs
9. **Use proper error messages** to inform users when services aren't available
10. **Store UUIDs as strings** in JSON, not UUID objects