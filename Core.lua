----------------------------------------------------------------------
-- ArmorySnap  –  Core.lua  v1.1.0
-- Passive scanner, talent capture, inspect queue, data management
----------------------------------------------------------------------
local ADDON_NAME = "ArmorySnap"
local AS = {}
_G.ArmorySnap = AS

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------
AS.SLOT_ORDER = { 1,2,3,15,5,4,19,9, 10,6,7,8,11,12,13,14, 16,17,18 }

AS.SLOT_INFO = {
    [1]  = { name = "HeadSlot",          label = "Head" },
    [2]  = { name = "NeckSlot",          label = "Neck" },
    [3]  = { name = "ShoulderSlot",      label = "Shoulder" },
    [4]  = { name = "ShirtSlot",         label = "Shirt" },
    [5]  = { name = "ChestSlot",         label = "Chest" },
    [6]  = { name = "WaistSlot",         label = "Waist" },
    [7]  = { name = "LegsSlot",          label = "Legs" },
    [8]  = { name = "FeetSlot",          label = "Feet" },
    [9]  = { name = "WristSlot",         label = "Wrist" },
    [10] = { name = "HandsSlot",         label = "Hands" },
    [11] = { name = "Finger0Slot",       label = "Finger 1" },
    [12] = { name = "Finger1Slot",       label = "Finger 2" },
    [13] = { name = "Trinket0Slot",      label = "Trinket 1" },
    [14] = { name = "Trinket1Slot",      label = "Trinket 2" },
    [15] = { name = "BackSlot",          label = "Back" },
    [16] = { name = "MainHandSlot",      label = "Main Hand" },
    [17] = { name = "SecondaryHandSlot", label = "Off Hand" },
    [18] = { name = "RangedSlot",        label = "Ranged / Relic" },
    [19] = { name = "TabardSlot",        label = "Tabard" },
}

AS.EMPTY_SLOT_TEXTURES = {}

----------------------------------------------------------------------
-- Tunables
----------------------------------------------------------------------
local SCAN_TICK        = 3
local RETRY_COOLDOWN   = 120
local ROSTER_CHECK     = 10
local INSPECT_TIMEOUT  = 4

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
AS.db = nil

AS.session = {
    active       = false,
    snapshotKey  = nil,
    captured     = {},
    pending      = {},
    failed       = {},
    inspecting   = false,
    currentUnit  = nil,
    passComplete = false,
    retryClock   = 0,
    rosterClock  = 0,
    totalInRaid  = 0,
    totalCaptured= 0,
}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[ArmorySnap]|r " .. tostring(msg))
end
AS.Print = Print

local function Verbose(msg)
    if AS.db and AS.db.options and AS.db.options.verbose then
        Print(msg)
    end
end

local function GetTimestamp()
    return date("%Y-%m-%d %H:%M")
end

local function GetGroupSize()
    if GetNumRaidMembers then
        local n = GetNumRaidMembers()
        if n > 0 then return n, "raid" end
    elseif IsInRaid and IsInRaid() then
        return GetNumGroupMembers(), "raid"
    end
    local n = GetNumPartyMembers and GetNumPartyMembers()
             or (GetNumGroupMembers and GetNumGroupMembers() or 0)
    if n > 0 then return n, "party" end
    return 0, "none"
end

----------------------------------------------------------------------
-- Instance / zone detection
----------------------------------------------------------------------
function AS.ShouldAutoScan()
    local inInstance, instanceType = IsInInstance()
    if inInstance and instanceType == "raid" then return true end
    if AS.db and AS.db.options and AS.db.options.scanGroup then
        local size = GetGroupSize()
        if size > 0 then return true end
    end
    return false
end

----------------------------------------------------------------------
-- Session key
----------------------------------------------------------------------
local function MakeSessionKey()
    local zone = GetRealZoneText() or "Unknown"
    return GetTimestamp() .. " - " .. zone
end

----------------------------------------------------------------------
-- Cache empty-slot textures
----------------------------------------------------------------------
local function CacheEmptyTextures()
    for slotId, info in pairs(AS.SLOT_INFO) do
        local _, tex = GetInventorySlotInfo(info.name)
        AS.EMPTY_SLOT_TEXTURES[slotId] = tex
    end
