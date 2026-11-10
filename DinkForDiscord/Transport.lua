local _, ns = ...

-- Gets alerts out of the game. Addons can't use the internet, so for each alert:
--   1. (optional) take a normal screenshot to attach to the Discord post,
--   2. draw the data code and take a second screenshot that the helper app decodes and deletes.
-- Every alert is also saved in DinkForDiscordDB.outbox. The helper posts anything it
-- missed from there when WoW saves (on /reload, logout or exit).

local Transport = {}
ns.Transport = Transport

local OUTBOX_MAX = 100
local HISTORY_MAX = 60
local WAIT_TIMEOUT = 4

local queue = {}
local state = "idle"      -- idle, hold, prep, wait
local lastShotSecond = 0  -- WoW names screenshots by the second; two in one second overwrite each other
local current, waitUntil, nextAt, framesLeft, shotResult
local runner = CreateFrame("Frame")
runner:Hide()

---------------------------------------------------------------- cvars
local function GetCV(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
    if GetCVar then return GetCVar(name) end
end
local function SetCV(name, value)
    local ok = pcall(function()
        if C_CVar and C_CVar.SetCVar then C_CVar.SetCVar(name, value) elseif SetCVar then SetCVar(name, value) end
    end)
    return ok
end

local function BoostQuality()
    if ns.db.savedQuality == nil then ns.db.savedQuality = GetCV("screenshotQuality") or false end
    SetCV("screenshotQuality", "10")
end

-- Puts the player's screenshot quality back. Also runs at load in case of a /reload mid-capture.
function Transport.RestoreCVars()
    if ns.db and ns.db.savedQuality ~= nil then
        if ns.db.savedQuality then SetCV("screenshotQuality", ns.db.savedQuality) end
        ns.db.savedQuality = nil
    end
end

---------------------------------------------------------------- hiding our window, chat and "Screen captured"
local hiddenChat = {}
local function Fade(f)
    if f and f.GetAlpha and f:IsShown() and f:GetAlpha() > 0 then
        hiddenChat[#hiddenChat + 1] = { f, f:GetAlpha() }
        f:SetAlpha(0)
    end
end

-- Runs just before the normal screenshot. Our own window and tooltip are always hidden
-- (so test alerts don't show the settings), chat only if the player asked for it.
local function HideChat()
    Fade(_G.DinkForDiscordFrame)
    if GameTooltip and GameTooltip.GetOwner then
        local owner = GameTooltip:GetOwner()
        if owner and (owner == _G.DinkForDiscordMinimapButton or (_G.DinkForDiscordFrame and owner.GetParent
            and owner:GetParent() == _G.DinkForDiscordFrame)) then
            Fade(GameTooltip)
        end
    end
    if not ns.db.general.hideChat then return end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local f = _G["ChatFrame" .. i]
        if f and f:IsShown() and f:GetAlpha() > 0 then
            hiddenChat[#hiddenChat + 1] = { f, f:GetAlpha() }
            f:SetAlpha(0)
        end
    end
    for _, name in ipairs({ "GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton", "QuickJoinToastButton" }) do
        local f = _G[name]
        if f and f.GetAlpha and f:GetAlpha() > 0 then
            hiddenChat[#hiddenChat + 1] = { f, f:GetAlpha() }
            f:SetAlpha(0)
        end
    end
end
local function ShowChat()
    for _, entry in ipairs(hiddenChat) do entry[1]:SetAlpha(entry[2]) end
    wipe(hiddenChat)
end

local quietUntil = 0
local function HookActionStatus()
    if ActionStatus and ActionStatus.HookScript and not Transport.hooked then
        Transport.hooked = true
        ActionStatus:HookScript("OnShow", function(self)
            if GetTime() < quietUntil then self:Hide() end
        end)
    end
end

---------------------------------------------------------------- outbox
function Transport.NextID()
    ns.db.counter = (ns.db.counter or 0) + 1
    local guid = ns.Public(UnitGUID("player")) or ns.PlayerName()
    return string.format("%s-%d-%d", tostring(guid):gsub("^Player%-", ""), time(), ns.db.counter)
end

local function SaveOutbox(json, payload)
    local box = ns.db.outbox
    box[#box + 1] = json
    while #box > OUTBOX_MAX do table.remove(box, 1) end

    local hist = ns.db.history
    table.insert(hist, 1, { id = payload.id, ts = payload.ts, t = payload.t, title = payload.title, msg = payload.msg })
    while #hist > HISTORY_MAX do table.remove(hist) end
    if ns.UI and ns.UI.OnHistoryChanged then ns.UI:OnHistoryChanged() end
end

---------------------------------------------------------------- queue
-- payload: table from ns.Notify. opts.image: take a screenshot for the post. opts.delay: seconds before it.
function Transport.Send(payload, opts)
    opts = opts or {}
    payload.id = payload.id or Transport.NextID()
    payload.img = 0
    SaveOutbox(ns.Json.Encode(payload), payload)
    if not ns.db.general.live then return end
    queue[#queue + 1] = { payload = payload, image = opts.image, at = GetTime() + (opts.delay or 0) }
    runner:Show()
end

function Transport.Busy() return state ~= "idle" or #queue > 0 end

local function TakeShot()
    local fn = _G.Screenshot or _G.TakeScreenshot
    if not fn then return false end
    return pcall(fn)
end

local function Finish()
    ns.Strip.Hide()
    ShowChat()
    Transport.RestoreCVars()
    current, state = nil, "idle"
    nextAt = GetTime() + 0.25
    if #queue == 0 then runner:Hide() end
end

-- Steps: clean shot (optional) -> data shot -> done. Each shot waits for SCREENSHOT_SUCCEEDED.
local function Step()
    local now = GetTime()
    if state == "idle" then
        if #queue == 0 then runner:Hide(); return end
        if now < (nextAt or 0) or now < (queue[1].at or 0) then return end
        current = table.remove(queue, 1)
        current.phase = current.image and "clean" or "data"
        state = "hold"
        quietUntil = now + 10
        HookActionStatus()
    elseif state == "hold" then
        -- Wait for the clock to reach a new second before the next screenshot.
        if time() <= lastShotSecond then return end
        if ns.db.general.highQuality or current.phase == "data" then BoostQuality() end
        if current.phase == "clean" then HideChat() else
            ns.Strip.Show(ns.Json.Encode(current.payload))
        end
        state, framesLeft = "prep", 2
    elseif state == "prep" then
        framesLeft = framesLeft - 1
        if framesLeft > 0 then return end
        shotResult = nil
        if not TakeShot() then
            lastShotSecond = time()
            if current.phase == "clean" then current.image = false end
            Finish()
            return
        end
        state, waitUntil = "wait", now + WAIT_TIMEOUT
    elseif state == "wait" then
        if shotResult == nil and now < waitUntil then return end
        local ok = shotResult == true
        lastShotSecond = math.max(lastShotSecond, time())
        if current.phase == "clean" then
            ShowChat()
            current.payload.img = ok and 1 or 0
            current.phase = "data"
            state = "hold"
        else
            if not ok and ns.db.general.debug then ns.Print("Screenshot failed; the helper will post this alert from saved data.") end
            quietUntil = now + 1.5
            Finish()
        end
    end
end
runner:SetScript("OnUpdate", Step)

ns.On("SCREENSHOT_SUCCEEDED", function()
    lastShotSecond = math.max(lastShotSecond, time())
    if state == "wait" then shotResult = true end
end)
ns.On("SCREENSHOT_FAILED", function() if state == "wait" then shotResult = false end end)
