----------------------------------------------------------------------
-- ArmorySnap  –  UI.lua  v1.1.0
-- Browse frame with paper-doll, talents, ElvUI theme, minimap button
----------------------------------------------------------------------
local AS = _G.ArmorySnap

----------------------------------------------------------------------
-- Layout constants  (scaled to fit weapons row comfortably)
----------------------------------------------------------------------
local SLOT_SIZE     = 36
local SLOT_SPACING  = 3
local ICON_BORDER   = 2

local LEFT_SLOTS    = { 1, 2, 3, 15, 5, 4, 19, 9 }   -- 8 slots
local RIGHT_SLOTS   = { 10, 6, 7, 8, 11, 12, 13, 14 } -- 8 slots
local BOT_SLOTS     = { 16, 17, 18 }                   -- MH, OH, Ranged

local LIST_WIDTH    = 180
local DOLL_WIDTH    = 330
local FRAME_WIDTH   = LIST_WIDTH + DOLL_WIDTH + 30
local DOLL_COL_H    = #LEFT_SLOTS * (SLOT_SIZE + SLOT_SPACING)
local DOLL_H        = DOLL_COL_H + SLOT_SIZE + 16       -- columns + gap + bot row
local TALENT_H      = 52                                 -- talent bar area
local FRAME_HEIGHT  = 28 + 18 + 26 + 24 + 28 + 22       -- title + status + checkbox row + snap label
                    + 30                                  -- dropdown
                    + DOLL_H + TALENT_H                   -- paper doll + talents
                    + 40                                  -- summary + padding
FRAME_HEIGHT = math.max(FRAME_HEIGHT, 590)               -- floor

----------------------------------------------------------------------
-- Class / quality colours
----------------------------------------------------------------------
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
-- ElvUI theme colours
----------------------------------------------------------------------
local ELVUI = {
    bgMain     = { 0.07, 0.07, 0.07, 0.92 },
    bgPanel    = { 0.05, 0.05, 0.05, 0.85 },
    border     = { 0.15, 0.15, 0.15, 1 },
    borderHl   = { 0.00, 0.44, 0.87, 0.8 },
    accent     = { 0.00, 0.44, 0.87 },
    statusBg   = { 0.08, 0.08, 0.08, 0.8 },
    statusBar  = { 0.00, 0.44, 0.87, 0.85 },
    statusDone = { 0.18, 0.70, 0.18, 0.85 },
    text       = { 0.84, 0.84, 0.84 },
    textDim    = { 0.50, 0.50, 0.50 },
    slotBg     = { 0.10, 0.10, 0.10, 0.7 },
    listHover  = { 1, 1, 1, 0.06 },
    listSelect = { 0.00, 0.44, 0.87, 0.18 },
}

----------------------------------------------------------------------
-- Frame refs
----------------------------------------------------------------------
local browseFrame
local memberButtons   = {}
local slotButtons     = {}
local charNameText, charDetailText, charGuildText, summaryLabel
local talentFrame, talentIcons, talentTexts, talentSpecText
local snapshotDropdown
local memberScrollChild
local scanStatusBar, scanStatusText, scanStatusPct, scanStatusBg
local groupCheckbox, themeCheckbox, verboseCheckbox
local dollFrame, dollBg
local elvuiOverlays = {}  -- textures / objects we restyle on theme toggle

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
-- Pixel border helper (for ElvUI style)
----------------------------------------------------------------------
local function MakePixelBorder(frame, r, g, b, a, size)
    size = size or 1
    if frame._pxBorders then
        for _, t in ipairs(frame._pxBorders) do
            t:SetColorTexture(r, g, b, a)
        end
        return
    end
    frame._pxBorders = {}
    local sides = {
        {"TOPLEFT","BOTTOMLEFT", size,0, 0,0,0,0},       -- left
        {"TOPRIGHT","BOTTOMRIGHT", size,0, 0,0,0,0},      -- right
        {"TOPLEFT","TOPRIGHT", 0,size, 0,0,0,0},          -- top
        {"BOTTOMLEFT","BOTTOMRIGHT", 0,size, 0,0,0,0},    -- bottom
    }
    for i, s in ipairs(sides) do
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(r, g, b, a)
        if i == 1 then     -- left
            t:SetPoint("TOPLEFT", -size, size)
            t:SetPoint("BOTTOMLEFT", -size, -size)
            t:SetWidth(size)
        elseif i == 2 then -- right
            t:SetPoint("TOPRIGHT", size, size)
            t:SetPoint("BOTTOMRIGHT", size, -size)
            t:SetWidth(size)
        elseif i == 3 then -- top
            t:SetPoint("TOPLEFT", -size, size)
            t:SetPoint("TOPRIGHT", size, size)
            t:SetHeight(size)
        elseif i == 4 then -- bottom
            t:SetPoint("BOTTOMLEFT", -size, -size)
            t:SetPoint("BOTTOMRIGHT", size, -size)
            t:SetHeight(size)
        end
        table.insert(frame._pxBorders, t)
    end