end

----------------------------------------------------------------------
-- Capture gear for a unit
----------------------------------------------------------------------
local function CaptureGear(unit)
    local gear = {}
    for slotId in pairs(AS.SLOT_INFO) do
        local link = GetInventoryItemLink(unit, slotId)
        local tex  = GetInventoryItemTexture(unit, slotId)
        if link then
            gear[slotId] = { link = link, icon = tex or "" }
        end
    end
    return gear
end

----------------------------------------------------------------------
-- Capture talents for a unit
-- TBC API: GetTalentTabInfo(tabIndex, inspect, pet)
--   returns: name, iconTexture, pointsSpent, background, ...
----------------------------------------------------------------------
local function CaptureTalents(isInspect)
    local talents = {
        trees  = {},
        spec   = "",
        points = "",
    }
    local maxPts, maxTree = 0, ""
    local ptsStrParts = {}

    -- TBC Anniversary API:
    --   Self:    GetNumTalentTabs()        / GetTalentTabInfo(tab)
    --   Inspect: GetNumTalentTabs(true)    / GetTalentTabInfo(tab, true)
    local ok, numTabs
    if isInspect then
        ok, numTabs = pcall(GetNumTalentTabs, true)
    else
        ok, numTabs = pcall(GetNumTalentTabs)
    end
    if not ok or not numTabs then numTabs = 3 end
    numTabs = tonumber(numTabs) or 3

    for tab = 1, numTabs do
        local tOk, tName, tIcon, tPts, tBg
        if isInspect then
            tOk, tName, tIcon, tPts, tBg = pcall(GetTalentTabInfo, tab, true)
        else
            tOk, tName, tIcon, tPts, tBg = pcall(GetTalentTabInfo, tab)
        end
        if not tOk then
            tName, tIcon, tPts = "Tree " .. tab, "", 0
        end
        tName = tName or ("Tree " .. tab)
        tPts  = tonumber(tPts) or 0
        tIcon = tIcon or ""
        table.insert(talents.trees, {
            name   = tName,
            icon   = tIcon,
            points = tPts,
        })
        table.insert(ptsStrParts, tostring(tPts))
        if tPts > maxPts then
            maxPts  = tPts
            maxTree = tName
        end
    end

    talents.spec   = maxTree
    talents.points = table.concat(ptsStrParts, "/")
    return talents
end

----------------------------------------------------------------------
-- Capture character metadata
----------------------------------------------------------------------
local function CaptureCharInfo(unit)
    local name, realm = UnitName(unit)
    if realm and realm ~= "" then name = name .. "-" .. realm end
    local _, classFile = UnitClass(unit)
    return {
        name    = name or "Unknown",
        class   = classFile or "WARRIOR",
        race    = UnitRace(unit) or "",
        level   = UnitLevel(unit) or 0,
        guild   = GetGuildInfo(unit) or "",
        sex     = UnitSex(unit) or 1,
        gear    = {},
        talents = nil,
    }
end

----------------------------------------------------------------------
-- Parse enchant / gem IDs from item link
----------------------------------------------------------------------
function AS.ParseItemLink(link)
    if not link then return nil end
    local _, _, color, itemStr, name =
        string.find(link, "|c(%x+)|Hitem:(.+)|h%[(.+)%]|h|r")
    if not itemStr then return nil end
    local parts = { strsplit(":", itemStr) }
    return {
        itemId    = tonumber(parts[1]) or 0,
        enchantId = tonumber(parts[2]) or 0,
        gem1      = tonumber(parts[3]) or 0,
        gem2      = tonumber(parts[4]) or 0,
        gem3      = tonumber(parts[5]) or 0,
        name      = name or "",
        color     = color or "ffffffff",
        fullLink  = link,
    }
end

