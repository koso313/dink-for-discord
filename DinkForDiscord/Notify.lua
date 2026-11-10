local _, ns = ...

-- Every alert type, its defaults and the settings shown for it in the window.
-- Option types: check, number, quality, gold, text, lines.

local COMMON_VARS = "%PLAYER%, %LEVEL%, %CLASS%, %ZONE%"

ns.NOTIFIERS = {
    {
        key = "DEATH", name = "Death", color = 0xc0392b, delay = 1.0,
        icons = { "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", "Interface\\Icons\\Ability_Rogue_FeignDeath" },
        desc = "When your character dies. Hardcore deaths are marked as such.",
        template = "%PLAYER% has died in %ZONE%.",
        vars = "",
        options = {
            { type = "check", key = "skipPvP", label = "Ignore deaths in battlegrounds", default = true },
        },
    },
    {
        key = "LEVEL", name = "Level up", color = 0xf1c40f, delay = 0.8,
        icons = { "Interface\\Icons\\Spell_Holy_SurgeOfLight", "Interface\\Icons\\Spell_ChargePositive", "Interface\\Icons\\Spell_Holy_HolyBolt" },
        desc = "When you gain a level.",
        template = "%PLAYER% has reached level %LEVEL%!",
        vars = "",
        options = {
            { type = "number", key = "minLevel", label = "Only from level", min = 1, max = 60, step = 1, default = 1 },
            { type = "number", key = "every", label = "Every N levels", min = 1, max = 20, step = 1, default = 1 },
            { type = "check", key = "always60", label = "Always send level 60", default = true },
        },
    },
    {
        key = "LOOT", name = "Loot", color = 0xa335ee, delay = 0.3,
        icons = { "Interface\\Icons\\INV_Misc_Bag_10", "Interface\\Icons\\INV_Misc_Bag_08" },
        desc = "Items you loot. Items looted together are sent as one alert. Uses Auctionator prices when it's installed.",
        template = "%PLAYER% has looted:\n%LOOT%\nFrom: %SOURCE%",
        vars = "%LOOT%, %SOURCE%, %TOTAL_VALUE%, %COUNT%",
        options = {
            { type = "quality", key = "minQuality", label = "Minimum quality", default = 3 },
            { type = "gold", key = "minValue", label = "Or worth at least (gold, 0 = off)", min = 0, max = 100000, step = 5, default = 0 },
            { type = "lines", key = "allow", label = "Always send these items (one per line, * wildcard)", default = "" },
            { type = "lines", key = "deny", label = "Never send these items", default = "" },
            { type = "check", key = "questItems", label = "Include quest items", default = false },
        },
    },
    {
        key = "QUEST", name = "Quests", color = 0x3498db, delay = 0.3,
        icons = { "Interface\\Icons\\INV_Misc_Note_01", "Interface\\Icons\\INV_Letter_15" },
        desc = "When you turn in a quest.",
        template = "%PLAYER% has completed a quest: %QUEST%",
        vars = "%QUEST%",
        options = {
            { type = "number", key = "minLevel", label = "Only from character level", min = 1, max = 60, step = 1, default = 1 },
        },
    },
    {
        key = "BOSS", name = "Boss kills", color = 0xe67e22, delay = 0.5,
        icons = { "Interface\\Icons\\INV_Misc_Head_Dragon_01", "Interface\\Icons\\INV_Misc_Head_Dragon_Black" },
        desc = "Dungeon and raid boss kills, with your kill count and fight time.",
        template = "%PLAYER% has defeated %BOSS% with a kill count of %COUNT%.",
        vars = "%BOSS%, %COUNT%, %TIME%, %INSTANCE%",
        options = {
            { type = "check", key = "wipes", label = "Also send wipes", default = false },
        },
    },
    {
        key = "SKILL", name = "Professions", color = 0x16a085, delay = 0.3,
        icons = { "Interface\\Icons\\Trade_BlackSmithing", "Interface\\Icons\\Trade_Engineering" },
        desc = "Profession and secondary skill milestones.",
        template = "%PLAYER% has reached %LEVEL_SKILL% %SKILL%.",
        vars = "%SKILL%, %LEVEL_SKILL%",
        options = {
            { type = "number", key = "every", label = "Every N skill points", min = 1, max = 75, step = 1, default = 25 },
            { type = "check", key = "weapons", label = "Include weapon and defense skills", default = false },
        },
    },
    {
        key = "REP", name = "Reputation", color = 0x27ae60, delay = 0.3,
        icons = { "Interface\\Icons\\INV_Scroll_03", "Interface\\Icons\\INV_Misc_Note_02" },
        desc = "When you reach a new reputation standing.",
        template = "%PLAYER% is now %STANDING% with %FACTION%.",
        vars = "%FACTION%, %STANDING%",
        options = {
            { type = "number", key = "minStanding", label = "From standing (5 Friendly, 6 Honored, 7 Revered, 8 Exalted)", min = 5, max = 8, step = 1, default = 6 },
        },
    },
    {
        key = "COLLECTION", name = "Collections", color = 0x9b59b6, delay = 0.3,
        icons = { "Interface\\Icons\\Ability_Mount_RidingHorse", "Interface\\Icons\\INV_Box_PetCarrier_01" },
        desc = "New mounts, companions and toys added to your account collection.",
        template = "%PLAYER% has added %ITEM% to their %TYPE% collection.",
        vars = "%ITEM%, %TYPE%",
        options = {
            { type = "check", key = "mounts", label = "Mounts", default = true },
            { type = "check", key = "pets", label = "Companions", default = true },
            { type = "check", key = "toys", label = "Toys", default = true },
            { type = "check", key = "transmog", label = "Appearances (can be a lot)", default = false },
        },
    },
    {
        key = "LEGACY", name = "Legacy", color = 0xd4ac0d, delay = 0.8,
        icons = { "Interface\\Icons\\INV_Misc_Rune_01", "Interface\\Icons\\INV_Misc_Gem_Pearl_04" },
        desc = "Legacy (achievement) completions. Experimental until it's checked in game.",
        template = "%PLAYER% has earned %ACHIEVEMENT%.",
        vars = "%ACHIEVEMENT%, %POINTS%",
        options = {},
    },
    {
        key = "PVP", name = "PvP", color = 0xe74c3c, enabled = false, delay = 0.2,
        icons = { "Interface\\Icons\\INV_BannerPVP_02", "Interface\\Icons\\INV_BannerPVP_01" },
        desc = "Honorable kills and duel wins.",
        template = "%PLAYER% has defeated %TARGET%.",
        vars = "%TARGET%, %KIND%",
        options = {
            { type = "check", key = "honor", label = "Honorable kills", default = true },
            { type = "check", key = "duels", label = "Duel wins", default = true },
        },
    },
    {
        key = "GOLD", name = "Gold", color = 0xf39c12, delay = 0.3,
        icons = { "Interface\\Icons\\INV_Misc_Coin_02", "Interface\\Icons\\INV_Misc_Coin_01" },
        desc = "The first time your character holds a gold milestone.",
        template = "%PLAYER% now has %GOLD% gold!",
        vars = "%GOLD%",
        options = {
            { type = "text", key = "milestones", label = "Milestones in gold (comma separated)", default = "100, 250, 500, 1000, 2500, 5000" },
        },
    },
    {
        key = "TRADE", name = "Trades", color = 0x2ecc71, enabled = false, screenshot = false, delay = 0,
        icons = { "Interface\\Icons\\INV_Misc_Coin_03", "Interface\\Icons\\INV_Misc_Coin_04" },
        desc = "Completed trades with other players.",
        template = "%PLAYER% traded with %COUNTERPARTY%.",
        vars = "%COUNTERPARTY%, %GAVE%, %GOT%",
        options = {
            { type = "gold", key = "minValue", label = "Only if worth at least (gold)", min = 0, max = 100000, step = 5, default = 0 },
        },
    },
    {
        key = "AUCTION", name = "Auction House", color = 0x95a5a6, enabled = false, screenshot = false, delay = 0,
        icons = { "Interface\\Icons\\INV_Hammer_16", "Interface\\Icons\\INV_Hammer_15" },
        desc = "When one of your auctions sells, or you win one.",
        template = "%PLAYER%: %STATUS% %ITEM%",
        vars = "%ITEM%, %STATUS%",
        options = {
            { type = "check", key = "sold", label = "Auctions sold", default = true },
            { type = "check", key = "won", label = "Auctions won", default = true },
        },
    },
    {
        key = "CHAT", name = "Chat", color = 0x7289da, enabled = false, screenshot = false, delay = 0,
        icons = { "Interface\\Icons\\INV_Letter_15", "Interface\\Icons\\INV_Letter_04" },
        desc = "Chat messages that match your patterns.",
        template = "%SENDER%: %MESSAGE%",
        vars = "%SENDER%, %MESSAGE%, %CHANNEL%",
        options = {
            { type = "lines", key = "patterns", label = "Message patterns (one per line, * wildcard)", default = "" },
            { type = "check", key = "guild", label = "Guild and officer", default = true },
            { type = "check", key = "party", label = "Party and raid", default = true },
            { type = "check", key = "whisper", label = "Whispers", default = true },
            { type = "check", key = "public", label = "Say, yell and channels", default = false },
            { type = "check", key = "system", label = "System messages", default = true },
        },
    },
}