end

----------------------------------------------------------------------
-- Create a gear slot button
----------------------------------------------------------------------
local function CreateSlotButton(parent, slotId)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(SLOT_SIZE, SLOT_SIZE)

    -- Background (empty slot texture)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(AS.EMPTY_SLOT_TEXTURES[slotId]
                  or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest")
    btn.bgTex = bg

    -- ElvUI dark square background (hidden unless themed)
    local elvBg = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
    elvBg:SetAllPoints()
    elvBg:SetColorTexture(unpack(ELVUI.slotBg))
    elvBg:Hide()
    btn.elvBg = elvBg

    -- Item icon
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", ICON_BORDER, -ICON_BORDER)
    icon:SetPoint("BOTTOMRIGHT", -ICON_BORDER, ICON_BORDER)
    icon:Hide()
    btn.iconTex = icon

    -- Quality border glow
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetAlpha(0.8)
    border:Hide()
    btn.borderTex = border

    -- Highlight
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
    btn.hlTex = hl

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
        local isElv = AS.db and AS.db.options and AS.db.options.elvuiTheme
        btn.bgTex:SetShown(not isElv)
        btn.borderTex:Hide()
    end
end

----------------------------------------------------------------------
-- THEME APPLICATION
----------------------------------------------------------------------
function AS.ApplyTheme()
    if not browseFrame then return end
    local elv = AS.db and AS.db.options and AS.db.options.elvuiTheme

    if elv then
        -- Main frame
        if browseFrame.SetBackdrop then
            browseFrame:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            browseFrame:SetBackdropColor(unpack(ELVUI.bgMain))
            browseFrame:SetBackdropBorderColor(unpack(ELVUI.border))
        end

        -- Hide default Blizzard chrome textures
        if browseFrame.TitleBg       then browseFrame.TitleBg:Hide() end
        if browseFrame.TopTileStreaky then browseFrame.TopTileStreaky:Hide() end
        if browseFrame.Bg            then browseFrame.Bg:Hide() end
        if browseFrame.InsetBg       then browseFrame.InsetBg:Hide() end
        for _, region in pairs({browseFrame:GetRegions()}) do
            if region.GetDrawLayer and region:GetDrawLayer() == "BORDER" then
                region:SetAlpha(0)
            end
        end

        -- Inset region
        local inset = browseFrame.Inset
        if inset then
            for _, region in pairs({inset:GetRegions()}) do
                region:SetAlpha(0)
            end
        end

        -- Title
        browseFrame.TitleText:SetTextColor(unpack(ELVUI.text))

        -- Status bar
        if scanStatusBg then scanStatusBg:SetColorTexture(unpack(ELVUI.statusBg)) end
        if scanStatusBar then
            scanStatusBar:SetStatusBarColor(unpack(ELVUI.statusBar))
            MakePixelBorder(scanStatusBar, unpack(ELVUI.border))
        end

        -- Doll background
        if dollBg then dollBg:SetColorTexture(unpack(ELVUI.bgPanel)) end

        -- Slot buttons
        for _, btn in pairs(slotButtons) do
            btn.elvBg:Show()
            btn.bgTex:Hide()
            MakePixelBorder(btn, unpack(ELVUI.border))
            btn.hlTex:SetTexture("Interface\\Buttons\\WHITE8X8")
            btn.hlTex:SetAlpha(0.08)
        end

        -- Talent frame
        if talentFrame then
            talentFrame.bg:SetColorTexture(unpack(ELVUI.bgPanel))
            MakePixelBorder(talentFrame, unpack(ELVUI.border))
        end
    else
        -- Restore default Blizzard frame
        if browseFrame.SetBackdrop then
            browseFrame:SetBackdrop(nil)
        end
        if browseFrame.TitleBg       then browseFrame.TitleBg:Show() end
        if browseFrame.TopTileStreaky then browseFrame.TopTileStreaky:Show() end
        if browseFrame.Bg            then browseFrame.Bg:Show() end
        if browseFrame.InsetBg       then browseFrame.InsetBg:Show() end
        for _, region in pairs({browseFrame:GetRegions()}) do
            if region.GetDrawLayer and region:GetDrawLayer() == "BORDER" then
                region:SetAlpha(1)
            end
        end
        local inset = browseFrame.Inset
        if inset then
            for _, region in pairs({inset:GetRegions()}) do
                region:SetAlpha(1)
            end
        end
        browseFrame.TitleText:SetTextColor(1, 0.82, 0)

        if scanStatusBg then scanStatusBg:SetColorTexture(0.1, 0.1, 0.1, 0.6) end
        if scanStatusBar then
            scanStatusBar:SetStatusBarColor(0.26, 0.8, 0.26, 0.7)
            if scanStatusBar._pxBorders then
                for _, t in ipairs(scanStatusBar._pxBorders) do t:Hide() end
            end
        end

        if dollBg then dollBg:SetColorTexture(0, 0, 0, 0.15) end

        for _, btn in pairs(slotButtons) do
            btn.elvBg:Hide()
            if not btn.itemLink then btn.bgTex:Show() end
            if btn._pxBorders then
                for _, t in ipairs(btn._pxBorders) do t:Hide() end
            end
            btn.hlTex:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
            btn.hlTex:SetAlpha(1)
        end

        if talentFrame then
            talentFrame.bg:SetColorTexture(0, 0, 0, 0.2)
            if talentFrame._pxBorders then
                for _, t in ipairs(talentFrame._pxBorders) do t:Hide() end
            end
        end
    end

    -- Update theme checkbox
    if themeCheckbox then
        themeCheckbox:SetChecked(elv and true or false)
    end
end

----------------------------------------------------------------------
-- BUILD THE MAIN FRAME
----------------------------------------------------------------------
local function CreateBrowseFrame()
    if browseFrame then return end

    local f = CreateFrame("Frame", "ArmorySnapBrowseFrame", UIParent,
                          "BasicFrameTemplateWithInset, BackdropTemplate")
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
    statusBar:SetPoint("TOPLEFT", 10, -28)
    statusBar:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    statusBar:SetHeight(18)
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(0)
    statusBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    statusBar:SetStatusBarColor(0.26, 0.8, 0.26, 0.7)
    scanStatusBar = statusBar

    local sBg = statusBar:CreateTexture(nil, "BACKGROUND")
    sBg:SetAllPoints()
    sBg:SetColorTexture(0.1, 0.1, 0.1, 0.6)
    scanStatusBg = sBg

    scanStatusText = statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scanStatusText:SetPoint("LEFT", 6, 0)
    scanStatusText:SetText("Scanner idle")

    scanStatusPct = statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scanStatusPct:SetPoint("RIGHT", -6, 0)

    --==============================================================
    -- CHECKBOX ROW  (group + theme)
    --==============================================================
    local cbRow = CreateFrame("Frame", nil, f)
    cbRow:SetPoint("TOPLEFT", statusBar, "BOTTOMLEFT", -2, -1)
    cbRow:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    cbRow:SetHeight(24)

    -- Group checkbox
    local gcb = CreateFrame("CheckButton", "ASGroupCB", cbRow,
                            "UICheckButtonTemplate")
    gcb:SetPoint("LEFT", 0, 0)
    gcb:SetSize(22, 22)
    gcb.text = _G[gcb:GetName() .. "Text"] or gcb.Text
    if gcb.text then
        gcb.text:SetText("Scan in group")
        gcb.text:SetFontObject("GameFontNormalSmall")
    end
    gcb:SetChecked(AS.db and AS.db.options and AS.db.options.scanGroup or false)
    gcb:SetScript("OnClick", function(self)
        if AS.db and AS.db.options then
            AS.db.options.scanGroup = self:GetChecked() and true or false
        end
    end)
    groupCheckbox = gcb

    -- Theme checkbox
    local tcb = CreateFrame("CheckButton", "ASThemeCB", cbRow,
                            "UICheckButtonTemplate")
    tcb:SetPoint("LEFT", gcb, "RIGHT", 110, 0)
    tcb:SetSize(22, 22)
    tcb.text = _G[tcb:GetName() .. "Text"] or tcb.Text
    if tcb.text then
        tcb.text:SetText("ElvUI Theme")
        tcb.text:SetFontObject("GameFontNormalSmall")
    end
    tcb:SetChecked(AS.db and AS.db.options and AS.db.options.elvuiTheme or false)
    tcb:SetScript("OnClick", function(self)
        if AS.db and AS.db.options then
            AS.db.options.elvuiTheme = self:GetChecked() and true or false
            AS.ApplyTheme()
        end
    end)
    themeCheckbox = tcb

    -- Verbose checkbox
    local vcb = CreateFrame("CheckButton", "ASVerboseCB", cbRow,
                            "UICheckButtonTemplate")
    vcb:SetPoint("LEFT", tcb, "RIGHT", 80, 0)
    vcb:SetSize(22, 22)
    vcb.text = _G[vcb:GetName() .. "Text"] or vcb.Text
    if vcb.text then
        vcb.text:SetText("Chat Log")
        vcb.text:SetFontObject("GameFontNormalSmall")
    end
    vcb:SetChecked(AS.db and AS.db.options and AS.db.options.verbose or false)
    vcb:SetScript("OnClick", function(self)
        if AS.db and AS.db.options then
            AS.db.options.verbose = self:GetChecked() and true or false
        end
    end)
    verboseCheckbox = vcb

    -- Retention row
    local retRow = CreateFrame("Frame", nil, f)
    retRow:SetPoint("TOPLEFT", cbRow, "BOTTOMLEFT", 0, 0)
    retRow:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    retRow:SetHeight(26)

    local retLabel = retRow:CreateFontString(nil, "OVERLAY",
                                              "GameFontNormalSmall")
    retLabel:SetPoint("LEFT", 4, 0)
    retLabel:SetText("Keep snapshots:")

    local retDD = CreateFrame("Frame", "ASRetentionDD", retRow,
                              "UIDropDownMenuTemplate")
    retDD:SetPoint("LEFT", retLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(retDD, 80)

    local retOptions = {
        { text = "1 day",   value = 1 },
        { text = "7 days",  value = 7 },
        { text = "14 days", value = 14 },
        { text = "30 days", value = 30 },
    }

    local function RetDDInit(self, level)
        local current = AS.db and AS.db.options
                        and AS.db.options.retentionDays or 30
        for _, opt in ipairs(retOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text    = opt.text
            info.value   = opt.value
            info.checked = (opt.value == current)
            info.func = function(self)
                if AS.db and AS.db.options then
                    AS.db.options.retentionDays = self.value
                end
                UIDropDownMenu_SetText(retDD, opt.text)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_Initialize(retDD, RetDDInit)

    -- Set initial text
    local initDays = AS.db and AS.db.options
                     and AS.db.options.retentionDays or 30
    for _, opt in ipairs(retOptions) do
        if opt.value == initDays then
            UIDropDownMenu_SetText(retDD, opt.text)
            break
        end
    end

    --==============================================================
    -- LEFT PANEL: Snapshot dropdown + member list
    --==============================================================
    local leftPanel = CreateFrame("Frame", nil, f)
    leftPanel:SetPoint("TOPLEFT", retRow, "BOTTOMLEFT", 2, -2)
    leftPanel:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)
    leftPanel:SetWidth(LIST_WIDTH)

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
    -- RIGHT PANEL: Char info + paper doll + talents + summary
    --==============================================================
    local rightPanel = CreateFrame("Frame", nil, f)
    rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 10, 0)
    rightPanel:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)
    rightPanel:SetWidth(DOLL_WIDTH)

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
    dollFrame = CreateFrame("Frame", nil, rightPanel)
    dollFrame:SetPoint("TOP", charGuildText, "BOTTOM", 0, -8)
    dollFrame:SetSize(DOLL_WIDTH, DOLL_H)

    dollBg = dollFrame:CreateTexture(nil, "BACKGROUND")
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

    -- Bottom row (MH / OH / Ranged) — centred below columns with gap
    local bw = #BOT_SLOTS * SLOT_SIZE + (#BOT_SLOTS - 1) * SLOT_SPACING
    local bx = (DOLL_WIDTH - bw) / 2
    local by = -(DOLL_COL_H + 10)   -- 10 px gap after columns
    for i, sid in ipairs(BOT_SLOTS) do
        local btn = CreateSlotButton(dollFrame, sid)
        btn:SetPoint("TOPLEFT", dollFrame, "TOPLEFT",
                     bx + (i - 1) * (SLOT_SIZE + SLOT_SPACING), by)
        slotButtons[sid] = btn
    end

    -- Centre silhouette
    local sil = dollFrame:CreateFontString(nil, "ARTWORK",
                                            "GameFontDisableLarge")
    sil:SetPoint("CENTER", 0, 10)
    sil:SetText("[ Character ]")
    sil:SetAlpha(0.15)

    --==============================================================
    -- TALENT BAR (below paper doll)
    --==============================================================
    talentFrame = CreateFrame("Frame", nil, rightPanel)
    talentFrame:SetPoint("TOP", dollFrame, "BOTTOM", 0, -6)
    talentFrame:SetSize(DOLL_WIDTH, TALENT_H)

    local tBg = talentFrame:CreateTexture(nil, "BACKGROUND")
    tBg:SetAllPoints()
    tBg:SetColorTexture(0, 0, 0, 0.2)
    talentFrame.bg = tBg

    -- Spec name + points string at top
    talentSpecText = talentFrame:CreateFontString(nil, "OVERLAY",
                                                   "GameFontNormal")
    talentSpecText:SetPoint("TOP", 0, -4)

    -- 3 tree columns: [icon] name \n points — evenly spaced
    talentIcons = {}
    talentTexts = {}
    local iconSize   = 22
    local colWidth    = math.floor(DOLL_WIDTH / 3)

    for t = 1, 3 do
        local colX = (t - 1) * colWidth

        local ic = talentFrame:CreateTexture(nil, "ARTWORK")
        ic:SetSize(iconSize, iconSize)
        ic:SetPoint("TOPLEFT", talentFrame, "TOPLEFT",
                    colX + 8, -22)
        ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        ic:Hide()
        talentIcons[t] = ic

        local tx = talentFrame:CreateFontString(nil, "OVERLAY",
                                                 "GameFontHighlightSmall")
        tx:SetPoint("LEFT", ic, "RIGHT", 4, 0)
        tx:SetWidth(colWidth - iconSize - 16)
        tx:SetJustifyH("LEFT")
        tx:SetText("")
        talentTexts[t] = tx
    end

    --==============================================================
    -- SUMMARY LABEL
    --==============================================================
    summaryLabel = rightPanel:CreateFontString(nil, "OVERLAY",
                                                "GameFontNormalSmall")
    summaryLabel:SetPoint("TOP", talentFrame, "BOTTOM", 0, -6)
    summaryLabel:SetWidth(DOLL_WIDTH - 8)
    summaryLabel:SetJustifyH("CENTER")

    browseFrame = f
    f:Hide()
