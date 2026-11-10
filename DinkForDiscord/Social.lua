local _, ns = ...

-- Trades, Auction House, chat patterns, collections and Legacy alerts.

local function S(key) return ns.Setting(key) end

---------------------------------------------------------------- trades
local trade -- snapshot while the trade window is open

local function TradeSide(getItem, getLink, getMoney, slots)
    local items, value = {}, 0
    for i = 1, slots do
        local name, _, count = getItem(i)
        name = ns.Public(name)
        if name then
            count = ns.Public(count) or 1
            items[#items + 1] = string.format("[%s] x%d", name, count)
            local link = getLink and ns.Public(getLink(i))
            local info = link and ns.ItemInfo(link)
            if info then value = value + (ns.AuctionValue(info.link) or info.sell or 0) * count end
        end
    end
    local money = tonumber(ns.Public(getMoney())) or 0
    if money > 0 then items[#items + 1] = ns.Money(money) end
    return items, value + money
end

ns.On("TRADE_SHOW", function()
    trade = { who = ns.Public(UnitName("NPC")) or "someone" }
end)

ns.On("TRADE_ACCEPT_UPDATE", function()
    if not trade or not GetTradePlayerItemInfo then return end
    local slots = (MAX_TRADABLE_ITEMS or 6)
    trade.gave, trade.gaveValue = TradeSide(GetTradePlayerItemInfo, GetTradePlayerItemLink, GetPlayerTradeMoney, slots)
    trade.got, trade.gotValue = TradeSide(GetTradeTargetItemInfo, GetTradeTargetItemLink, GetTargetTradeMoney, slots)
end)

ns.On("UI_INFO_MESSAGE", function(_, msg)
    if not trade or ns.IsSecret(msg) or msg ~= ERR_TRADE_COMPLETE then return end
    local t = trade
    trade = nil
    if not ns.Enabled("TRADE") then return end
    local worth = math.max(t.gaveValue or 0, t.gotValue or 0)
    if worth < (S("TRADE").minValue or 0) * 10000 then return end
    local gave = (t.gave and #t.gave > 0) and table.concat(t.gave, ", ") or "nothing"
    local got = (t.got and #t.got > 0) and table.concat(t.got, ", ") or "nothing"
    ns.Notify("TRADE", {
        vars = { COUNTERPARTY = t.who, GAVE = gave, GOT = got },
        fields = { { "Gave", gave, false }, { "Received", got, false } },
    })
end)
ns.On("TRADE_CLOSED", function() ns.After(1, function() trade = nil end) end)

---------------------------------------------------------------- auction house + system chat
ns.On("CHAT_MSG_SYSTEM", function(msg)
    if ns.IsSecret(msg) or not ns.Enabled("AUCTION") then return end
    local s = S("AUCTION")
    local item = s.sold and ns.MatchFormat(msg, ERR_AUCTION_SOLD_S)
    if item then
        ns.Notify("AUCTION", { vars = { ITEM = item, STATUS = "Sold" }, fields = { { "Item", item, true } } })
        return
    end
    item = s.won and ns.MatchFormat(msg, ERR_AUCTION_WON_S)
    if item then
        ns.Notify("AUCTION", { vars = { ITEM = item, STATUS = "Won" }, color = 0x2ecc71, fields = { { "Item", item, true } } })
    end
end)

---------------------------------------------------------------- chat patterns
local CHANNELS = {
    CHAT_MSG_GUILD = { "guild", "Guild" }, CHAT_MSG_OFFICER = { "guild", "Officer" },
    CHAT_MSG_PARTY = { "party", "Party" }, CHAT_MSG_PARTY_LEADER = { "party", "Party" },
    CHAT_MSG_RAID = { "party", "Raid" }, CHAT_MSG_RAID_LEADER = { "party", "Raid" },
    CHAT_MSG_RAID_WARNING = { "party", "Raid warning" },
    CHAT_MSG_WHISPER = { "whisper", "Whisper" }, CHAT_MSG_BN_WHISPER = { "whisper", "Whisper" },
    CHAT_MSG_SAY = { "public", "Say" }, CHAT_MSG_YELL = { "public", "Yell" }, CHAT_MSG_CHANNEL = { "public", "Channel" },
    CHAT_MSG_SYSTEM = { "system", "System" },
}

for event, info in pairs(CHANNELS) do
    ns.On(event, function(msg, sender)
        if not ns.Enabled("CHAT") then return end
        local s = S("CHAT")
        if not s[info[1]] or ns.IsSecret(msg) then return end
        local text = ns.Plain(msg)
        for _, pattern in ipairs(ns.Lines(s.patterns)) do
            if ns.WildMatch(text, pattern) then
                local who = ns.Public(sender)
                who = who and who:gsub("%-.*$", "") or info[2]
                ns.Notify("CHAT", {
                    vars = { SENDER = who, MESSAGE = text, CHANNEL = info[2] },
                    fields = { { "Channel", info[2], true } },
                })
                return
            end
        end
    end)
end

---------------------------------------------------------------- collections (account-wide, Forever)
local function Collected(kind, name, link)
    if not ns.Enabled("COLLECTION") or not name then return end
    ns.Notify("COLLECTION", {
        vars = { ITEM = name, TYPE = kind },
        url = link and ns.ItemUrl(link) or nil,
        fields = { { "Type", kind, true } },
    })
end

ns.On("NEW_MOUNT_ADDED", function(mountID)
    if not S("COLLECTION").mounts then return end
    local name = C_MountJournal and C_MountJournal.GetMountInfoByID and C_MountJournal.GetMountInfoByID(mountID)
    Collected("mount", ns.Public(name))
end)

ns.On("NEW_PET_ADDED", function(petGUID)
    if not S("COLLECTION").pets then return end
    local name
    if C_PetJournal and C_PetJournal.GetPetInfoByPetID then
        local _, customName, _, _, _, _, _, speciesName = C_PetJournal.GetPetInfoByPetID(petGUID)
        name = ns.Public(customName) or ns.Public(speciesName)
    end
    Collected("companion", name)
end)

ns.On("NEW_TOY_ADDED", function(itemID)
    if not S("COLLECTION").toys then return end
    local info = ns.ItemInfo(itemID)
    if info then Collected("toy", info.name, info.link) else
        ns.After(1, function() local i = ns.ItemInfo(itemID); if i then Collected("toy", i.name, i.link) end end)
    end
end)

ns.On("TRANSMOG_COLLECTION_SOURCE_ADDED", function(sourceID)
    if not S("COLLECTION").transmog then return end
    local info = C_TransmogCollection and C_TransmogCollection.GetSourceInfo and C_TransmogCollection.GetSourceInfo(sourceID)
    if info and ns.Public(info.name) then Collected("appearance", info.name, info.itemID and ("item:" .. info.itemID)) end
end)

---------------------------------------------------------------- Legacy (achievements)
ns.On("ACHIEVEMENT_EARNED", function(id)
    if not ns.Enabled("LEGACY") or not GetAchievementInfo then return end
    local _, name, points = GetAchievementInfo(id)
    name = ns.Public(name)
    if not name then return end
    ns.Notify("LEGACY", {
        vars = { ACHIEVEMENT = name, POINTS = ns.Public(points) or 0 },
        fields = { (ns.Public(points) or 0) > 0 and { "Points", points, true } or {} },
    })
end)
