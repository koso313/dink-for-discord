-- A fake WoW client, just enough to run Dink For Discord outside the game.
-- Frames accept any method call; a few return useful values. Events and OnUpdate
-- are driven by the Python test (FireEvent / Tick).

TEST = { frames = {}, chat = {}, shots = {}, now = 1000, timers = {}, secret = {}, items = {}, bags = {}, cvars = {} }

local Mock = {}
local function mock(kind, parent)
    local o = { _kind = kind, _scripts = {}, _events = {}, _shown = true, _points = {}, _children = {},
                _w = 100, _h = 20, _text = "", _alpha = 1, _parent = parent, _scale = 1 }
    setmetatable(o, Mock)
    table.insert(TEST.frames, o)
    return o
end

local methods = {}
function methods:SetScript(name, fn) self._scripts[name] = fn end
function methods:GetScript(name) return self._scripts[name] end
function methods:HookScript(name, fn)
    local old = self._scripts[name]
    self._scripts[name] = function(...) if old then old(...) end fn(...) end
end
function methods:RegisterEvent(e)
    if e:match("^FAKE_") then error("unknown event") end
    self._events[e] = true
end
function methods:UnregisterEvent(e) self._events[e] = nil end
function methods:Show() self._shown = true end
function methods:Hide() self._shown = false end
function methods:SetShown(v) self._shown = v and true or false end
function methods:IsShown() return self._shown end
function methods:IsVisible() return self._shown end
function methods:SetPoint(...) self._points[#self._points + 1] = { ... } end
function methods:ClearAllPoints() self._points = {} end
function methods:SetSize(w, h) self._w, self._h = w, h end
function methods:SetWidth(w) self._w = w end
function methods:SetHeight(h) self._h = h end
function methods:GetWidth() return self._w end
function methods:GetHeight() return self._h end
function methods:SetText(t) self._text = t end
function methods:GetText() return self._text end
function methods:GetStringHeight() return 14 end
function methods:GetStringWidth() return #tostring(self._text) * 6 end
function methods:SetColorTexture(r, g, b, a) self._color = { r, g, b, a } end
function methods:SetAlpha(a) self._alpha = a end
function methods:GetAlpha() return self._alpha end
function methods:SetScale(s) self._scale = s end
function methods:GetEffectiveScale() return 1 end
function methods:GetChecked() return self._checked end
function methods:SetChecked(v) self._checked = v end
function methods:GetCenter() return 50, 50 end
function methods:GetParent() return self._parent end
function methods:CreateTexture() local t = mock("Texture", self); self._children[#self._children + 1] = t; return t end
function methods:CreateFontString() local t = mock("FontString", self); self._children[#self._children + 1] = t; return t end
function methods:GetName() return self._name end
function methods:SetTitle(t) self._title = t end

Mock.__index = function(self, key)
    if methods[key] then return methods[key] end
    if type(key) == "string" and key:sub(1, 1) == "_" then return nil end
    -- Any other method: do nothing.
    return function() return nil end
end

function CreateFrame(kind, name, parent, template)
    local f = mock(kind, parent)
    f._name = name
    f._template = template
    if name then _G[name] = f end
    if template and template:find("ButtonFrameTemplate") then
        f.Inset = mock("Frame", f)
        f.portrait = f:CreateTexture()
    end
    return f
end

UIParent = CreateFrame("Frame", "UIParent")
Minimap = CreateFrame("Frame", "Minimap")
WorldFrame = CreateFrame("Frame", "WorldFrame")
GameTooltip = CreateFrame("Frame", "GameTooltip")
ActionStatus = CreateFrame("Frame", "ActionStatus")
ChatFrame1 = CreateFrame("Frame", "ChatFrame1")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(TEST.chat, msg) end }
UISpecialFrames, StaticPopupDialogs, SlashCmdList = {}, {}, {}
NUM_CHAT_WINDOWS, NUM_BAG_SLOTS, MAX_TRADABLE_ITEMS = 1, 4, 6

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert, tremove = table.insert, table.remove
date = os.date
function time() return 1700000000 + math.floor(TEST.now) end
function hooksecurefunc() end
function ReloadUI() TEST.reloaded = true end
function StaticPopup_Show() end
function ScrollingEdit_OnTextChanged() end
function ScrollingEdit_OnCursorChanged() end
function ScrollingEdit_OnUpdate() end
function GetTime() return TEST.now end
function GetCursorPosition() return 0, 0 end
function GetPhysicalScreenSize() return TEST.screenW or 1920, TEST.screenH or 1080 end
function issecretvalue(v) return TEST.secret[v] == true end

C_Timer = { After = function(d, fn) table.insert(TEST.timers, { at = TEST.now + d, fn = fn }) end }
C_CVar = {
    GetCVar = function(n) return TEST.cvars[n] end,
    SetCVar = function(n, v) TEST.cvars[n] = v end,
}
TEST.cvars.screenshotQuality = "3"

function Screenshot()
    local strip
    for _, f in ipairs(TEST.frames) do
        if f._kind == "Frame" and f._parent == nil and f._strata == "TOOLTIP" and f._shown then strip = f end
    end
    local shot = { quality = TEST.cvars.screenshotQuality, chatAlpha = ChatFrame1._alpha, sec = time(),
                   windowAlpha = DinkForDiscordFrame and DinkForDiscordFrame._shown and DinkForDiscordFrame._alpha or nil }
    if strip then
        shot.cells = {}
        for _, t in ipairs(strip._children) do
            if t._shown and t._color and t._points[1] and t._points[1][4] then
                table.insert(shot.cells, { x = t._points[1][4], y = -t._points[1][5], w = t._w, h = t._h,
                    r = t._color[1], g = t._color[2], b = t._color[3] })
            end
        end
        shot.w, shot.h = strip._w, strip._h
    end
    table.insert(TEST.shots, shot)
    TEST.pendingShot = true
end
methods.SetFrameStrata = function(self, s) self._strata = s end

-- Player and world
function UnitName(u) if u == "player" then return "Thrall", "Stormrider" end if u == "target" then return TEST.targetName end if u == "NPC" then return "Jaina" end end
function UnitLevel() return TEST.level or 42 end
function UnitClass() return "Paladin", "PALADIN" end
function UnitGUID() return "Player-1-0ABCDEF" end
function UnitExists(u) return u == "target" and TEST.targetName ~= nil end
function UnitIsDead(u) return u == "target" and TEST.targetDead end
function GetRealZoneText() return "Stranglethorn Vale" end
function GetZoneText() return "Stranglethorn Vale" end
function IsInInstance() return false, "none" end
function GetInstanceInfo() return "The Deadmines" end
function GetMoney() return TEST.money or 0 end
function GetTitleText() return "Wanted: Gath'Ilzogg" end
C_QuestLog = { GetTitleForQuestID = function(id) return id == 169 and "Wanted: Gath'Ilzogg" or nil end }
C_Map = { GetBestMapForUnit = function() return 224 end,
          GetPlayerMapPosition = function() return { GetXY = function() return 0.381, 0.554 end } end }
C_GameRules = nil

function GetItemInfo(link)
    local id = tonumber(tostring(link):match("item:(%d+)")) or tonumber(link)
    local it = TEST.items[id]
    if not it then return nil end
    return it.name, it.link, it.quality, 60, 60, "Weapon", "Sword", 1, "", 135349, it.sell
end
function GetItemInfoInstant(link)
    local id = tonumber(tostring(link):match("item:(%d+)")) or tonumber(link)
    local it = TEST.items[id]
    return id, nil, nil, nil, 135349, it and it.classID or 2
end

C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end,
    GetContainerItemInfo = function(bag, slot)
        local s = TEST.bags[slot]
        if bag ~= 0 or not s then return nil end
        return { hyperlink = s.link, stackCount = s.count }
    end,
}

function GetNumFactions() return #(TEST.factions or {}) end
function GetFactionInfo(i)
    local f = TEST.factions[i]
    return f.name, "", f.standing, 0, 0, 0, false, false, false, false, true, false, false, f.id
end
for i = 1, 8 do _G["FACTION_STANDING_LABEL" .. i] = ({ "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" })[i] end

function GetNumSkillLines() return 3 end
function GetSkillLineInfo(i)
    return ({ { "Professions", true }, { "Mining", false }, { "Weapon Skills", true } })[i][1],
           ({ { "Professions", true }, { "Mining", false }, { "Weapon Skills", true } })[i][2]
end

-- enUS global strings the addon parses
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
ERR_SKILL_UP_SI = "Your skill in %s has increased to %d."
COMBATLOG_HONORGAIN = "%s dies, honorable kill Rank: %s (Estimated Honor Points: %d)"
DUEL_WINNER_KNOCKOUT = "%1$s has defeated %2$s in a duel"
DUEL_WINNER_RETREAT = "%2$s has fled from %1$s in a duel"
ERR_AUCTION_SOLD_S = "A buyer has been found for your auction of %s."
ERR_AUCTION_WON_S = "You won an auction for %s"
ERR_TRADE_COMPLETE = "Trade complete."
TRADE_SKILLS = "Professions"
YES, NO = "Yes", "No"

-- Test drivers ------------------------------------------------------------
function TEST.Fire(event, ...)
    for _, f in ipairs(TEST.frames) do
        if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
    end
end

function TEST.Tick(dt)
    TEST.now = TEST.now + (dt or 0.016)
    local due = {}
    for i = #TEST.timers, 1, -1 do
        if TEST.timers[i].at <= TEST.now then table.insert(due, table.remove(TEST.timers, i)) end
    end
    for i = #due, 1, -1 do due[i].fn() end
    for _, f in ipairs(TEST.frames) do
        if f._shown and f._scripts.OnUpdate then f._scripts.OnUpdate(f, dt or 0.016) end
    end
    if TEST.pendingShot then
        TEST.pendingShot = false
        TEST.Fire("SCREENSHOT_SUCCEEDED")
    end
end

function TEST.Run(seconds)
    local steps = math.floor(seconds / 0.016)
    for _ = 1, steps do TEST.Tick(0.016) end
end
