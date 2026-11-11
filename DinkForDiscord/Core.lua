local ADDON, ns = ...

-- Shared helpers, saved settings and the event hub every other file uses.

ns.ADDON = ADDON
ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version"))
    or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or "dev"
ns.TITLE = "Dink For Discord"
ns.HELPER_URL = "https://github.com/koso313/dink-for-discord/releases/latest"
ns.ICON = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Icon"

local PREFIX = "|cff7289daDink|r: "
function ns.Print(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg)) end

---------------------------------------------------------------- secret values
-- WoW Forever hides some values from addons (in combat, in instances).
-- Anything we put in a Discord message must be readable, so check first.
function ns.IsSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, v)
    return ok and secret == true
end

function ns.Public(v)
    if v == nil or ns.IsSecret(v) then return nil end
    return v
end

---------------------------------------------------------------- timers
function ns.After(delay, fn)
    if C_Timer and C_Timer.After then C_Timer.After(delay, fn) else fn() end
end

---------------------------------------------------------------- events
local hub = CreateFrame("Frame")
local handlers = {}
ns.hub = hub

-- Registers fn for an event. Events that don't exist in this client are skipped quietly.
function ns.On(event, fn)
    if not handlers[event] then
        local ok = pcall(hub.RegisterEvent, hub, event)
        if not ok then return false end
        handlers[event] = {}
    end
    table.insert(handlers[event], fn)
    return true
end

hub:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok and ns.db and ns.db.general and ns.db.general.debug then
            ns.Print("|cffff5555error in " .. event .. ":|r " .. tostring(err))
        end
    end
end)

---------------------------------------------------------------- text helpers
-- Strips WoW colour codes, textures and hyperlinks down to plain text.
function ns.Plain(text)
    if type(text) ~= "string" then return text end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    text = text:gsub("|n", "\n")
    return text
end

-- Turns a game format string ("Your skill in %s has increased to %d.") into a Lua pattern.
-- Returns the pattern and, for "%1$s" style strings, the order of the captures.
function ns.PatternFromFormat(fmt)
    if type(fmt) ~= "string" then return nil end
    local order, n = {}, 0
    local pat = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    pat = pat:gsub("%%(%d)%%%$([sd])", function(i, kind)
        n = n + 1; order[n] = tonumber(i)
        return kind == "d" and "(%d+)" or "(.-)"
    end)
    pat = pat:gsub("%%([sd])", function(kind)
        n = n + 1; order[n] = n
        return kind == "d" and "(%d+)" or "(.-)"
    end)
    return "^" .. pat .. "$", order
end