----------------------------------------------------------------------
-- SESSION MANAGEMENT
----------------------------------------------------------------------
local function EnsureSessionSnapshot()
    local s = AS.session
    if s.snapshotKey and AS.db.snapshots[s.snapshotKey] then
        return s.snapshotKey
    end
    local key = MakeSessionKey()
    if not AS.db.snapshots[key] then
        AS.db.snapshots[key] = {
            timestamp = GetTimestamp(),
            zone      = GetRealZoneText() or "Unknown",
            members   = {},
        }
    end
    s.snapshotKey = key
    return key
end

local function BuildPendingQueue()
    local s = AS.session
    s.pending = {}
    s.failed  = {}
    local size, groupType = GetGroupSize()
    s.totalInRaid = size
    local added = {}

    for i = 1, size do
        local unit
        if groupType == "raid" then
            unit = "raid" .. i
        elseif i < size then
            unit = "party" .. i
        else
            unit = "player"
        end
        if unit and UnitExists(unit) then
            local uName = UnitName(unit)
            local realm = select(2, UnitName(unit))
            if realm and realm ~= "" then uName = uName .. "-" .. realm end
            if uName and not s.captured[uName] and not added[uName] then
                table.insert(s.pending, unit)
                added[uName] = true
            end
        end
    end
    if groupType == "party" then
        local pName = UnitName("player")
        if pName and not s.captured[pName] and not added[pName] then
            table.insert(s.pending, "player")
        end
    end
end

local function UpdateCounts()
    local s = AS.session
    local c = 0
    for _ in pairs(s.captured) do c = c + 1 end
    s.totalCaptured = c
end

function AS.ResetSession()
    local s = AS.session
    s.active        = false
    s.snapshotKey   = nil
    s.captured      = {}
    s.pending       = {}
    s.failed        = {}
    s.inspecting    = false
    s.currentUnit   = nil
    s.passComplete  = false
    s.retryClock    = 0
    s.rosterClock   = 0
    s.totalInRaid   = 0
    s.totalCaptured = 0
end

----------------------------------------------------------------------
-- INSPECT HANDLING
----------------------------------------------------------------------
local inspectTimer = nil

local function FinishInspect()
    local s = AS.session
    if inspectTimer then inspectTimer:Cancel(); inspectTimer = nil end
    ClearInspectPlayer()
    s.inspecting  = false
    s.currentUnit = nil
end

local function OnInspectReady(guid)
    local s = AS.session
    if not s.inspecting or not s.currentUnit then return end
    if not s.snapshotKey then FinishInspect(); return end

    local unit = s.currentUnit
    if guid and UnitGUID(unit) ~= guid then return end

    local snap = AS.db.snapshots[s.snapshotKey]
    if not snap then FinishInspect(); return end

    local charInfo    = CaptureCharInfo(unit)
    charInfo.gear     = CaptureGear(unit)
    charInfo.talents  = CaptureTalents(true)  -- inspect = true
    snap.members[charInfo.name] = charInfo
    s.captured[charInfo.name]   = true
    UpdateCounts()

    local gc = 0
    for _ in pairs(charInfo.gear) do gc = gc + 1 end
    local specStr = ""
    if charInfo.talents and charInfo.talents.spec ~= "" then
        specStr = "  " .. charInfo.talents.points .. " " .. charInfo.talents.spec
    end
    Verbose("  Scanned |cffffffff" .. charInfo.name .. "|r (" .. gc
          .. " items" .. specStr .. ")  [" .. s.totalCaptured .. "/" .. s.totalInRaid .. "]")

    FinishInspect()
    if AS.OnMemberCaptured then AS.OnMemberCaptured() end
end