end

----------------------------------------------------------------------
-- Status bar refresh
----------------------------------------------------------------------
local function UpdateScanStatus()
    if not browseFrame or not browseFrame:IsShown() then return end
    local s  = AS.session
    local elv = AS.db and AS.db.options and AS.db.options.elvuiTheme
    if s.active then
        local total = math.max(s.totalInRaid, 1)
        local pct   = s.totalCaptured / total
        scanStatusBar:SetValue(pct)
        scanStatusText:SetText("Scanning: " .. (s.snapshotKey or ""))
        scanStatusPct:SetText(s.totalCaptured .. " / " .. s.totalInRaid)
        if pct >= 1 then
            if elv then
                scanStatusBar:SetStatusBarColor(unpack(ELVUI.statusDone))
            else
                scanStatusBar:SetStatusBarColor(0.26, 0.8, 0.26, 0.7)
            end
        else
            if elv then
                scanStatusBar:SetStatusBarColor(unpack(ELVUI.statusBar))
            else
                scanStatusBar:SetStatusBarColor(0.9, 0.7, 0.0, 0.7)
            end
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

    local elv = AS.db and AS.db.options and AS.db.options.elvuiTheme
    local yOff, btnH = 0, 18
    for _, name in ipairs(names) do
        local member = snap.members[name]
        local btn = CreateFrame("Button", nil, memberScrollChild)
        btn:SetSize(LIST_WIDTH - 30, btnH)
        btn:SetPoint("TOPLEFT", 0, -yOff)

        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        if elv then
            hl:SetColorTexture(unpack(ELVUI.listHover))
        else
            hl:SetColorTexture(1, 1, 1, 0.1)
        end

        local sel = btn:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints()
        if elv then
            sel:SetColorTexture(unpack(ELVUI.listSelect))
        else
            sel:SetColorTexture(1, 1, 1, 0.15)
        end
        sel:Hide()
        btn.selTex = sel

        local cc = CLASS_COLORS[member.class] or { r=1, g=1, b=1 }
        local txt = btn:CreateFontString(nil, "OVERLAY",
                                          "GameFontHighlightSmall")
        txt:SetPoint("LEFT", 4, 0)
        txt:SetText(name)
        txt:SetTextColor(cc.r, cc.g, cc.b)

        -- Spec shorthand on right if talents exist
        local rightLabel = ""
        if member.talents and member.talents.points ~= ""
           and member.talents.points ~= "0/0/0" then
            rightLabel = member.talents.points
        else
            local gc = 0
            for _ in pairs(member.gear) do gc = gc + 1 end
            rightLabel = gc .. " items"
        end
        local ct = btn:CreateFontString(nil, "OVERLAY",
                                         "GameFontDisableSmall")
        ct:SetPoint("RIGHT", -4, 0)
        ct:SetText(rightLabel)

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
    if summaryLabel   then summaryLabel:SetText("") end
    if talentSpecText then talentSpecText:SetText("") end
    for t = 1, 3 do
        if talentIcons[t] then talentIcons[t]:Hide() end
        if talentTexts[t] then talentTexts[t]:SetText("") end
    end
    for _, btn in pairs(slotButtons) do SetSlotItem(btn, nil) end
