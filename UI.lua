----------------------------------------------------------------------
-- ArmorySnap  –  UI.lua
-- Browse frame with paper-doll gear view, scan status, group checkbox
----------------------------------------------------------------------
local AS = _G.ArmorySnap

----------------------------------------------------------------------
-- Layout constants
----------------------------------------------------------------------
local SLOT_SIZE     = 37
local SLOT_SPACING  = 4
local ICON_BORDER   = 2

local LEFT_SLOTS    = { 1, 2, 3, 15, 5, 4, 19, 9 }
local RIGHT_SLOTS   = { 10, 6, 7, 8, 11, 12, 13, 14 }
local BOT_SLOTS     = { 16, 17, 18 }

local LIST_WIDTH    = 180
local DOLL_WIDTH    = 330
local FRAME_HEIGHT  = 480
local FRAME_WIDTH   = LIST_WIDTH + DOLL_WIDTH + 30

local CLASS_COLORS = RAID_CLASS_COLORS or {
    WARRIOR     = { r=0.78, g=0.61, b=0.43 },
    PALADIN     = { r=0.96, g=0.55, b=0.73 },
    HUNTER      = { r=0.67, g=0.83, b=0.45 },
    ROGUE       = { r=1.00, g=0.96, b=0.41 },
    PRIEST      = { r=1.00, g=1.00, b=1.00 },
    SHAMAN      = { r=0.00, g=0.44, b=0.87 },
    MAGE        = { r=0.25, g=0.78, b=0.92 },
    WARLOCK     = { r=0.53, g=0.53, b=0.93 },
    DRUID       = { r=1.00, g=0.49, b=0.04 },
}

local QUALITY_COLORS = {
    [0] = { r=0.62, g=0.62, b=0.62 },
    [1] = { r=1.00, g=1.00, b=1.00 },
    [2] = { r=0.12, g=1.00, b=0.00 },
    [3] = { r=0.00, g=0.44, b=0.87 },
    [4] = { r=0.64, g=0.21, b=0.93 },
    [5] = { r=1.00, g=0.50, b=0.00 },
}

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local browseFrame
local memberButtons   = {}
local slotButtons     = {}
local charNameText, charDetailText, charGuildText, summaryLabel
local snapshotDropdown
local memberScrollChild
local scanStatusBar, scanStatusText, scanStatusPct
local groupCheckbox

local selectedSnapshotKey = nil
local selectedMemberName  = nil

----------------------------------------------------------------------
-- Quality from link
----------------------------------------------------------------------
local function GetQualityFromLink(link)
    if not link then return 1 end
    local _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, q = GetItemInfo(link)
    if q then return q end
    local hex = link:match("|c(%x%x%x%x%x%x%x%x)")
    if hex then
        if hex == "ff9d9d9d" then return 0 end
        if hex == "ffffffff" then return 1 end
        if hex == "ff1eff00" then return 2 end
        if hex == "ff0070dd" then return 3 end
        if hex == "ffa335ee" then return 4 end
        if hex == "ffff8000" then return 5 end
    end
    return 1
end

