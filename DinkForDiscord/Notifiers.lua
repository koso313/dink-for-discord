local _, ns = ...

-- Death, level, quest, boss, profession, reputation, gold and PvP alerts.

local function S(key) return ns.Setting(key) end

---------------------------------------------------------------- death
ns.On("PLAYER_DEAD", function()
    if not ns.Enabled("DEATH") then return end
    local _, instanceType = IsInInstance()
    if S("DEATH").skipPvP and (instanceType == "pvp" or instanceType == "arena") then return end
    local hardcore = ns.Ruleset() == "Hardcore"
    local x, y
    if C_Map and C_Map.GetBestMapForUnit then
        local map = C_Map.GetBestMapForUnit("player")
        local pos = map and C_Map.GetPlayerMapPosition(map, "player")
        if pos and not ns.IsSecret(pos) then x, y = pos:GetXY() end
    end
    ns.Notify("DEATH", {
        title = hardcore and "Hardcore death" or nil,
        color = hardcore and 0x010101 or nil, -- 0 means "no colour" to Discord
        fields = {
            { "Level", ns.PlayerLevel(), true },
            { "Zone", ns.Zone(), true },
            x and { "Location", string.format("%.1f, %.1f", x * 100, y * 100), true } or {},
        },
    })
end)

---------------------------------------------------------------- level
ns.On("PLAYER_LEVEL_UP", function(level)
    level = tonumber(ns.Public(level))
    if not level or not ns.Enabled("LEVEL") then return end
    local s = S("LEVEL")
    local wanted = level >= (s.minLevel or 1) and (level % math.max(1, s.every or 1) == 0)
    if s.always60 and level == 60 then wanted = true end
    if not wanted then return end
    ns.Notify("LEVEL", { vars = { LEVEL = level }, fields = { { "Level", level, true }, { "Zone", ns.Zone(), true } } })
end)

---------------------------------------------------------------- quests
local function QuestTitle(id)
    if C_QuestLog then
        if C_QuestLog.GetTitleForQuestID then
            local t = C_QuestLog.GetTitleForQuestID(id)
            if t then return t end
        end
        if C_QuestLog.GetQuestInfo then
            local t = C_QuestLog.GetQuestInfo(id)
            if t then return t end
        end
    end
    return nil
end

-- The quest title is only easy to get while the turn-in window is open, so remember it.
local lastQuestTitle
ns.On("QUEST_COMPLETE", function() lastQuestTitle = ns.Public(GetTitleText and GetTitleText()) end)

ns.On("QUEST_TURNED_IN", function(questID, xp, money)
    if not ns.Enabled("QUEST") then return end
    if ns.PlayerLevel() < (S("QUEST").minLevel or 1) then return end
    questID = ns.Public(questID)
    local title = (questID and QuestTitle(questID)) or lastQuestTitle or ("Quest " .. tostring(questID or "?"))
    lastQuestTitle = nil
    xp, money = tonumber(ns.Public(xp)) or 0, tonumber(ns.Public(money)) or 0
    local base = ns.db.general.linkBase
    ns.Notify("QUEST", {
        vars = { QUEST = title },
        url = (questID and base ~= "") and (base:gsub("/$", "") .. "/quest=" .. questID) or nil,
        fields = {
            xp > 0 and { "Experience", xp, true } or {},
            money > 0 and { "Money", ns.Money(money), true } or {},
        },
    })
end)

---------------------------------------------------------------- boss kills
local encounterStart = {}
ns.On("ENCOUNTER_START", function(id) id = ns.Public(id); if id then encounterStart[id] = GetTime() end end)

ns.On("ENCOUNTER_END", function(id, name, difficulty, size, success)
    if not ns.Enabled("BOSS") then return end
    id, name, success = ns.Public(id), ns.Public(name), ns.Public(success)
    if not id or not name then return end
    local won = success == 1 or success == true
    if not won and not S("BOSS").wipes then return end
    local fight = encounterStart[id] and (GetTime() - encounterStart[id]) or nil
    encounterStart[id] = nil
    local count = ns.char.kc[id] or 0
    if won then count = count + 1; ns.char.kc[id] = count end
    local instance = ns.Public((GetInstanceInfo())) or ns.Zone()
    ns.Notify("BOSS", {
        title = (not won) and "Wipe" or nil,
        color = (not won) and 0x7f8c8d or nil,
        vars = { BOSS = name, COUNT = count, TIME = fight and ns.Duration(fight) or "?", INSTANCE = instance },
        fields = {
            { "Kill count", count, true },
            fight and { "Fight time", ns.Duration(fight), true } or {},
            { "Instance", instance, true },
            size and ns.Public(size) and { "Group size", ns.Public(size), true } or {},
        },
    })
end)

---------------------------------------------------------------- professions
local function SkillHeader(skillName)
    if not (GetNumSkillLines and GetSkillLineInfo) then return nil end
    local header
    for i = 1, GetNumSkillLines() do
        local name, isHeader = GetSkillLineInfo(i)
        if isHeader then header = name elseif name == skillName then return header end
    end
    return nil
