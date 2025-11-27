# LuaLink Plugin Deployment Guide

This guide explains how to deploy LuaLink plugins from the example-scripts directory to your Minecraft server.

## Directory Structure

Your server's LuaLink plugin folder should have the following structure:

```
plugins/LuaLink/
├── libs/                    # Global shared libraries
│   ├── common/
│   │   ├── utils.lua       # Common utilities (require("common.utils"))
│   │   └── minigame.lua    # Minigame framework (require("common.minigame"))
│   └── json.lua            # JSON encoder/decoder (require("json"))
└── scripts/                 # Individual plugin directories
    ├── plugin-name/
    │   ├── main.lua         # Required entry point
    │   ├── config.lua       # Optional configuration
    │   └── ...              # Other plugin-specific files
    └── another-plugin/
        └── main.lua
```

## Understanding the Module Search Paths

When a plugin uses `require("moduleName")`, LuaLink searches in this order:

1. **Script-local modules**: `plugins/LuaLink/scripts/{scriptName}/{moduleName}.lua`
   - For plugin-specific modules
   
2. **Global libraries**: `plugins/LuaLink/libs/{moduleName}/main.lua`
   - For namespaced modules (e.g., `require("common.utils")` → `libs/common/utils.lua`)
   
3. **Global libraries**: `plugins/LuaLink/libs/{moduleName}.lua`
   - For single-file modules (e.g., `require("json")` → `libs/json.lua`)

## Deploying Shared Libraries

Deploy shared libraries **once** - they're available to all plugins:

```bash
# Deploy common utilities
mkdir -p "$SERVER/plugins/LuaLink/libs/common"
cp example-scripts/libs/common/*.lua "$SERVER/plugins/LuaLink/libs/common/"

# Deploy JSON library
cp example-scripts/libs/json.lua "$SERVER/plugins/LuaLink/libs/"
```

Where `$SERVER` is your server directory, e.g.:
```bash
SERVER="/Users/nigelthorne/ATLauncher/ATLauncher.app/Contents/Java/servers/Minecraft12110withPaper"
```

## Deploying Individual Plugins

Each plugin needs its own directory under `scripts/`:

```bash
# Deploy a plugin
mkdir -p "$SERVER/plugins/LuaLink/scripts/plugin-name"
cp example-scripts/plugin-name/main.lua "$SERVER/plugins/LuaLink/scripts/plugin-name/"

# If the plugin has additional files:
cp example-scripts/plugin-name/*.lua "$SERVER/plugins/LuaLink/scripts/plugin-name/"
```

### Example: Deploy auto-replace-hotbar

```bash
mkdir -p "$SERVER/plugins/LuaLink/scripts/auto-replace-hotbar"
cp example-scripts/auto-replace-hotbar/main.lua "$SERVER/plugins/LuaLink/scripts/auto-replace-hotbar/"
```

### Example: Deploy restack

```bash
mkdir -p "$SERVER/plugins/LuaLink/scripts/restack"
cp example-scripts/restack/main.lua "$SERVER/plugins/LuaLink/scripts/restack/"
```

### Example: Deploy vanish

```bash
mkdir -p "$SERVER/plugins/LuaLink/scripts/vanish"
cp example-scripts/vanish/main.lua "$SERVER/plugins/LuaLink/scripts/vanish/"
```

## Loading and Reloading Plugins

Use the in-game or console commands:

```
lualink load <plugin-name>    # Load or reload a plugin
lualink unload <plugin-name>  # Unload a plugin
lualink list                  # List all loaded plugins
```

**Note**: LuaLink supports hot-reloading - you can modify plugin files and reload them without restarting the server.

## Quick Deploy Script

Create a deployment script for easy updates:

```bash
#!/bin/bash

# Configuration
SERVER="/path/to/your/server"
LUALINK_DIR="$SERVER/plugins/LuaLink"
SOURCE_DIR="./example-scripts"

# Deploy shared libraries
echo "Deploying shared libraries..."
mkdir -p "$LUALINK_DIR/libs/common"
cp "$SOURCE_DIR/libs/common/"*.lua "$LUALINK_DIR/libs/common/"
cp "$SOURCE_DIR/libs/json.lua" "$LUALINK_DIR/libs/"

# Deploy individual plugins
deploy_plugin() {
    local plugin=$1
    echo "Deploying $plugin..."
    mkdir -p "$LUALINK_DIR/scripts/$plugin"
    cp -r "$SOURCE_DIR/$plugin/"* "$LUALINK_DIR/scripts/$plugin/"
}

# Deploy your plugins
deploy_plugin "auto-replace-hotbar"
deploy_plugin "restack"
deploy_plugin "vanish"
deploy_plugin "eggfight"
deploy_plugin "skyblock"
deploy_plugin "teleport-home"

echo "Deployment complete!"
echo "Use 'lualink load <plugin-name>' in-game to load plugins"
```

## Troubleshooting

### Module not found errors

If you see: `Module 'common.utils' not found in any search paths`

**Check**:
1. File exists at `plugins/LuaLink/libs/common/utils.lua`
2. File permissions are readable
3. You're using the correct require statement: `require("common.utils")`

### Plugin won't load

**Check**:
1. File exists at `plugins/LuaLink/scripts/{plugin-name}/main.lua`
2. Syntax errors in the Lua file
3. Check server logs for error messages
4. Ensure all required modules are deployed

### After updating a plugin

1. Copy the updated files to the server
2. Run `lualink load <plugin-name>` to reload
3. No server restart needed!

## Best Practices

1. **Version control**: Keep your deployed plugins in sync with your source
2. **Test locally**: Use a local test server before deploying to production
3. **Backup first**: Backup plugin data directories before major updates
4. **Incremental updates**: Deploy and test one plugin at a time
5. **Check logs**: Monitor server logs when loading plugins

## File Permissions

Ensure the server process can read the files:

```bash
chmod -R 755 "$SERVER/plugins/LuaLink/scripts"
chmod -R 755 "$SERVER/plugins/LuaLink/libs"
```

## Production Deployment Notes

- Always backup before deploying to production
- Test plugins on a staging server first
- Coordinate deployment with low-traffic periods
- Have a rollback plan ready
- Monitor server performance after deployment