ns.NOTIFIER_BY_KEY = {}
for _, n in ipairs(ns.NOTIFIERS) do ns.NOTIFIER_BY_KEY[n.key] = n end
ns.COMMON_VARS = COMMON_VARS

---------------------------------------------------------------- building alerts
local function Fill(template, vars)
    return (template:gsub("%%([%u_]+)%%", function(name)
        local v = vars[name]
        if v == nil then return "%" .. name .. "%" end
        return tostring(v)
    end))
end
ns.FillTemplate = Fill

-- Is this alert switched on?
function ns.Enabled(key)
    local s = ns.Setting(key)
    return s and s.enabled
end

-- Sends an alert. info:
--   vars    = { NAME = value } for the message template
--   fields  = { { "Name", "value", inline }, ... } shown under the message
--   color   = embed colour (number), url = link for the title, title = override title
--   test    = true to ignore the enabled switch
function ns.Notify(key, info)
    local n = ns.NOTIFIER_BY_KEY[key]
    local s = ns.Setting(key)
    if not n or not s then return end
    if not s.enabled and not info.test then return end

    local className, classFile = ns.PlayerClass()
    local vars = info.vars or {}
    vars.PLAYER = vars.PLAYER or ns.PlayerName()
    vars.LEVEL = vars.LEVEL or ns.PlayerLevel()
    vars.CLASS = vars.CLASS or className
    vars.ZONE = vars.ZONE or ns.Zone()
    for k, v in pairs(vars) do
        if ns.IsSecret(v) then vars[k] = "?" elseif type(v) == "string" then vars[k] = ns.Plain(v) end
    end

    local fields = {}
    for _, f in ipairs(info.fields or {}) do
        local name, value = ns.Public(f[1]), ns.Public(f[2])
        if name and value ~= nil and tostring(value) ~= "" then
            fields[#fields + 1] = { ns.Plain(tostring(name)), ns.Plain(tostring(value)), f[3] and true or false }
        end
    end

    local msg = Fill(s.template ~= "" and s.template or n.template, vars)
    if #msg > 900 then msg = msg:sub(1, 897) .. "..." end
    local payload = {
        v = 1,
        t = key,
        title = info.title or n.name,
        msg = msg,
        fields = fields,
        col = info.color or n.color,
        url = info.url,
        p = vars.PLAYER,
        cls = classFile,
        lvl = tonumber(vars.LEVEL) or ns.PlayerLevel(), -- on level up, UnitLevel is still the old level
        zone = ns.Zone(),
        rs = ns.Ruleset(),
        ts = time(),
        ver = ns.VERSION,
    }
    if #fields == 0 then payload.fields = nil end
    ns.Transport.Send(payload, { image = s.screenshot, delay = n.delay })
    if ns.db.general.chatConfirm then
        ns.Print((info.test and "Test alert" or n.name .. " alert") .. " sent to the helper.")
    end
end

function ns.ItemUrl(link)
    local id = ns.ItemID(link)
    local base = ns.db.general.linkBase
    if not id or type(base) ~= "string" or base == "" then return nil end
    return base:gsub("/$", "") .. "/item=" .. id
end

---------------------------------------------------------------- test alerts
local SAMPLES = {
    DEATH = { ZONE = "Duskwood" },
    LEVEL = {},
    LOOT = { LOOT = "1 x [Thunderfury, Blessed Blade of the Windseeker] (1000g)", SOURCE = "Baron Geddon", TOTAL_VALUE = "1000g", COUNT = 1 },
    QUEST = { QUEST = "The Defias Brotherhood" },
    BOSS = { BOSS = "Edwin VanCleef", COUNT = 3, TIME = "1:42", INSTANCE = "The Deadmines" },
    SKILL = { SKILL = "Mining", LEVEL_SKILL = 150 },
    REP = { FACTION = "Stormwind", STANDING = "Exalted" },
    COLLECTION = { ITEM = "Reins of the Black Stallion", TYPE = "mount" },
    LEGACY = { ACHIEVEMENT = "Explorer of Eastern Kingdoms", POINTS = 10 },
    PVP = { TARGET = "Orcwarrior", KIND = "Honorable kill" },
    GOLD = { GOLD = 1000 },
    TRADE = { COUNTERPARTY = "Friendlyguy", GAVE = "50g", GOT = "[Arcanite Bar] x2" },
    AUCTION = { STATUS = "Sold", ITEM = "[Black Lotus]" },
    CHAT = { SENDER = "Guildie", MESSAGE = "grats on the ding!", CHANNEL = "Guild" },
}

function ns.SendTest(key)
    if not ns.HasWebhook() then
        ns.Print("Add a Discord webhook first: /dink")
    end
    if key then
        local vars = {}
        for k, v in pairs(SAMPLES[key] or {}) do vars[k] = v end
        ns.Notify(key, { vars = vars, test = true, title = ns.NOTIFIER_BY_KEY[key].name .. " (test)" })
        return
    end
    ns.Transport.Send({
        v = 1, t = "TEST", title = "Dink For Discord is connected",
        msg = ns.PlayerName() .. " is ready to send alerts from World of Warcraft: Forever.",
        col = 0x7289da, p = ns.PlayerName(), cls = select(2, ns.PlayerClass()), lvl = ns.PlayerLevel(),
        zone = ns.Zone(), rs = ns.Ruleset(), ts = time(), ver = ns.VERSION,
    }, { image = true, delay = 0.2 })
    ns.Print("Test alert sent to the helper. It should appear in Discord in a few seconds.")
end