end

local function IsProfession(skillName)
    local header = SkillHeader(skillName)
    if not header then return true end
    local h = header:lower()
    if (TRADE_SKILLS and header == TRADE_SKILLS) or (SECONDARY_SKILLS and header:find(SECONDARY_SKILLS, 1, true)) then return true end
    return h:find("profession") ~= nil or h:find("secondary") ~= nil
end

ns.On("CHAT_MSG_SKILL", function(msg)
    if not ns.Enabled("SKILL") or ns.IsSecret(msg) then return end
    local skill, level = ns.MatchFormat(msg, ERR_SKILL_UP_SI)
    level = tonumber(level)
    if not skill or not level then return end
    local s = S("SKILL")
    if level % math.max(1, s.every or 25) ~= 0 then return end
    if not s.weapons and not IsProfession(skill) then return end
    ns.Notify("SKILL", { vars = { SKILL = skill, LEVEL_SKILL = level }, fields = { { "Skill", skill, true }, { "Level", level, true } } })
end)

---------------------------------------------------------------- reputation
local function EachFaction(fn)
    if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
        for i = 1, C_Reputation.GetNumFactions() do
            local d = C_Reputation.GetFactionDataByIndex(i)
            if d and not d.isHeader and d.name then fn(d.factionID or d.name, d.name, d.reaction) end
        end
    elseif GetNumFactions and GetFactionInfo then
        for i = 1, GetNumFactions() do
            local name, _, standing, _, _, _, _, _, isHeader, _, hasRep, _, _, factionID = GetFactionInfo(i)
            if name and (not isHeader or hasRep) then fn(factionID or name, name, standing) end
        end
    end
end

local repReady = false
local function ScanRep(notify)
    EachFaction(function(id, name, standing)
        if ns.IsSecret(standing) or ns.IsSecret(name) then return end
        local key = tostring(id)
        local old = ns.char.standings[key]
        ns.char.standings[key] = standing
        if notify and old and standing and standing > old and ns.Enabled("REP") and standing >= (S("REP").minStanding or 6) then
            local label = _G["FACTION_STANDING_LABEL" .. standing] or tostring(standing)
            ns.Notify("REP", { vars = { FACTION = name, STANDING = label }, fields = { { "Faction", name, true }, { "Standing", label, true } } })
        end
    end)
end

ns.On("PLAYER_ENTERING_WORLD", function()
    ns.After(3, function() ScanRep(false); repReady = true end)
end)
ns.On("UPDATE_FACTION", function()
    if repReady then ScanRep(true) end
end)

---------------------------------------------------------------- gold milestones
local function Milestones()
    local list = {}
    for n in tostring(S("GOLD").milestones or ""):gmatch("[%d%.]+") do list[#list + 1] = tonumber(n) end
    table.sort(list)
    return list
end

local function CheckGold(notify)
    local copper = ns.Public(GetMoney())
    if not copper then return end
    local gold = math.floor(copper / 10000)
    local best = ns.char.goldReached or 0
    local hit
    for _, m in ipairs(Milestones()) do
        if gold >= m and m > best then hit = m end
    end
    if hit then
        ns.char.goldReached = hit
        if notify and ns.Enabled("GOLD") then
            ns.Notify("GOLD", { vars = { GOLD = hit }, fields = { { "Milestone", hit .. "g", true }, { "Total", ns.Money(copper), true } } })
        end
    end
end

ns.OnLogin(function()
    -- Don't announce milestones a character already had before installing the addon.
    if ns.char.goldReached == 0 then CheckGold(false) end
end)
ns.On("PLAYER_MONEY", function() CheckGold(true) end)

---------------------------------------------------------------- PvP
ns.On("CHAT_MSG_COMBAT_HONOR_GAIN", function(msg)
    if not ns.Enabled("PVP") or not S("PVP").honor or ns.IsSecret(msg) then return end
    local target, rank = ns.MatchFormat(msg, COMBATLOG_HONORGAIN)
    if not target then return end
    ns.Notify("PVP", { vars = { TARGET = target, KIND = "Honorable kill" }, fields = { { "Target", target, true }, rank and { "Rank", rank, true } or {} } })
end)

ns.On("CHAT_MSG_SYSTEM", function(msg)
    if not ns.Enabled("PVP") or not S("PVP").duels or ns.IsSecret(msg) then return end
    for _, fmt in ipairs({ DUEL_WINNER_KNOCKOUT, DUEL_WINNER_RETREAT }) do
        local winner, loser = ns.MatchFormat(msg, fmt)
        if winner and ns.IsMe(winner) then
            ns.Notify("PVP", { vars = { TARGET = loser, KIND = "Duel" }, title = "Duel won", fields = { { "Opponent", loser, true } } })
            return
        end
    end
end)