-- Matches msg against a game format string and returns captures in argument order.
function ns.MatchFormat(msg, fmt)
    if type(msg) ~= "string" or type(fmt) ~= "string" then return nil end
    local pat, order = ns.PatternFromFormat(fmt)
    local caps = { msg:match(pat) }
    if #caps == 0 then return nil end
    local out = {}
    for i, argIndex in ipairs(order) do out[argIndex] = caps[i] end
    return unpack(out, 1, #order)
end

-- "*" wildcard match, case-insensitive. Used for item and chat filters.
function ns.WildMatch(text, pattern)
    if type(text) ~= "string" or type(pattern) ~= "string" or pattern == "" then return false end
    local p = pattern:lower():gsub("([%(%)%.%%%+%-%?%[%]%^%$])", "%%%1"):gsub("%*", ".*")
    return text:lower():match("^" .. p .. "$") ~= nil
end

function ns.Lines(text)
    local out = {}
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" then out[#out + 1] = line end
    end
    return out
end

function ns.Money(copper)
    copper = math.floor(tonumber(copper) or 0)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

function ns.Duration(sec)
    sec = math.floor(tonumber(sec) or 0)
    if sec >= 3600 then return string.format("%d:%02d:%02d", sec / 3600, (sec % 3600) / 60, sec % 60) end
    return string.format("%d:%02d", sec / 60, sec % 60)
end

---------------------------------------------------------------- player info
-- WoW Forever characters have a first name and a surname; UnitName returns both.
function ns.FirstName() return ns.Public((UnitName("player"))) or "Unknown" end
function ns.PlayerName()
    local first, surname = UnitName("player")
    first, surname = ns.Public(first), ns.Public(surname)
    if not first then return "Unknown" end
    if type(surname) ~= "string" or surname == "" then return first end
    local sep = Constants and Constants.CharacterNameSeparatorConsts
        and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "
    return first .. sep .. surname
end
function ns.IsMe(name)
    return type(name) == "string" and (name == ns.FirstName() or name == ns.PlayerName())
end
function ns.PlayerLevel() return ns.Public(UnitLevel("player")) or 0 end
function ns.PlayerClass()
    local localized, file = UnitClass("player")
    return ns.Public(localized) or "", ns.Public(file) or ""
end
function ns.Zone()
    return ns.Public(GetRealZoneText and GetRealZoneText()) or ns.Public(GetZoneText and GetZoneText()) or ""
end

-- Normal, PvP, Roleplay or Hardcore.
function ns.Ruleset()
    if C_GameRules and C_GameRules.IsGameRuleActive and Enum and Enum.GameRule then
        local function on(rule)
            if rule == nil then return false end
            local ok, v = pcall(C_GameRules.IsGameRuleActive, rule)
            return ok and v == true
        end
        if on(Enum.GameRule.HardcoreRuleset) then return "Hardcore" end
        if on(Enum.GameRule.PvPRuleset) then return "PvP" end
        if on(Enum.GameRule.RPRuleset) then return "Roleplay" end
    end
    return "Normal"
end

---------------------------------------------------------------- item helpers
function ns.ItemInfo(link)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not get or not link then return nil end
    local name, itemLink, quality, ilvl, _, _, _, _, _, icon, sellPrice = get(link)
    if not name then return nil end
    return { name = name, link = itemLink, quality = quality or 1, ilvl = ilvl, icon = icon, sell = sellPrice or 0 }
end

function ns.ItemID(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- Auction value from Auctionator if it's installed, in copper.
function ns.AuctionValue(link)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.GetAuctionPriceByItemLink) then return nil end
    local ok, v = pcall(api.GetAuctionPriceByItemLink, ADDON, link)
    if ok and type(v) == "number" and v > 0 then return v end
    return nil
end

ns.QUALITY = {
    [0] = { name = "Poor",      color = 0x9d9d9d },
    [1] = { name = "Common",    color = 0xffffff },
    [2] = { name = "Uncommon",  color = 0x1eff00 },
    [3] = { name = "Rare",      color = 0x0070dd },
    [4] = { name = "Epic",      color = 0xa335ee },
    [5] = { name = "Legendary", color = 0xff8000 },
    [6] = { name = "Artifact",  color = 0xe6cc80 },
}

function ns.QualityText(q)
    local info = ns.QUALITY[q or 1] or ns.QUALITY[1]
    return string.format("|cff%06x%s|r", info.color, info.name)
end

---------------------------------------------------------------- saved settings
local GENERAL_DEFAULTS = {
    live = true,           -- send alerts within seconds via screenshot data codes
    highQuality = true,    -- temporarily use the best screenshot quality
    hideChat = false,      -- hide chat windows in screenshots
    keepShots = true,      -- keep the clean screenshot in the Screenshots folder after posting
    compact = false,       -- short Discord posts: one line of text and a small screenshot on the right
    chatConfirm = true,    -- print a line in chat when an alert is queued
    minimap = true,
    minimapAngle = 200,
    linkBase = "https://www.wowhead.com/forever",
    debug = false,
}

function ns.InitDB()
    DinkForDiscordDB = DinkForDiscordDB or {}
    local db = DinkForDiscordDB
    db.webhooks = db.webhooks or { "", "", "" }
    for i = 1, 3 do db.webhooks[i] = db.webhooks[i] or "" end
    db.general = db.general or {}
    -- 1.0.0 linked to Wowhead Classic, which doesn't have Forever's new quests and items.
    if db.general.linkBase == "https://www.wowhead.com/classic" then db.general.linkBase = nil end
    for k, v in pairs(GENERAL_DEFAULTS) do
        if db.general[k] == nil then db.general[k] = v end
    end
    db.notifiers = db.notifiers or {}
    db.outbox = db.outbox or {}
    db.history = db.history or {}
    db.counter = db.counter or 0

    DinkForDiscordChar = DinkForDiscordChar or {}
    local c = DinkForDiscordChar
    c.kc = c.kc or {}
    c.standings = c.standings or {}
    c.goldReached = c.goldReached or 0
    ns.db, ns.char = db, c

    -- Notifier settings: fill in anything missing from each notifier's defaults.
    for _, n in ipairs(ns.NOTIFIERS) do
        local s = db.notifiers[n.key] or {}
        if s.enabled == nil then s.enabled = n.enabled ~= false end
        if s.screenshot == nil then s.screenshot = n.screenshot ~= false end
        if s.template == nil then s.template = n.template end
        if s.webhook == nil then s.webhook = "" end
        for _, opt in ipairs(n.options or {}) do
            if s[opt.key] == nil then s[opt.key] = opt.default end
        end
        db.notifiers[n.key] = s
    end
end

function ns.Setting(key) return ns.db and ns.db.notifiers[key] end

function ns.HasWebhook()
    for _, url in ipairs(ns.db.webhooks) do
        if ns.ValidWebhook(url) then return true end
    end
    return false
end

function ns.ValidWebhook(url)
    if type(url) ~= "string" then return false end
    return url:match("^https://[%w%.]*discord[app]*%.com/api/webhooks/%d+/[%w%-_]+") ~= nil
end

---------------------------------------------------------------- slash command
SLASH_DINKFORDISCORD1 = "/dink"
SLASH_DINKFORDISCORD2 = "/dinkfordiscord"
SlashCmdList.DINKFORDISCORD = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "test" then
        ns.SendTest()
    elseif msg == "history" then
        ns.UI:Show("history")
    elseif msg == "debug" then
        ns.db.general.debug = not ns.db.general.debug
        ns.Print("Debug messages " .. (ns.db.general.debug and "on" or "off") .. ".")
    elseif msg == "help" then
        ns.Print("/dink - open settings, /dink test - send a test alert, /dink history - recent alerts")
    else
        ns.UI:Toggle()
    end
end

---------------------------------------------------------------- startup
ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    ns.InitDB()
    if ns.Transport then ns.Transport.RestoreCVars() end
end)

ns.On("PLAYER_LOGIN", function()
    for _, fn in ipairs(ns.loginHooks or {}) do pcall(fn) end
    if ns.UI then ns.UI:Init() end
end)

function ns.OnLogin(fn)
    ns.loginHooks = ns.loginHooks or {}
    table.insert(ns.loginHooks, fn)
end
