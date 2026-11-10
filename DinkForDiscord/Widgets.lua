local _, ns = ...

-- Small building blocks for the window. Everything uses Blizzard templates and textures
-- so it matches the default UI (same approach as Paladin Leveling Guide).

local W = {}
ns.W = W

W.GOLD = { 1.00, 0.82, 0.00 }
W.GREY = { 0.62, 0.62, 0.62 }
W.GREEN = { 0.30, 0.90, 0.40 }
W.RED = { 1.00, 0.35, 0.35 }

function W.Hex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end
function W.Color(text, c) return W.Hex(c) .. text .. "|r" end

function W.Text(parent, font, width, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    if width then fs:SetWidth(width) end
    fs:SetJustifyH(justify or "LEFT")
    fs:SetJustifyV("TOP")
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    return fs
end

function W.FileExists(path)
    if GetFileIDFromPath then
        local ok, id = pcall(GetFileIDFromPath, path)
        return ok and id ~= nil
    end
    return true
end

function W.SetFirstTexture(tex, candidates, fallback)
    for _, c in ipairs(candidates or {}) do
        if type(c) == "number" or W.FileExists(c) then tex:SetTexture(c); return true end
    end
    tex:SetTexture(fallback or "Interface\\Icons\\INV_Misc_QuestionMark")
    return false
end

function W.Button(parent, w, h, label, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h)
    b:SetText(label or "")
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

function W.Box(parent, w, h, kind)
    local b = CreateFrame(kind or "Frame", nil, parent, "BackdropTemplate")
    if w then b:SetSize(w, h) end
    b:SetBackdrop(BACKDROP)
    b:SetBackdropColor(0.04, 0.04, 0.04, 0.9)
    b:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
    return b
end

-- Icon with the standard action-slot border.
function W.SlotIcon(parent, size)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size, size)
    holder.icon = holder:CreateTexture(nil, "ARTWORK")
    holder.icon:SetAllPoints()
    holder.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if W.FileExists("Interface\\Buttons\\UI-Quickslot2") then
        holder.border = holder:CreateTexture(nil, "OVERLAY")
        holder.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        holder.border:SetSize(size * 64 / 36, size * 64 / 36)
        holder.border:SetPoint("CENTER")
    end
    return holder
end

function W.Check(parent, label, get, set, desc, width)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb.label = W.Text(cb, "GameFontHighlight", width or 420)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    cb.label:SetText(label)
    local height = 26
    if desc then
        cb.desc = W.Text(cb, "GameFontHighlightSmall", width or 420)
        cb.desc:SetPoint("TOPLEFT", cb.label, "BOTTOMLEFT", 0, -2)
        cb.desc:SetTextColor(0.7, 0.7, 0.7)
        cb.desc:SetText(desc)
        height = 26 + math.max(12, cb.desc:GetStringHeight()) + 2
    end
    cb.height = height
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    function cb:Refresh() self:SetChecked(get() and true or false) end
    cb:Refresh()
    return cb
end

local editCount = 0
function W.EditLine(parent, width, get, set)
    editCount = editCount + 1
    local e = CreateFrame("EditBox", "DinkForDiscordEdit" .. editCount, parent, "InputBoxTemplate")
    e:SetSize(width, 22)
    e:SetAutoFocus(false)
    e:SetMaxLetters(400)
    e:SetFontObject("ChatFontNormal")
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    e:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
    if set then
        e:SetScript("OnTextChanged", function(self, user) if user then set(self:GetText()) end end)
    end
    function e:Refresh() if get then self:SetText(get() or ""); self:SetCursorPosition(0) end end
    e:Refresh()
    return e
end

-- Multi-line text box inside a scroll frame.
function W.EditArea(parent, width, height, get, set)
    local box = W.Box(parent, width, height)
    editCount = editCount + 1
    local sf = CreateFrame("ScrollFrame", "DinkForDiscordArea" .. editCount, box, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 8, -6)
    sf:SetPoint("BOTTOMRIGHT", -28, 6)
    local e = CreateFrame("EditBox", nil, sf)
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    e:SetFontObject("ChatFontNormal")
    e:SetWidth(width - 40)
    e:SetMaxLetters(2000)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnTextChanged", function(self, user)
        if user and set then set(self:GetText()) end
        if ScrollingEdit_OnTextChanged then ScrollingEdit_OnTextChanged(self, sf) end
    end)
    if ScrollingEdit_OnCursorChanged then e:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged) end
    if ScrollingEdit_OnUpdate then
        e:SetScript("OnUpdate", function(self, elapsed) ScrollingEdit_OnUpdate(self, elapsed, sf) end)
    end
    sf:SetScrollChild(e)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() e:SetFocus() end)
    box.edit = e
    function box:Refresh() if get then e:SetText(get() or "") end end
    box:Refresh()
    return box
end

-- [-] value [+] number picker.
function W.Stepper(parent, label, opt, get, set, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 440, 24)
    f.label = W.Text(f, "GameFontHighlight", (width or 440) - 140)
    f.label:SetPoint("LEFT", 0, 0)
    f.label:SetText(label)
    local minus = W.Button(f, 24, 22, "-")
    minus:SetPoint("RIGHT", f, "RIGHT", -96, 0)
    local edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    edit:SetSize(56, 22)
    edit:SetPoint("LEFT", minus, "RIGHT", 8, 0)
    edit:SetAutoFocus(false)
    edit:SetNumeric(true)
    edit:SetJustifyH("CENTER")
    local plus = W.Button(f, 24, 22, "+")
    plus:SetPoint("LEFT", edit, "RIGHT", 4, 0)

    local function clamp(v)
        v = tonumber(v) or opt.default or 0
        return math.max(opt.min or 0, math.min(opt.max or 1e9, v))
    end
    local function apply(v)
        v = clamp(v)
        set(v)
        edit:SetText(tostring(v))
    end
    minus:SetScript("OnClick", function() apply((get() or 0) - (opt.step or 1)) end)
    plus:SetScript("OnClick", function() apply((get() or 0) + (opt.step or 1)) end)
    edit:SetScript("OnEnterPressed", function(self) apply(self:GetText()); self:ClearFocus() end)
    edit:SetScript("OnEditFocusLost", function(self) apply(self:GetText()) end)
    edit:SetScript("OnEscapePressed", function(self) self:SetText(tostring(get())); self:ClearFocus() end)
    function f:Refresh() edit:SetText(tostring(clamp(get()))) end
    f:Refresh()
    return f
end

-- Click to cycle through item qualities (right-click goes back).
function W.QualityPicker(parent, label, get, set, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 440, 24)
    f.label = W.Text(f, "GameFontHighlight", (width or 440) - 140)
    f.label:SetPoint("LEFT", 0, 0)
    f.label:SetText(label)
    local b = W.Button(f, 128, 22, "")
    b:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, button)
        local q = get() or 3
        if button == "RightButton" then q = q - 1 else q = q + 1 end
        if q > 5 then q = 0 elseif q < 0 then q = 5 end
        set(q)
        f:Refresh()
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Left-click: higher, right-click: lower")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    function f:Refresh() b:SetText(ns.QualityText(get() or 3) .. " +") end
    f:Refresh()
    return f
end

function W.Header(parent, text, width)
    local fs = W.Text(parent, "GameFontNormal", width)
    fs:SetText(text)
    return fs
end