----------------------------------------------------------------------
-- Create a gear slot button
----------------------------------------------------------------------
local function CreateSlotButton(parent, slotId)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(SLOT_SIZE, SLOT_SIZE)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(AS.EMPTY_SLOT_TEXTURES[slotId]
                  or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest")
    btn.bgTex = bg

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", ICON_BORDER, -ICON_BORDER)
    icon:SetPoint("BOTTOMRIGHT", -ICON_BORDER, ICON_BORDER)
    icon:Hide()
    btn.iconTex = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetAlpha(0.8)
    border:Hide()
    btn.borderTex = border

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")

    btn.slotId    = slotId
    btn.slotLabel = AS.SLOT_INFO[slotId] and AS.SLOT_INFO[slotId].label or "Slot"
    btn.itemLink  = nil

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemLink then
            GameTooltip:SetHyperlink(self.itemLink)
        else
            GameTooltip:AddLine(self.slotLabel, 0.5, 0.5, 0.5)
            GameTooltip:AddLine("Empty", 0.4, 0.4, 0.4)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:RegisterForClicks("LeftButtonUp")
    btn:SetScript("OnClick", function(self)
        if IsShiftKeyDown() and self.itemLink and ChatEdit_GetActiveWindow() then
            ChatEdit_InsertLink(self.itemLink)
        end
    end)

    return btn
end

----------------------------------------------------------------------
-- Set slot item or empty
----------------------------------------------------------------------
local function SetSlotItem(btn, gearData)
    if gearData and gearData.link then
        btn.itemLink = gearData.link
        btn.iconTex:SetTexture(gearData.icon
            or "Interface\\Icons\\INV_Misc_QuestionMark")
        btn.iconTex:Show()
        btn.bgTex:Hide()
        local q  = GetQualityFromLink(gearData.link)
        local qc = QUALITY_COLORS[q]
        if qc and q >= 2 then
            btn.borderTex:SetVertexColor(qc.r, qc.g, qc.b)
            btn.borderTex:Show()
        else
            btn.borderTex:Hide()
        end
    else
        btn.itemLink = nil
        btn.iconTex:Hide()
        btn.bgTex:Show()
        btn.borderTex:Hide()
    end
end

----------------------------------------------------------------------
-- BUILD THE MAIN FRAME
----------------------------------------------------------------------
local function CreateBrowseFrame()
    if browseFrame then return end

    local f = CreateFrame("Frame", "ArmorySnapBrowseFrame", UIParent,
                          "BasicFrameTemplateWithInset")
    f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "ArmorySnapBrowseFrame")
    f.TitleText:SetText("ArmorySnap")

    --==============================================================
    -- SCAN STATUS BAR
    --==============================================================
    local statusBar = CreateFrame("StatusBar", nil, f)
    statusBar:SetPoint("TOPLEFT", f.InsetBg or f, "TOPLEFT", 8, -6)
    statusBar:SetPoint("TOPRIGHT", f.InsetBg or f, "TOPRIGHT", -8, -6)
    statusBar:SetHeight(18)
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(0)
    statusBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    statusBar:SetStatusBarColor(0.26, 0.8, 0.26, 0.7)
    scanStatusBar = statusBar

    local statusBg = statusBar:CreateTexture(nil, "BACKGROUND")
    statusBg:SetAllPoints()
    statusBg:SetColorTexture(0.1, 0.1, 0.1, 0.6)

    local stxt = statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stxt:SetPoint("LEFT", 6, 0)
    stxt:SetText("Scanner idle")
    scanStatusText = stxt

    local spct = statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spct:SetPoint("RIGHT", -6, 0)
    spct:SetText("")
    scanStatusPct = spct

    --==============================================================
    -- GROUP CHECKBOX
    --==============================================================
    local cb = CreateFrame("CheckButton", "ASGroupCheckbox", f,
                           "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", statusBar, "BOTTOMLEFT", -2, -2)
    cb:SetSize(24, 24)
    cb.text = _G[cb:GetName() .. "Text"] or cb.Text
    if cb.text then
        cb.text:SetText("Also scan in party / group")
        cb.text:SetFontObject("GameFontNormalSmall")
    end
    cb:SetChecked(AS.db and AS.db.options
                  and AS.db.options.scanGroup or false)
    cb:SetScript("OnClick", function(self)
        if AS.db and AS.db.options then
            AS.db.options.scanGroup = self:GetChecked() and true or false
            if AS.db.options.scanGroup then
                AS.Print("Group scanning |cff00ff00ENABLED|r")
            else
                AS.Print("Group scanning |cffff4444DISABLED|r")
            end
        end
    end)
    groupCheckbox = cb

    --==============================================================
    -- LEFT PANEL: Snapshot dropdown + member list
    --==============================================================
    local leftTop = -52
    local leftPanel = CreateFrame("Frame", nil, f)
    leftPanel:SetPoint("TOPLEFT", f.InsetBg or f, "TOPLEFT", 8, leftTop)
    leftPanel:SetSize(LIST_WIDTH, FRAME_HEIGHT - 90)

    local snapLabel = leftPanel:CreateFontString(nil, "OVERLAY",
                                                  "GameFontNormalSmall")
    snapLabel:SetPoint("TOPLEFT", 0, 0)
    snapLabel:SetText("Snapshot:")

    local dd = CreateFrame("Frame", "ASSnapDD", leftPanel,
                           "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", snapLabel, "BOTTOMLEFT", -16, -2)
    snapshotDropdown = dd
    UIDropDownMenu_SetWidth(dd, LIST_WIDTH - 30)

    local function DDInit(self, level)
        local keys = AS.GetSnapshotKeys()
        for _, key in ipairs(keys) do
            local info = UIDropDownMenu_CreateInfo()
            info.text     = key
            info.value    = key
            info.checked  = (key == selectedSnapshotKey)
            info.func = function(self)
                selectedSnapshotKey = self.value
                selectedMemberName  = nil
                UIDropDownMenu_SetText(dd, self.value)
                CloseDropDownMenus()
                AS.RefreshMemberList()
                AS.ClearPaperDoll()
            end
            UIDropDownMenu_AddButton(info, level)
        end
        if #keys == 0 then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "(No snapshots)"
            info.disabled = true
            info.notCheckable = true
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_Initialize(dd, DDInit)
    UIDropDownMenu_SetText(dd, "Select snapshot …")

    local mLabel = leftPanel:CreateFontString(nil, "OVERLAY",
                                               "GameFontNormalSmall")
    mLabel:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 16, -6)
    mLabel:SetText("Raid Members:")

    local sf = CreateFrame("ScrollFrame", "ASMemberScroll", leftPanel,
                           "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", mLabel, "BOTTOMLEFT", 0, -4)
    sf:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -22, 4)

    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(LIST_WIDTH - 28, 1)
    sf:SetScrollChild(child)
    memberScrollChild = child

    --==============================================================
    -- RIGHT PANEL: Character info + paper doll
    --==============================================================
    local rightPanel = CreateFrame("Frame", nil, f)
    rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 10, 0)
    rightPanel:SetSize(DOLL_WIDTH, FRAME_HEIGHT - 90)

    charNameText = rightPanel:CreateFontString(nil, "OVERLAY",
                                                "GameFontNormalLarge")
    charNameText:SetPoint("TOP", 0, -4)

    charDetailText = rightPanel:CreateFontString(nil, "OVERLAY",
                                                  "GameFontHighlightSmall")
    charDetailText:SetPoint("TOP", charNameText, "BOTTOM", 0, -2)

    charGuildText = rightPanel:CreateFontString(nil, "OVERLAY",
                                                 "GameFontNormalSmall")
    charGuildText:SetPoint("TOP", charDetailText, "BOTTOM", 0, -1)
    charGuildText:SetTextColor(0.25, 1.0, 0.25)

    -- Paper doll container
    local dollFrame = CreateFrame("Frame", nil, rightPanel)
    dollFrame:SetPoint("TOP", charGuildText, "BOTTOM", 0, -10)
    dollFrame:SetSize(DOLL_WIDTH, 340)

    local dollBg = dollFrame:CreateTexture(nil, "BACKGROUND")
    dollBg:SetAllPoints()
    dollBg:SetColorTexture(0, 0, 0, 0.15)

    -- Left column
    for i, sid in ipairs(LEFT_SLOTS) do
        local btn = CreateSlotButton(dollFrame, sid)
        btn:SetPoint("TOPLEFT", 6,
                     -((i - 1) * (SLOT_SIZE + SLOT_SPACING) + 4))
        slotButtons[sid] = btn
    end

    -- Right column
    local rx = DOLL_WIDTH - SLOT_SIZE - 6
    for i, sid in ipairs(RIGHT_SLOTS) do
        local btn = CreateSlotButton(dollFrame, sid)
        btn:SetPoint("TOPLEFT", rx,
                     -((i - 1) * (SLOT_SIZE + SLOT_SPACING) + 4))
        slotButtons[sid] = btn
    end

    -- Bottom row (centered)
    local bw = #BOT_SLOTS * SLOT_SIZE + (#BOT_SLOTS - 1) * SLOT_SPACING
    local bx = (DOLL_WIDTH - bw) / 2
    local by = -(#LEFT_SLOTS * (SLOT_SIZE + SLOT_SPACING) + 8)
    for i, sid in ipairs(BOT_SLOTS) do
        local btn = CreateSlotButton(dollFrame, sid)
        btn:SetPoint("TOPLEFT", bx + (i - 1) * (SLOT_SIZE + SLOT_SPACING), by)
        slotButtons[sid] = btn
    end

    -- Centre placeholder
    local sil = dollFrame:CreateFontString(nil, "ARTWORK",
                                            "GameFontDisableLarge")
    sil:SetPoint("CENTER", 0, -15)
    sil:SetText("[ Character ]")
    sil:SetAlpha(0.2)

    -- Summary label
    summaryLabel = rightPanel:CreateFontString(nil, "OVERLAY",
                                                "GameFontNormalSmall")
    summaryLabel:SetPoint("BOTTOMLEFT", 4, 4)
    summaryLabel:SetWidth(DOLL_WIDTH - 8)
    summaryLabel:SetJustifyH("LEFT")

    browseFrame = f
    f:Hide()
end

----------------------------------------------------------------------
-- Status bar refresh
----------------------------------------------------------------------
local function UpdateScanStatus()
    if not browseFrame or not browseFrame:IsShown() then return end
    local s = AS.session
    if s.active then
        local total = math.max(s.totalInRaid, 1)
        local pct   = s.totalCaptured / total
        scanStatusBar:SetValue(pct)
        scanStatusText:SetText("Scanning: " .. (s.snapshotKey or ""))
        scanStatusPct:SetText(s.totalCaptured .. " / " .. s.totalInRaid)
        if pct >= 1 then
            scanStatusBar:SetStatusBarColor(0.26, 0.8, 0.26, 0.7)
        else
            scanStatusBar:SetStatusBarColor(0.9, 0.7, 0.0, 0.7)
        end
    else
        scanStatusBar:SetValue(0)
        scanStatusText:SetText("Scanner idle")
        scanStatusPct:SetText("")
        scanStatusBar:SetStatusBarColor(0.4, 0.4, 0.4, 0.5)
    end
end

----------------------------------------------------------------------
-- Refresh member list
----------------------------------------------------------------------
function AS.RefreshMemberList()
    for _, btn in ipairs(memberButtons) do btn:Hide(); btn:SetParent(nil) end
    wipe(memberButtons)

    if not selectedSnapshotKey then return end
    local names = AS.GetMemberNames(selectedSnapshotKey)
    local snap  = AS.db.snapshots[selectedSnapshotKey]
    if not snap then return end

    local yOff, btnH = 0, 18
    for _, name in ipairs(names) do
        local member = snap.members[name]
        local btn = CreateFrame("Button", nil, memberScrollChild)
        btn:SetSize(LIST_WIDTH - 30, btnH)
        btn:SetPoint("TOPLEFT", 0, -yOff)

        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.1)

        local sel = btn:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints()
        sel:SetColorTexture(1, 1, 1, 0.15)
        sel:Hide()
        btn.selTex = sel

        local cc = CLASS_COLORS[member.class] or { r=1, g=1, b=1 }
        local txt = btn:CreateFontString(nil, "OVERLAY",
                                          "GameFontHighlightSmall")
        txt:SetPoint("LEFT", 4, 0)
        txt:SetText(name)
        txt:SetTextColor(cc.r, cc.g, cc.b)

        local gc = 0
        for _ in pairs(member.gear) do gc = gc + 1 end
        local ct = btn:CreateFontString(nil, "OVERLAY",
                                         "GameFontDisableSmall")
        ct:SetPoint("RIGHT", -4, 0)
        ct:SetText(gc .. " items")

        btn.memberName = name
        btn:SetScript("OnClick", function(self)
            selectedMemberName = self.memberName
            AS.RefreshPaperDoll()
            for _, b in ipairs(memberButtons) do
                if b.selTex then
                    b.selTex[b.memberName == selectedMemberName
                             and "Show" or "Hide"](b.selTex)
                end
            end
        end)

        table.insert(memberButtons, btn)
        yOff = yOff + btnH + 1
    end
    memberScrollChild:SetHeight(math.max(1, yOff))