local function TryInspectUnit(unit)
    local s = AS.session
    if not UnitExists(unit) or not UnitIsConnected(unit) then return false end

    -- Self
    if UnitIsUnit(unit, "player") then
        EnsureSessionSnapshot()
        local snap = AS.db.snapshots[s.snapshotKey]
        if snap then
            local ci = CaptureCharInfo(unit)
            ci.gear    = CaptureGear(unit)
            ci.talents = CaptureTalents(false) -- inspect = false (self)
            snap.members[ci.name] = ci
            s.captured[ci.name]   = true
            UpdateCounts()
            local specStr = ""
            if ci.talents and ci.talents.spec ~= "" then
                specStr = "  " .. ci.talents.points .. " " .. ci.talents.spec
            end
            Verbose("  Scanned |cffffffff" .. ci.name .. "|r (self" .. specStr .. ")  ["
                  .. s.totalCaptured .. "/" .. s.totalInRaid .. "]")
            if AS.OnMemberCaptured then AS.OnMemberCaptured() end
        end
        return true
    end

    if not CheckInteractDistance(unit, 1) then return false end
    if CanInspect and not CanInspect(unit) then return false end

    s.inspecting  = true
    s.currentUnit = unit
    NotifyInspect(unit)

    inspectTimer = C_Timer.NewTimer(INSPECT_TIMEOUT, function()
        if s.inspecting then FinishInspect() end
    end)
    return true
end

----------------------------------------------------------------------
-- PASSIVE SCANNER TICK
----------------------------------------------------------------------
local lastZone = nil

