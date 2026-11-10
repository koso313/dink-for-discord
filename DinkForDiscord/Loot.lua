local _, ns = ...

-- Loot alerts. Items looted within a second of each other are grouped into one alert.
-- If WoW Forever hides the loot chat message (it can inside instances), we fall back to
-- comparing bag contents before and after.

local GROUP_WINDOW = 1.2
local pending, flushAt, lootSource = {}, nil, nil
local secretLootAt = 0
local bagCounts, bagLinks = {}, {}

---------------------------------------------------------------- bag snapshot
local function ContainerSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

local function ContainerItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then return info.hyperlink, info.stackCount or 1 end
        return nil
    end
    if GetContainerItemInfo then
        local _, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
        return link, count or 1
    end
end

local function ScanBags()
    local counts, links = {}, {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, ContainerSlots(bag) or 0 do
            local link, count = ContainerItem(bag, slot)
            if link and not ns.IsSecret(link) then
                local id = ns.ItemID(link)
                if id then
                    counts[id] = (counts[id] or 0) + (ns.Public(count) or 1)
                    links[id] = link
                end
            end
        end
    end
    return counts, links
end

---------------------------------------------------------------- filters
local function Listed(name, lines)
    for _, pattern in ipairs(ns.Lines(lines)) do
        if ns.WildMatch(name, pattern) then return true end
    end
    return false
end

local function IsQuestItem(link)
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not instant then return false end
    local _, _, _, _, _, classID = instant(link)
    return classID == 12 -- LE_ITEM_CLASS_QUESTITEM
end

-- Returns the item info table if this item should be announced.
local function Wanted(item, count)
    local s = ns.Setting("LOOT")
    if Listed(item.name, s.deny) then return false end
    if Listed(item.name, s.allow) then return true end
    if not s.questItems and IsQuestItem(item.link) then return false end
    local value = (item.ah or item.sell or 0) * count
    if (s.minValue or 0) > 0 and value >= s.minValue * 10000 then return true end
    return (item.quality or 1) >= (s.minQuality or 3)
end

---------------------------------------------------------------- sending
local function Flush()
    flushAt = nil
    if #pending == 0 then return end
    local items = pending
    pending = {}

    local lines, total, best, count, firstLink = {}, 0, -1, 0, nil
    for _, entry in ipairs(items) do
        local item = entry.item
        local value = (item.ah or item.sell or 0) * entry.count
        total = total + value
        count = count + entry.count
        if (item.quality or 1) > best then best, firstLink = item.quality or 1, item.link end
        local line = string.format("%d x [%s]", entry.count, item.name)
        if value > 0 then line = line .. " (" .. ns.Money(value) .. ")" end
        lines[#lines + 1] = line
    end

    local source = lootSource or "Unknown"
    local priceLabel = items[1].item.ah and "Auction value" or "Vendor value"
    ns.Notify("LOOT", {
        vars = { LOOT = table.concat(lines, "\n"), SOURCE = source, TOTAL_VALUE = ns.Money(total), COUNT = count },
        color = (ns.QUALITY[best] or ns.QUALITY[1]).color,
        url = #items == 1 and ns.ItemUrl(firstLink) or nil,
        title = #items == 1 and items[1].item.name or nil,
        fields = {
            { "Source", source, true },
            total > 0 and { priceLabel, ns.Money(total), true } or {},
            { "Quality", (ns.QUALITY[best] or ns.QUALITY[1]).name, true },
        },
    })
end

-- Item info may not be cached the moment we see the link; retry briefly.
local function Consider(link, count, tries)
    local item = ns.ItemInfo(link)
    if not item then
        if (tries or 0) < 6 then ns.After(0.25, function() Consider(link, count, (tries or 0) + 1) end) end
        return
    end
    item.ah = ns.AuctionValue(item.link or link)
    if not Wanted(item, count) then return end
    pending[#pending + 1] = { item = item, count = count }
    flushAt = GetTime() + GROUP_WINDOW
    ns.After(GROUP_WINDOW + 0.05, function()
        if flushAt and GetTime() >= flushAt then Flush() end
    end)
end

---------------------------------------------------------------- events
local function RememberSource()
    local name
    if UnitExists("target") and UnitIsDead("target") then name = ns.Public(UnitName("target")) end
    if not name and UnitExists("mouseover") and UnitIsDead("mouseover") then name = ns.Public(UnitName("mouseover")) end
    if not name and GetLootSourceInfo and GetNumLootItems and GetNumLootItems() > 0 then
        -- Fishing, chests and the like: fall back to the zone.
        name = IsFishingLoot and IsFishingLoot() and "Fishing" or nil
    end
    lootSource = name or ns.Zone()
end
ns.On("LOOT_OPENED", RememberSource)
ns.On("LOOT_READY", RememberSource)

-- Only real loot ("You receive loot"), not vendor purchases or quest rewards ("You receive item").
local SELF_FORMATS = { "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF" }

ns.On("CHAT_MSG_LOOT", function(msg, ...)
    if not ns.Enabled("LOOT") then return end
    if ns.IsSecret(msg) then
        secretLootAt = GetTime()
        return
    end
    for _, name in ipairs(SELF_FORMATS) do
        local fmt = _G[name]
        if fmt then
            local link, count = ns.MatchFormat(msg, fmt)
            if link then
                Consider(link, tonumber(count) or 1)
                return
            end
        end
    end
end)

ns.On("BAG_UPDATE_DELAYED", function()
    local counts, links = ScanBags()
    if ns.Enabled("LOOT") and GetTime() - secretLootAt < 3 then
        for id, n in pairs(counts) do
            local gained = n - (bagCounts[id] or 0)
            if gained > 0 then Consider(links[id], gained) end
        end
        secretLootAt = 0
    end
    bagCounts, bagLinks = counts, links
end)

ns.On("PLAYER_ENTERING_WORLD", function()
    bagCounts, bagLinks = ScanBags()
end)