end

----------------------------------------------------------------------
-- Clear / Refresh paper doll
----------------------------------------------------------------------
function AS.ClearPaperDoll()
    charNameText:SetText("")
    charDetailText:SetText("")
    charGuildText:SetText("")
    if summaryLabel then summaryLabel:SetText("") end
    for _, btn in pairs(slotButtons) do SetSlotItem(btn, nil) end
end

function AS.RefreshPaperDoll()
    AS.ClearPaperDoll()
    if not selectedSnapshotKey or not selectedMemberName then return end
    local snap   = AS.db.snapshots[selectedSnapshotKey]
    if not snap then return end
    local member = snap.members[selectedMemberName]
    if not member then return end

    local cc = CLASS_COLORS[member.class] or { r=1, g=1, b=1 }
    charNameText:SetText(member.name)
    charNameText:SetTextColor(cc.r, cc.g, cc.b)
    charDetailText:SetText("Level " .. (member.level or "?") .. " "
                           .. (member.race or "") .. " "
                           .. (member.class or ""))
    charGuildText:SetText(member.guild ~= ""
                          and ("<" .. member.guild .. ">") or "")

    local enchants, gems, items = 0, 0, 0
    for sid, btn in pairs(slotButtons) do
        local gd = member.gear[sid]
        SetSlotItem(btn, gd)
        if gd and gd.link then
            items = items + 1
            local p = AS.ParseItemLink(gd.link)
            if p then
                if p.enchantId > 0 then enchants = enchants + 1 end
                if p.gem1      > 0 then gems = gems + 1 end
                if p.gem2      > 0 then gems = gems + 1 end
                if p.gem3      > 0 then gems = gems + 1 end
            end
        end
    end

    local s = items .. " items"
    if enchants > 0 or gems > 0 then
        s = s .. "  |  "
        if enchants > 0 then
            s = s .. "|cff00ff00" .. enchants .. " enchant"
                  .. (enchants ~= 1 and "s" or "") .. "|r"
        end
        if enchants > 0 and gems > 0 then s = s .. ", " end
        if gems > 0 then
            s = s .. "|cffff6600" .. gems .. " gem"
                  .. (gems ~= 1 and "s" or "") .. "|r"
        end
    end
    if summaryLabel then summaryLabel:SetText(s) end
