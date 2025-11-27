-- Restack Plugin for LuaLink
-- Consolidates inventory items to maximize free space

local Player = import("org.bukkit.entity.Player")
local ItemStack = import("org.bukkit.inventory.ItemStack")

local function restackInventory(player)
    local inventory = player:getInventory()
    local slots = {}

    -- Collect all items with their slot positions (0-35 for player inventory)
    for slot = 0, 35 do
        local item = inventory:getItem(slot)
        if item ~= nil and item:getType():name() ~= "AIR" then
            table.insert(slots, { slot = slot, item = item:clone() })
        end
    end

    -- Track which slots we've already processed
    local processed = {}
    local itemsRestacked = 0

    -- For each item, try to consolidate with similar items
    for i = 1, #slots do
        if not processed[i] then
            local baseSlot = slots[i]
            local baseItem = baseSlot.item
            local maxStackSize = baseItem:getMaxStackSize()

            -- If item can't stack, skip it
            if maxStackSize <= 1 then
                processed[i] = true
            else
                -- Find all similar items
                local similarItems = {}
                table.insert(similarItems, { index = i, slot = baseSlot.slot, item = baseItem })
                processed[i] = true

                for j = i + 1, #slots do
                    if not processed[j] then
                        local otherItem = slots[j].item
                        -- Check if items are similar (same type, enchants, meta, etc.)
                        if baseItem:isSimilar(otherItem) then
                            table.insert(similarItems, { index = j, slot = slots[j].slot, item = otherItem })
                            processed[j] = true
                        end
                    end
                end

                -- If we found multiple similar items, consolidate them
                if #similarItems > 1 then
                    -- Calculate total amount
                    local totalAmount = 0
                    for _, item in ipairs(similarItems) do
                        totalAmount = totalAmount + item.item:getAmount()
                    end

                    -- Create consolidated stacks
                    local newStacks = {}
                    while totalAmount > 0 do
                        local stackSize = math.min(totalAmount, maxStackSize)
                        local newStack = baseItem:clone()
                        newStack:setAmount(stackSize)
                        table.insert(newStacks, newStack)
                        totalAmount = totalAmount - stackSize
                    end

                    -- Place consolidated stacks back in inventory
                    for k, item in ipairs(similarItems) do
                        if k <= #newStacks then
                            inventory:setItem(item.slot, newStacks[k])
                        else
                            -- Clear extra slots
                            inventory:setItem(item.slot, nil)
                        end
                    end

                    itemsRestacked = itemsRestacked + 1
                end
            end
        end
    end

    return itemsRestacked
end

-- Register the /restack command
script:registerCommand(function(sender, args)
    if not Player.class:isInstance(sender) then
        sender:sendRichMessage("<red>Only players can use this command!</red>")
        return
    end
    ---@cast sender org.bukkit.entity.Player

    local player = sender
    local count = restackInventory(player)

    if count > 0 then
        player:sendRichMessage(string.format("<green>Restacked <bold>%d</bold> item type(s) in your inventory!</green>",
            count))
    else
        player:sendRichMessage("<gray>No items needed restacking.</gray>")
    end
end, {
    name = "restack",
    aliases = { "stack", "compact" },
    description = "Consolidate inventory items to maximize free space",
    usage = "/restack"
})

script:onLoad(function()
    script.logger:info("Restack plugin loaded!")
    script.logger:info("Command: /restack (aliases: /stack, /compact)")
end)

script:onUnload(function()
    script.logger:info("Restack plugin unloaded!")
end)
