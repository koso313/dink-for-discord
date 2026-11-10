local _, ns = ...

-- A page in the game's own settings (Options > AddOns > Dink For Discord) that opens the window.

local function Build()
    local panel = CreateFrame("Frame")
    panel.name = ns.TITLE

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(ns.TITLE .. "  |cff888888v" .. tostring(ns.VERSION) .. "|r")
    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    sub:SetWidth(560)
    sub:SetJustifyH("LEFT")
    sub:SetText("Posts your deaths, level ups, loot, boss kills and more to a Discord channel, with screenshots. "
        .. "Everything is set up in the Dink For Discord window.")

    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(220, 26)
    open:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -16)
    open:SetText("Open Dink For Discord")
    open:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
        ns.UI:Show()
    end)

    local tip = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    tip:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -12)
    tip:SetText("Shortcuts: /dink to open, /dink test to send a test alert.")

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

ns.OnLogin(function() pcall(Build) end)