end

----------------------------------------------------------------------
-- Refresh snapshot dropdown
----------------------------------------------------------------------
function AS.RefreshSnapshotList()
    if not browseFrame or not browseFrame:IsShown() then return end
    UIDropDownMenu_Initialize(snapshotDropdown, function(self, level)
        local keys = AS.GetSnapshotKeys()
        for _, key in ipairs(keys) do
            local info = UIDropDownMenu_CreateInfo()
            info.text    = key
            info.value   = key
            info.checked = (key == selectedSnapshotKey)
            info.func = function(self)
                selectedSnapshotKey = self.value
                selectedMemberName  = nil
                UIDropDownMenu_SetText(snapshotDropdown, self.value)
                CloseDropDownMenus()
                AS.RefreshMemberList()
                AS.ClearPaperDoll()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    if selectedSnapshotKey then
        UIDropDownMenu_SetText(snapshotDropdown, selectedSnapshotKey)
    end
end

----------------------------------------------------------------------
-- Live-refresh callback
----------------------------------------------------------------------
function AS.OnMemberCaptured()
    if not browseFrame or not browseFrame:IsShown() then return end
    local s = AS.session
    if s.snapshotKey and selectedSnapshotKey == s.snapshotKey then
        AS.RefreshMemberList()
    end
end

----------------------------------------------------------------------
-- Checkbox sync
----------------------------------------------------------------------
function AS.UpdateGroupCheckbox()
    if groupCheckbox and AS.db and AS.db.options then
        groupCheckbox:SetChecked(AS.db.options.scanGroup)
    end
end

----------------------------------------------------------------------
-- Toggle browse frame
----------------------------------------------------------------------
function AS.ToggleBrowseFrame()
    CreateBrowseFrame()
    if browseFrame:IsShown() then
        browseFrame:Hide()
    else
        if groupCheckbox and AS.db and AS.db.options then
            groupCheckbox:SetChecked(AS.db.options.scanGroup)
        end
        browseFrame:Show()
        if not selectedSnapshotKey then
            if AS.session.snapshotKey then
                selectedSnapshotKey = AS.session.snapshotKey
            else
                local keys = AS.GetSnapshotKeys()
                if #keys > 0 then selectedSnapshotKey = keys[1] end
            end
            if selectedSnapshotKey then
                UIDropDownMenu_SetText(snapshotDropdown, selectedSnapshotKey)
            end
        end
        AS.RefreshMemberList()
        UpdateScanStatus()
    end
end

----------------------------------------------------------------------
-- Minimap button
----------------------------------------------------------------------
local function CreateMinimapButton()
    local btn = CreateFrame("Button", "ASMinimapButton", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetHighlightTexture(
        "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\INV_Chest_Chain_09")

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("CENTER")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local angle = 220
    local function UpdatePos()
        local r = math.rad(angle)
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER",
                     math.cos(r) * 80, math.sin(r) * 80)
    end
    UpdatePos()

    btn:SetScript("OnDragStart", function(self) self.dragging = true end)
    btn:SetScript("OnDragStop",  function(self) self.dragging = false end)
    btn:SetScript("OnUpdate", function(self)
        if not self.dragging then return end
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local s = Minimap:GetEffectiveScale()
        angle = math.deg(math.atan2(cy/s - my, cx/s - mx))
        UpdatePos()
    end)

    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            AS.ToggleBrowseFrame()
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("ArmorySnap")
        local s = AS.session
        if s.active then
            GameTooltip:AddLine(s.totalCaptured .. "/" .. s.totalInRaid
                                .. " scanned", 0.6, 1, 0.6)
        else
            GameTooltip:AddLine("Idle", 0.6, 0.6, 0.6)
        end
        GameTooltip:AddLine("|cffffffffClick|r to browse", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

----------------------------------------------------------------------
-- Startup
----------------------------------------------------------------------
local function OnLoad()
    CreateMinimapButton()
    C_Timer.NewTicker(2, UpdateScanStatus)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function() OnLoad() end)
