local _, ns = ...

-- The Dink For Discord window: Discord setup, alerts, screenshots & delivery, history.

local UI = {}
ns.UI = UI
local W = ns.W

local FW, FH = 760, 590
local TABS = {
    { key = "discord",  label = "1. Discord",  heading = "Connect to Discord",       sub = "Three quick steps and your alerts start posting." },
    { key = "alerts",   label = "2. Alerts",   heading = "Choose your alerts",       sub = "Pick what gets posted, when, and how the message reads." },
    { key = "delivery", label = "3. Screenshots & delivery", heading = "Screenshots & delivery", sub = "How alerts and screenshots get to Discord." },
    { key = "history",  label = "History",     heading = "Recent alerts",            sub = "The last alerts this addon sent to the helper." },
}

---------------------------------------------------------------- window
local function SetTitle(f, text)
    if f.SetTitle then f:SetTitle(text)
    elseif f.TitleText then f.TitleText:SetText(text)
    elseif f.TitleContainer and f.TitleContainer.TitleText then f.TitleContainer.TitleText:SetText(text) end
end

local function SetPortrait(f)
    local tex = f.portrait or (f.PortraitContainer and f.PortraitContainer.portrait)
    if f.SetPortraitToAsset then pcall(f.SetPortraitToAsset, f, ns.ICON); return end
    if tex then
        if SetPortraitToTexture then pcall(SetPortraitToTexture, tex, ns.ICON) else tex:SetTexture(ns.ICON) end
    end
end

