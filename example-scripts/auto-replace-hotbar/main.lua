-- Auto Replace Hotbar Plugin for LuaLink
-- Automatically replaces broken items in hotbar slots 1-9 with matching items from inventory

local Material = import("org.bukkit.Material")
local ItemStack = import("org.bukkit.inventory.ItemStack")

-- Listen for item break events
script:registerListener("org.bukkit.event.player.PlayerItemBreakEvent", function(event)
    local player = event:getPlayer()
    local brokenItem = event:getBrokenItem()
    local inventory = player:getInventory()

    -- Get the material type of the broken item
    local brokenType = brokenItem:getType()

    -- The broken item was in the player's hand (currently selected hotbar slot)
    local brokenSlot = inventory:getHeldItemSlot()

    -- Only auto-replace if it was in a hotbar slot (0-8)
    if brokenSlot < 0 or brokenSlot > 8 then
        return
    end

    -- Search for a matching item in the rest of the inventory
    local replacementSlot = nil

    -- Check slots 9-35 (main inventory, not hotbar)
    for slot = 9, 35 do
        local item = inventory:getItem(slot)
        if item ~= nil and item:getType() == brokenType then
            replacementSlot = slot
            break
        end
    end

    -- If we found a replacement, move it to the hotbar
    if replacementSlot ~= nil then
        local replacementItem = inventory:getItem(replacementSlot)

        -- Move the item to the hotbar slot
        inventory:setItem(brokenSlot, replacementItem)

        -- Clear the original slot
        inventory:setItem(replacementSlot, nil)

        script.logger:info(string.format("Auto-replaced %s for %s in slot %d",
            brokenType:name(), player:getName(), brokenSlot + 1))
    end
end)

script:onLoad(function()
    script.logger:info("Auto Replace Hotbar plugin loaded!")
    script.logger:info("Items in hotbar slots 1-9 will be automatically replaced when they break")
end)

script:onUnload(function()
    script.logger:info("Auto Replace Hotbar plugin unloaded!")
end)