end

function AS.RefreshPaperDoll()
    AS.ClearPaperDoll()
    if not selectedSnapshotKey or not selectedMemberName then return end
    local snap   = AS.db.snapshots[selectedSnapshotKey]
    if not snap then return end
    local member = snap.members[selectedMemberName]
    if not member then return end

    -- Character info
    local cc = CLASS_COLORS[member.class] or { r=1, g=1, b=1 }
    charNameText:SetText(member.name)
    charNameText:SetTextColor(cc.r, cc.g, cc.b)
    charDetailText:SetText("Level " .. (member.level or "?") .. " "
                           .. (member.race or "") .. " "
                           .. (member.class or ""))
    charGuildText:SetText(member.guild ~= ""
                          and ("<" .. member.guild .. ">") or "")

    -- Gear slots
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

    -- Talents
    local tal = member.talents
    if tal and tal.trees and #tal.trees > 0 then
        -- Check if we have real point data
        local totalPts = 0
        for _, tree in ipairs(tal.trees) do
            totalPts = totalPts + (tree.points or 0)
        end

        local specColor = "|cff" .. string.format("%02x%02x%02x",
            cc.r * 255, cc.g * 255, cc.b * 255)

        if totalPts > 0 then
            -- Full talent data available (self or working inspect)
            talentSpecText:SetText(specColor .. (tal.spec or "") .. "|r  "
                                   .. (tal.points or ""))
            for t = 1, math.min(3, #tal.trees) do
                local tree = tal.trees[t]
                if tree.icon and tree.icon ~= "" then
                    talentIcons[t]:SetTexture(tree.icon)
                    talentIcons[t]:Show()
                end
                talentTexts[t]:SetText(tree.name .. ": " .. tree.points)
            end
        else
            -- Tree names available but points not (Anniversary API limitation)
            talentSpecText:SetText("|cff888888Talent details unavailable via inspect|r")
            for t = 1, math.min(3, #tal.trees) do
                local tree = tal.trees[t]
                if tree.icon and tree.icon ~= "" then
                    talentIcons[t]:SetTexture(tree.icon)
                    talentIcons[t]:Show()
                end
                talentTexts[t]:SetText(tree.name .. "\n|cff666666N/A|r")
            end
        end
    end

    -- Summary
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
    if AS.session.snapshotKey and selectedSnapshotKey == AS.session.snapshotKey then
        AS.RefreshMemberList()
    end
end

function AS.UpdateGroupCheckbox()
    if groupCheckbox and AS.db and AS.db.options then
        groupCheckbox:SetChecked(AS.db.options.scanGroup)
    end
end

function AS.UpdateVerboseCheckbox()
    if verboseCheckbox and AS.db and AS.db.options then
        verboseCheckbox:SetChecked(AS.db.options.verbose)
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
        if themeCheckbox and AS.db and AS.db.options then
            themeCheckbox:SetChecked(AS.db.options.elvuiTheme)
        end
        if verboseCheckbox and AS.db and AS.db.options then
            verboseCheckbox:SetChecked(AS.db.options.verbose)
        end
        browseFrame:Show()
        AS.ApplyTheme()
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
-- MINIMAP BUTTON  (free-drag, works with any minimap shape/addon)
----------------------------------------------------------------------
local function CreateMinimapButton()
    local BUTTON_SIZE = 32

    local btn = CreateFrame("Button", "ASMinimapButton", UIParent)
    btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetClampedToScreen(true)
    btn:SetMovable(true)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    -- Circular mask background
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    bg:SetPoint("CENTER")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    -- Icon centred inside
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\INV_Chest_Chain_09")
    -- Crop icon to remove the border baked into the texture
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Minimap-style circular border overlay
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Highlight
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetSize(24, 24)
    hl:SetPoint("CENTER", 0, 1)
    hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    hl:SetBlendMode("ADD")

    -- Restore saved position or default near top-right of Minimap
    local function RestorePos()
        btn:ClearAllPoints()
        local saved = AS.db and AS.db.options and AS.db.options.minimapPos
        if saved and saved.point then
            btn:SetPoint(saved.point, UIParent, saved.relPoint,
                         saved.x, saved.y)
        else
            -- Default: near Minimap top-left area
            if Minimap then
                local mx, my = Minimap:GetCenter()
                local scale  = Minimap:GetEffectiveScale()
                local uScale = UIParent:GetEffectiveScale()
                local sx = (mx * scale) / uScale - 40
                local sy = (my * scale) / uScale + 40
                btn:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sx, sy)
            else
                btn:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -180)
            end
        end
    end

    local function SavePos()
        if not AS.db or not AS.db.options then return end
        local point, _, relPoint, x, y = btn:GetPoint(1)
        AS.db.options.minimapPos = {
            point    = point,
            relPoint = relPoint or point,
            x        = x,
            y        = y,
        }
    end

    btn:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePos()
    end)

    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            AS.ToggleBrowseFrame()
        elseif button == "RightButton" then
            if AS.db and AS.db.options then
                AS.db.options.elvuiTheme = not AS.db.options.elvuiTheme
                if AS.ApplyTheme then AS.ApplyTheme() end
                AS.Print("ElvUI theme "
                    .. (AS.db.options.elvuiTheme
                        and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
            end
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
        GameTooltip:AddLine("|cffffffffLeft-Click|r  Browse", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffffffffRight-Click|r Toggle ElvUI theme", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffffffffDrag|r  Move anywhere", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    C_Timer.After(0.5, RestorePos)
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