-- Webhooks and the settings the helper reads; used to tell when a reload is needed.
local function HelperSignature()
    local parts = {}
    for _, url in ipairs(ns.db.webhooks) do parts[#parts + 1] = url end
    for _, n in ipairs(ns.NOTIFIERS) do parts[#parts + 1] = ns.db.notifiers[n.key].webhook or "" end
    parts[#parts + 1] = tostring(ns.db.general.keepShots)
    return table.concat(parts, "\1")
end

function UI:Init()
    self.savedSignature = HelperSignature()
    self:BuildMinimapButton()
    if not ns.HasWebhook() then
        ns.Print("Not connected to Discord yet. Type |cffffd100/dink|r to set it up.")
        if not ns.db.setupSeen then
            ns.db.setupSeen = true
            ns.After(3, function() UI:Show("discord") end)
        end
    end
end

function UI:Build()
    if self.frame then return end
    local f = CreateFrame("Frame", "DinkForDiscordFrame", UIParent, "ButtonFrameTemplate")
    self.frame = f
    f:SetSize(FW, FH)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if type(f.Inset) ~= "table" then f.Inset = CreateFrame("Frame", nil, f, "InsetFrameTemplate") end
    SetTitle(f, ns.TITLE)
    SetPortrait(f)
    tinsert(UISpecialFrames, "DinkForDiscordFrame")
    f:Hide()

    f.heading = W.Text(f, "GameFontNormalLarge", FW - 90)
    f.heading:SetPoint("TOPLEFT", 66, -30)
    f.sub = W.Text(f, "GameFontHighlightSmall", FW - 90)
    f.sub:SetPoint("TOPLEFT", f.heading, "BOTTOMLEFT", 0, -3)

    f.Inset:ClearAllPoints()
    f.Inset:SetPoint("TOPLEFT", 4, -64)
    f.Inset:SetPoint("BOTTOMRIGHT", -6, 30)

    -- Tab strip, styled like the Paladin guide's step labels.
    f.tabs = {}
    local x = 20
    for _, tab in ipairs(TABS) do
        local b = CreateFrame("Button", nil, f.Inset)
        b:SetHeight(24)
        b.text = W.Text(b, "GameFontNormal")
        b.text:SetPoint("LEFT")
        b.text:SetText(tab.label)
        b:SetWidth(b.text:GetStringWidth() + 8)
        b:SetPoint("TOPLEFT", x, -8)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b:SetScript("OnClick", function() UI:SelectTab(tab.key) end)
        x = x + b:GetWidth() + 26
        f.tabs[tab.key] = b
    end
    local line = f.Inset:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 10, -34)
    line:SetPoint("TOPRIGHT", -10, -34)

    f.pages = {}
    for _, tab in ipairs(TABS) do
        local p = CreateFrame("Frame", nil, f.Inset)
        p:SetPoint("TOPLEFT", 10, -42)
        p:SetPoint("BOTTOMRIGHT", -10, 8)
        p:Hide()
        f.pages[tab.key] = p
    end

    -- Bottom bar.
    f.status = W.Text(f, "GameFontHighlightSmall", 420)
    f.status:SetPoint("BOTTOMLEFT", 16, 10)
    f.save = W.Button(f, 150, 22, "Save & Reload", function() ReloadUI() end)
    f.save:SetPoint("BOTTOMRIGHT", -8, 5)
    f.test = W.Button(f, 140, 22, "Send test alert", function() ns.SendTest() end)
    f.test:SetPoint("RIGHT", f.save, "LEFT", -6, 0)

    self:BuildDiscord(f.pages.discord)
    self:BuildAlerts(f.pages.alerts)
    self:BuildDelivery(f.pages.delivery)
    self:BuildHistory(f.pages.history)

    f:SetScript("OnShow", function() UI:Refresh() end)
    f:SetScript("OnUpdate", function(_, elapsed)
        UI.statusTimer = (UI.statusTimer or 0) + elapsed
        if UI.statusTimer > 0.5 then UI.statusTimer = 0; UI:RefreshStatus() end
    end)
end

function UI:SelectTab(key)
    self.tab = key
    for _, tab in ipairs(TABS) do
        local on = tab.key == key
        self.frame.pages[tab.key]:SetShown(on)
        local b = self.frame.tabs[tab.key]
        if on then
            b.text:SetTextColor(1, 0.82, 0)
            self.frame.heading:SetText(tab.heading)
            self.frame.sub:SetText(tab.sub)
        else
            b.text:SetTextColor(0.62, 0.62, 0.62)
        end
    end
    if key == "history" then self:RefreshHistory() end
end

function UI:Show(tab)
    self:Build()
    self.frame:Show()
    self:SelectTab(tab or self.tab or (ns.HasWebhook() and "alerts" or "discord"))
end

function UI:Hide() if self.frame then self.frame:Hide() end end
function UI:Toggle()
    if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end
end

function UI:NeedsReload() return self.savedSignature ~= nil and HelperSignature() ~= self.savedSignature end

function UI:RefreshStatus()
    local f = self.frame
    if not f then return end
    if not ns.HasWebhook() then
        f.status:SetText(W.Color("Not connected: paste a Discord webhook on the Discord tab.", W.RED))
    elseif self:NeedsReload() then
        f.status:SetText(W.Color("Changes not saved for the helper yet. Click Save & Reload.", W.GOLD))
    elseif not ns.db.general.live then
        f.status:SetText(W.Color("Alerts post when you /reload, log out or quit.", W.GREY))
    else
        f.status:SetText(W.Color("Connected. Alerts post within a few seconds while the helper runs.", W.GREEN))
    end
    if f.webhookChecks then
        for i, tex in ipairs(f.webhookChecks) do
            local url = ns.db.webhooks[i] or ""
            tex:SetShown(url ~= "")
            tex:SetTexture(ns.ValidWebhook(url) and "Interface\\RaidFrame\\ReadyCheck-Ready" or "Interface\\RaidFrame\\ReadyCheck-NotReady")
        end
    end
end

function UI:Refresh()
    if not self.frame then return end
    for _, w in ipairs(self.refreshers or {}) do w:Refresh() end
    self:RefreshList()
    self:RefreshStatus()
    if self.tab == "history" then self:RefreshHistory() end
end

local function Track(widget)
    UI.refreshers = UI.refreshers or {}
    table.insert(UI.refreshers, widget)
    return widget
end

---------------------------------------------------------------- Discord tab
local function StepCard(parent, num, title, height, width)
    local c = W.Box(parent, width, height)
    c.num = c:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    c.num:SetPoint("TOPLEFT", 14, -12)
    c.num:SetText(num)
    c.title = W.Text(c, "GameFontNormalLarge", width - 70)
    c.title:SetPoint("TOPLEFT", 46, -14)
    c.title:SetText(title)
    c.body = W.Text(c, "GameFontHighlight", width - 70)
    c.body:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -6)
    c.body:SetTextColor(0.85, 0.85, 0.85)
    return c
end

function UI:BuildDiscord(p)
    local width = FW - 40

    local c1 = StepCard(p, "1", "Create a webhook in Discord", 84, width)
    c1:SetPoint("TOPLEFT", 0, 0)
    c1.body:SetText("In your Discord server open |cffffd100Server Settings > Integrations > Webhooks|r and click |cffffd100New Webhook|r. "
        .. "Pick the channel for your alerts, then click |cffffd100Copy Webhook URL|r.")

    local c2 = StepCard(p, "2", "Paste it here", 150, width)
    c2:SetPoint("TOPLEFT", c1, "BOTTOMLEFT", 0, -8)
    c2.body:SetText("Click a box and press Ctrl+V. Extra webhooks get every alert too (another channel or server).")
    self.frame.webhookChecks = {}
    local labels = { "Main webhook", "Extra webhook", "Extra webhook" }
    for i = 1, 3 do
        local label = W.Text(c2, "GameFontNormal", 110)
        label:SetPoint("TOPLEFT", 46, -60 - (i - 1) * 28)
        label:SetText(labels[i])
        local e = Track(W.EditLine(c2, width - 210, function() return ns.db.webhooks[i] end, function(v)
            ns.db.webhooks[i] = v:match("^%s*(.-)%s*$")
            UI:RefreshStatus()
        end))
        e:SetPoint("LEFT", label, "RIGHT", 10, 4)
        local ok = c2:CreateTexture(nil, "OVERLAY")
        ok:SetSize(18, 18)
        ok:SetPoint("LEFT", e, "RIGHT", 6, 0)
        self.frame.webhookChecks[i] = ok
    end

    local c3 = StepCard(p, "3", "Run the Dink helper on your PC", 112, width)
    c3:SetPoint("TOPLEFT", c2, "BOTTOMLEFT", 0, -8)
    c3.body:SetText("WoW addons can't reach the internet, so a small free helper app sits in your system tray and posts the alerts. "
        .. "Download DinkHelper.exe here (click the box, Ctrl+C to copy, paste in your browser):")
    local link = W.EditLine(c3, width - 70, function() return ns.HELPER_URL end, nil)
    link:SetPoint("TOPLEFT", c3.body, "BOTTOMLEFT", 4, -8)
    link:SetScript("OnTextChanged", function(self, user) if user then self:SetText(ns.HELPER_URL); self:HighlightText() end end)
    link:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

    local c4 = StepCard(p, "4", "Save, then send a test", 74, width)
    c4:SetPoint("TOPLEFT", c3, "BOTTOMLEFT", 0, -8)
    c4.body:SetText("Click |cffffd100Save & Reload|r (bottom right) so the helper can read your webhook, then |cffffd100Send test alert|r. "
        .. "It should show up in Discord within a few seconds.")
end

---------------------------------------------------------------- Alerts tab
local LIST_W, ROW_H = 214, 30

function UI:BuildAlerts(p)
    local list = W.Box(p, LIST_W, 10)
    list:SetPoint("TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMLEFT", 0, 0)
    self.rows = {}
    for i, n in ipairs(ns.NOTIFIERS) do
        local r = CreateFrame("Button", nil, list)
        r:SetSize(LIST_W - 12, ROW_H)
        r:SetPoint("TOPLEFT", 6, -6 - (i - 1) * ROW_H)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(22, 22)
        r.icon:SetPoint("LEFT", 4, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        W.SetFirstTexture(r.icon, n.icons)
        r.name = W.Text(r, "GameFontHighlight", 120)
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.name:SetText(n.name)
        r.state = W.Text(r, "GameFontHighlightSmall", 40, "RIGHT")
        r.state:SetPoint("RIGHT", -6, 0)
        r.sel = r:CreateTexture(nil, "BACKGROUND")
        r.sel:SetAllPoints()
        r.sel:SetColorTexture(1, 0.82, 0, 0.18)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r:SetScript("OnClick", function() UI:SelectNotifier(n.key) end)
        self.rows[n.key] = r
    end

    local sf = CreateFrame("ScrollFrame", "DinkForDiscordDetailScroll", p, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", list, "TOPRIGHT", 12, -2)
    sf:SetPoint("BOTTOMRIGHT", -24, 2)
    self.detailScroll = sf
    self.details = {}
    self:SelectNotifier(ns.NOTIFIERS[1].key)
end

function UI:RefreshList()
    if not self.rows then return end
    for key, r in pairs(self.rows) do
        local s = ns.db.notifiers[key]
        r.state:SetText(s.enabled and W.Color("On", W.GREEN) or W.Color("Off", W.GREY))
        r.name:SetTextColor(s.enabled and 1 or 0.6, s.enabled and 1 or 0.6, s.enabled and 1 or 0.6)
        r.sel:SetShown(key == self.selected)
    end
end

function UI:SelectNotifier(key)
    self.selected = key
    if not self.details[key] then self.details[key] = self:BuildDetail(ns.NOTIFIER_BY_KEY[key]) end
    for k, d in pairs(self.details) do d:SetShown(k == key) end
    self.detailScroll:SetScrollChild(self.details[key])
    self.detailScroll:SetVerticalScroll(0)
    self.details[key]:Refresh()
    self:RefreshList()
end

function UI:BuildDetail(n)
    local width = FW - LIST_W - 80
    local d = CreateFrame("Frame", nil, self.detailScroll)
    d:SetWidth(width)
    local s = ns.db.notifiers[n.key]
    local widgets = {}
    local y = -4
    local function place(widget, height, indent)
        widget:SetPoint("TOPLEFT", indent or 0, y)
        y = y - height
        if widget.Refresh then widgets[#widgets + 1] = widget end
        return widget
    end

    local icon = W.SlotIcon(d, 36)
    icon:SetPoint("TOPLEFT", 4, y - 2)
    W.SetFirstTexture(icon.icon, n.icons)
    local title = W.Text(d, "GameFontNormalLarge", width - 60)
    title:SetPoint("TOPLEFT", 52, y)
    title:SetText(n.name)
    local desc = W.Text(d, "GameFontHighlightSmall", width - 60)
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetTextColor(0.8, 0.8, 0.8)
    desc:SetText(n.desc)
    y = y - math.max(46, 26 + desc:GetStringHeight()) - 6

    place(W.Check(d, "Send this alert", function() return s.enabled end, function(v) s.enabled = v; UI:RefreshList() end), 26)
    place(W.Check(d, "Attach a screenshot", function() return s.screenshot end, function(v) s.screenshot = v end), 32)

    if n.options and #n.options > 0 then
        place(W.Header(d, "Settings", width), 18)
        for _, opt in ipairs(n.options) do
            local get = function() return s[opt.key] end
            local set = function(v) s[opt.key] = v end
            if opt.type == "check" then
                place(W.Check(d, opt.label, get, set, nil, width - 40), 26)
            elseif opt.type == "number" or opt.type == "gold" then
                place(W.Stepper(d, opt.label, opt, get, set, width - 10), 28, 4)
            elseif opt.type == "quality" then
                place(W.QualityPicker(d, opt.label, get, set, width - 10), 28, 4)
            elseif opt.type == "text" then
                local label = W.Text(d, "GameFontHighlight", width)
                label:SetText(opt.label)
                place(label, 18, 4)
                place(W.EditLine(d, width - 20, get, set), 28, 10)
            elseif opt.type == "lines" then
                local label = W.Text(d, "GameFontHighlight", width)
                label:SetText(opt.label)
                place(label, 18, 4)
                place(W.EditArea(d, width - 10, 64, get, set), 70, 4)
            end
        end
        y = y - 6
    end

    place(W.Header(d, "Message", width), 18)
    place(W.EditArea(d, width - 10, 58, function() return s.template end, function(v) s.template = v end), 62, 4)
    local vars = W.Text(d, "GameFontHighlightSmall", width - 10)
    vars:SetTextColor(0.7, 0.7, 0.7)
    vars:SetText("You can use: " .. ns.COMMON_VARS .. (n.vars ~= "" and (", " .. n.vars) or ""))
    place(vars, vars:GetStringHeight() + 10, 4)

    place(W.Header(d, "Webhook for this alert only (optional)", width), 18)
    local hookNote = W.Text(d, "GameFontHighlightSmall", width - 10)
    hookNote:SetTextColor(0.7, 0.7, 0.7)
    hookNote:SetText("Leave empty to use your main webhooks. Needs Save & Reload.")
    place(hookNote, 16, 4)
    place(W.EditLine(d, width - 20, function() return s.webhook end, function(v) s.webhook = v:match("^%s*(.-)%s*$"); UI:RefreshStatus() end), 32, 10)

    local test = W.Button(d, 130, 22, "Send test", function() ns.SendTest(n.key) end)
    place(test, 26, 4)
    local reset = W.Button(d, 130, 22, "Reset message", function()
        s.template = n.template
        d:Refresh()
    end)
    reset:SetPoint("LEFT", test, "RIGHT", 6, 0)

    d:SetHeight(-y + 10)
    function d:Refresh() for _, w in ipairs(widgets) do w:Refresh() end end
    return d
end

---------------------------------------------------------------- Screenshots & delivery tab
function UI:BuildDelivery(p)
    local g = ns.db.general
    local width = FW - 80
    local y = 0
    local function check(label, key, desc, onSet)
        local cb = Track(W.Check(p, label, function() return g[key] end, function(v)
            g[key] = v
            if onSet then onSet(v) end
            UI:RefreshStatus()
        end, desc, width))
        cb:SetPoint("TOPLEFT", 0, y)
        y = y - cb.height - 8
    end
    check("Send alerts within seconds", "live",
        "For each alert the addon takes one extra screenshot with a small data code in the corner. The helper reads it, posts the alert and deletes that screenshot. Turn off to post only when you /reload, log out or quit.")
    check("Compact Discord posts", "compact",
        "One line of text with a small screenshot on the right, instead of a big card. Click the picture in Discord to see it full size.")
    check("Use the best screenshot quality", "highQuality",
        "Screenshot quality is raised for a moment while an alert is captured, then put back.")
    check("Hide chat windows in screenshots", "hideChat",
        "Keeps whispers and guild chat out of the pictures posted to Discord.")
    check("Keep alert screenshots in my Screenshots folder", "keepShots",
        "Turn off to have the helper delete them after posting. Needs Save & Reload.")
    check("Print a line in chat when an alert is sent", "chatConfirm")
    check("Show the minimap button", "minimap", nil, function() UI:UpdateMinimapButton() end)

    local label = W.Header(p, "Link items and quests to", width)
    label:SetPoint("TOPLEFT", 4, y - 4)
    local e = Track(W.EditLine(p, 420, function() return g.linkBase end, function(v) g.linkBase = v end))
    e:SetPoint("TOPLEFT", 10, y - 24)
    y = y - 62

    local clear = W.Button(p, 150, 22, "Clear history", function()
        wipe(ns.db.history)
        UI:RefreshHistory()
        ns.Print("History cleared.")
    end)
    clear:SetPoint("TOPLEFT", 4, y)
    local reset = W.Button(p, 150, 22, "Reset all settings", function() StaticPopup_Show("DINKFORDISCORD_RESET") end)
    reset:SetPoint("LEFT", clear, "RIGHT", 8, 0)
end

StaticPopupDialogs["DINKFORDISCORD_RESET"] = {
    text = "Reset all Dink For Discord settings? Your webhooks are kept.",
    button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function()
        local hooks = ns.db.webhooks
        wipe(DinkForDiscordDB)
        DinkForDiscordDB.webhooks = hooks
        DinkForDiscordDB.setupSeen = true
        ReloadUI()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

---------------------------------------------------------------- History tab
local HIST_ROW = 50

function UI:BuildHistory(p)
    local sf = CreateFrame("ScrollFrame", "DinkForDiscordHistoryScroll", p, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", -24, 0)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(FW - 70, 10)
    sf:SetScrollChild(child)
    self.histChild, self.histRows = child, {}
    self.histEmpty = W.Text(p, "GameFontDisable", FW - 80, "CENTER")
    self.histEmpty:SetPoint("TOP", 0, -60)
    self.histEmpty:SetText("No alerts yet. Use |cffffd100Send test alert|r to try one.")
end

function UI:OnHistoryChanged()
    if self.frame and self.frame:IsShown() and self.tab == "history" then self:RefreshHistory() end
end

function UI:RefreshHistory()
    if not self.histChild then return end
    local hist = ns.db.history
    local width = FW - 70
    for i, h in ipairs(hist) do
        local r = self.histRows[i]
        if not r then
            r = W.Box(self.histChild, width, HIST_ROW - 4)
            r:SetPoint("TOPLEFT", 0, -(i - 1) * HIST_ROW)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(30, 30)
            r.icon:SetPoint("LEFT", 10, 0)
            r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            r.title = W.Text(r, "GameFontNormal", width - 200)
            r.title:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, 2)
            r.time = W.Text(r, "GameFontDisableSmall", 140, "RIGHT")
            r.time:SetPoint("TOPRIGHT", -10, -8)
            r.msg = W.Text(r, "GameFontHighlightSmall", width - 70)
            r.msg:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -3)
            if r.msg.SetMaxLines then r.msg:SetMaxLines(1) end
            self.histRows[i] = r
        end
        local n = ns.NOTIFIER_BY_KEY[h.t]
        W.SetFirstTexture(r.icon, n and n.icons or { ns.ICON })
        r.title:SetText(h.title or h.t)
        r.time:SetText(date("%b %d  %H:%M", h.ts or time()))
        r.msg:SetText((tostring(h.msg or ""):gsub("\n", "  ")))
        r:Show()
    end
    for i = #hist + 1, #self.histRows do self.histRows[i]:Hide() end
    self.histChild:SetHeight(math.max(10, #hist * HIST_ROW))
    self.histEmpty:SetShown(#hist == 0)
end

---------------------------------------------------------------- minimap button
function UI:BuildMinimapButton()
    if self.minimap or not Minimap then return end
    local b = CreateFrame("Button", "DinkForDiscordMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    bg:SetTexture(ns.ICON)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local function place()
        local a = math.rad(ns.db.general.minimapAngle or 200)
        local r = (Minimap:GetWidth() / 2) + 10
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
    end

    b:SetScript("OnDragStart", function(s)
        s:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local sc = Minimap:GetEffectiveScale()
            local atan2 = math.atan2 or atan2
            ns.db.general.minimapAngle = math.deg(atan2(py / sc - my, px / sc - mx))
            place()
        end)
    end)
    b:SetScript("OnDragStop", function(s) s:SetScript("OnUpdate", nil) end)
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then UI:Show("history") else UI:Toggle() end
    end)
    b:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:AddLine(ns.TITLE)
        if ns.HasWebhook() then
            GameTooltip:AddLine(ns.db.general.live and "Connected - live alerts" or "Connected - alerts post on reload/logout", 0.3, 0.9, 0.4)
        else
            GameTooltip:AddLine("Not connected to Discord yet", 1, 0.35, 0.35)
        end
        GameTooltip:AddLine("Left-click: settings", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Right-click: recent alerts", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Drag: move button", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.minimap = b
    place()
    self:UpdateMinimapButton()
end

function UI:UpdateMinimapButton()
    if self.minimap then self.minimap:SetShown(ns.db.general.minimap) end
end