local function ScannerTick()
    local s = AS.session

    if not AS.ShouldAutoScan() then
        if s.active then
            Verbose("Left scannable area — pausing.")
            s.active = false
        end
        return
    end

    local zone = GetRealZoneText() or ""
    if zone ~= lastZone then
        if lastZone and s.snapshotKey then
            Verbose("Zone changed → starting new scan session.")
        end
        AS.ResetSession()
        lastZone = zone
    end

    if not s.active then
        s.active = true
        EnsureSessionSnapshot()
        BuildPendingQueue()
        if #s.pending > 0 then
            Verbose("Auto-scan started in |cfffff000" .. zone
                  .. "|r  (" .. #s.pending .. " members)")
        end
    end

    if s.inspecting then return end

    if s.passComplete then
        s.rosterClock = s.rosterClock - SCAN_TICK
        if s.rosterClock <= 0 then
            s.rosterClock = ROSTER_CHECK
            BuildPendingQueue()
            if #s.pending > 0 then
                s.passComplete = false
                Verbose("Roster change detected — scanning "
                      .. #s.pending .. " new/remaining members.")
            end
        end
        if #s.failed > 0 then
            s.retryClock = s.retryClock - SCAN_TICK
            if s.retryClock <= 0 then
                s.pending      = s.failed
                s.failed       = {}
                s.passComplete = false
                Verbose("Retrying " .. #s.pending
                      .. " members that were out of range …")
            end
        end
        return
    end

    while #s.pending > 0 do
        local unit = table.remove(s.pending, 1)
        if UnitExists(unit) then
            local uName = UnitName(unit)
            local realm = select(2, UnitName(unit))
            if realm and realm ~= "" then uName = uName .. "-" .. realm end
            if uName and not s.captured[uName] then
                EnsureSessionSnapshot()
                if TryInspectUnit(unit) then return end
                table.insert(s.failed, unit)
            end
        end
    end

    s.passComplete = true
    UpdateCounts()
    if #s.failed > 0 then
        s.retryClock = RETRY_COOLDOWN
        Verbose("Pass done. |cffffffff" .. s.totalCaptured .. "/"
              .. s.totalInRaid .. "|r captured.  Retrying "
              .. #s.failed .. " in " .. RETRY_COOLDOWN .. "s.")
    else
        s.rosterClock = ROSTER_CHECK
        if s.totalCaptured > 0 then
            Verbose("All |cff00ff00" .. s.totalCaptured
                  .. "|r raid members captured!")
        end
    end
end

----------------------------------------------------------------------
-- Manual snapshot
----------------------------------------------------------------------
function AS.TakeManualSnapshot(label)
    local size, groupType = GetGroupSize()
    if size == 0 then Print("You are not in a group."); return end

    local zone = label or GetRealZoneText() or "Unknown"
    local key  = GetTimestamp() .. " - " .. zone
    AS.db.snapshots[key] = {
        timestamp = GetTimestamp(),
        zone      = zone,
        members   = {},
    }
    local snap = AS.db.snapshots[key]

    local queue = {}
    for i = 1, size do
        local unit = (groupType == "raid") and ("raid" .. i)
                     or (i < size and ("party" .. i) or "player")
        if UnitExists(unit) then table.insert(queue, unit) end
    end

    Verbose("Manual snapshot: |cfffff000" .. key .. "|r  (" .. #queue .. " members)")

    local captured, idx = 0, 0
    local function DoNext()
        idx = idx + 1
        if idx > #queue then
            Verbose("Manual snapshot done — " .. captured .. "/" .. #queue .. " captured.")
            if AS.RefreshSnapshotList then AS.RefreshSnapshotList() end
            return
        end
        local unit = queue[idx]
        if UnitIsUnit(unit, "player") then
            local ci = CaptureCharInfo(unit)
            ci.gear    = CaptureGear(unit)
            ci.talents = CaptureTalents(false)
            snap.members[ci.name] = ci; captured = captured + 1
            DoNext()
        elseif UnitExists(unit) and CheckInteractDistance(unit, 1) then
            local waiting, timer = true, nil
            local handler = CreateFrame("Frame")
            handler:RegisterEvent("INSPECT_READY")
            handler:SetScript("OnEvent", function(self, _, guid)
                if not waiting then return end
                if guid and UnitGUID(unit) ~= guid then return end
                waiting = false; self:UnregisterAllEvents()
                if timer then timer:Cancel() end
                local ci = CaptureCharInfo(unit)
                ci.gear    = CaptureGear(unit)
                ci.talents = CaptureTalents(true)
                snap.members[ci.name] = ci; captured = captured + 1
                ClearInspectPlayer()
                C_Timer.After(0.5, DoNext)
            end)
            NotifyInspect(unit)
            timer = C_Timer.NewTimer(INSPECT_TIMEOUT, function()
                if waiting then
                    waiting = false; handler:UnregisterAllEvents()
                    ClearInspectPlayer(); C_Timer.After(0.2, DoNext)
                end
            end)
        else
            DoNext()
        end
    end
    DoNext()
end

----------------------------------------------------------------------
-- Snapshot helpers
----------------------------------------------------------------------
function AS.GetSnapshotKeys()
    local keys = {}
    for k in pairs(AS.db.snapshots) do table.insert(keys, k) end
    table.sort(keys, function(a, b) return a > b end)
    return keys
end

function AS.GetMemberNames(snapshotKey)
    local snap = AS.db.snapshots[snapshotKey]
    if not snap then return {} end
    local names = {}
    for name in pairs(snap.members) do table.insert(names, name) end
    table.sort(names)
    return names
end

function AS.DeleteSnapshot(key)
    if AS.db.snapshots[key] then
        AS.db.snapshots[key] = nil
        Print("Deleted snapshot: " .. key)
        if AS.RefreshSnapshotList then AS.RefreshSnapshotList() end
    else
        Print("Snapshot not found: " .. key)
    end
end

----------------------------------------------------------------------
-- EVENT FRAME
----------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("INSPECT_READY")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        if not ArmorySnapDB then
            ArmorySnapDB = { snapshots = {}, options = {} }
        end
        AS.db = ArmorySnapDB
        if not AS.db.snapshots then AS.db.snapshots = {} end
        if not AS.db.options   then AS.db.options   = {} end
        if AS.db.options.scanGroup  == nil then AS.db.options.scanGroup  = false end
        if AS.db.options.elvuiTheme == nil then AS.db.options.elvuiTheme = false end
        if AS.db.options.verbose    == nil then AS.db.options.verbose    = false end
        if AS.db.options.minimapPos == nil then AS.db.options.minimapPos = nil end

        CacheEmptyTextures()
        C_Timer.NewTicker(SCAN_TICK, ScannerTick)
        Print("v1.1.0 loaded. |cfffff000/as|r to open.")

    elseif event == "INSPECT_READY" then
        OnInspectReady(arg1)

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        C_Timer.After(2, ScannerTick)

    elseif event == "RAID_ROSTER_UPDATE"
        or event == "GROUP_ROSTER_UPDATE" then
        if AS.session.passComplete then
            AS.session.rosterClock = 0
        end
    end
end)

----------------------------------------------------------------------
-- SLASH COMMANDS
----------------------------------------------------------------------
SLASH_ARMORYSNAP1 = "/as"
SLASH_ARMORYSNAP2 = "/armorysnap"

SlashCmdList["ARMORYSNAP"] = function(msg)
    local cmd, rest = strsplit(" ", msg or "", 2)
    cmd = strlower(strtrim(cmd or ""))

    if cmd == "snap" or cmd == "snapshot" then
        local label = rest and strtrim(rest)
        if label == "" then label = nil end
        AS.TakeManualSnapshot(label)

    elseif cmd == "browse" or cmd == "view" or cmd == "open" or cmd == "" then
        AS.ToggleBrowseFrame()

    elseif cmd == "list" then
        local keys = AS.GetSnapshotKeys()
        if #keys == 0 then
            Print("No snapshots stored.")
        else
            Print("Stored snapshots:")
            for i, k in ipairs(keys) do
                local snap = AS.db.snapshots[k]
                local count = 0
                for _ in pairs(snap.members) do count = count + 1 end
                Print("  " .. i .. ". |cfffff000" .. k
                      .. "|r (" .. count .. " members)")
            end
        end

    elseif cmd == "delete" or cmd == "del" then
        if rest and rest ~= "" then
            AS.DeleteSnapshot(strtrim(rest))
        else Print("Usage: /as delete <snapshot name>") end

    elseif cmd == "group" then
        AS.db.options.scanGroup = not AS.db.options.scanGroup
        if AS.db.options.scanGroup then
            Print("Group scanning |cff00ff00ENABLED|r")
        else
            Print("Group scanning |cffff4444DISABLED|r")
        end
        if AS.UpdateGroupCheckbox then AS.UpdateGroupCheckbox() end

    elseif cmd == "elvui" or cmd == "theme" then
        AS.db.options.elvuiTheme = not AS.db.options.elvuiTheme
        if AS.db.options.elvuiTheme then
            Print("ElvUI theme |cff00ff00ENABLED|r — reopen browser to apply.")
        else
            Print("ElvUI theme |cffff4444DISABLED|r — reopen browser to apply.")
        end
        if AS.ApplyTheme then AS.ApplyTheme() end

    elseif cmd == "verbose" or cmd == "chat" then
        AS.db.options.verbose = not AS.db.options.verbose
        if AS.db.options.verbose then
            Print("Chat output |cff00ff00ENABLED|r")
        else
            Print("Chat output |cffff4444DISABLED|r")
        end
        if AS.UpdateVerboseCheckbox then AS.UpdateVerboseCheckbox() end

    elseif cmd == "status" then
        local s = AS.session
        if s.active then
            Print("Scanning: |cffffffff" .. s.totalCaptured .. "/"
                  .. s.totalInRaid .. "|r captured.")
            Print("Session: |cfffff000" .. (s.snapshotKey or "none") .. "|r")
            if s.passComplete and #s.failed > 0 then
                Verbose("Retrying " .. #s.failed .. " in "
                      .. math.max(0, math.floor(s.retryClock)) .. "s")
            end
        else
            Print("Scanner idle.")
        end
        Print("Group scan: " .. (AS.db.options.scanGroup
              and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
        Print("ElvUI theme: " .. (AS.db.options.elvuiTheme
              and "|cff00ff00ON|r" or "|cffff4444OFF|r"))

    elseif cmd == "reset" then
        AS.ResetSession()
        lastZone = nil
        Print("Session reset.")

    else
        Print("Commands:")
        Print("  |cfffff000/as|r               – Open gear browser")
        Print("  |cfffff000/as snap [label]|r   – Manual snapshot")
        Print("  |cfffff000/as list|r            – List saved snapshots")
        Print("  |cfffff000/as delete <n>|r   – Delete a snapshot")
        Print("  |cfffff000/as group|r           – Toggle group scanning")
        Print("  |cfffff000/as theme|r           – Toggle ElvUI theme")
        Print("  |cfffff000/as verbose|r         – Toggle chat output")
        Print("  |cfffff000/as status|r          – Show scanner status")
        Print("  |cfffff000/as reset|r           – Reset current session")
    end
end
