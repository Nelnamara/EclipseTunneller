-- EclipseTunneller
-- Balance Druid Eclipse HUD for WoW Midnight (12.x)
-- Author: Nelnamara

local ADDON = "EclipseTunneller"
EclipseTunneller = {}
local ET = EclipseTunneller

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

local ASTRAL_POWER_TYPE = 8

-- Eclipse buff IDs — the self-buff AURAS applied while in Eclipse (15s state),
-- not the active ability you press. Confirmed current on 12.0.7 (Wowhead Live):
--   48517 Eclipse (Solar) — +dmg incl. Wrath; 48518 Eclipse (Lunar) — +dmg incl. Starfire.
-- (Was 164547/164812 — 164547 no longer exists and 164812 is *Moonfire*, so the
--  HUD was reading Moonfire as "Lunar Eclipse" and never detecting Solar. Verify
--  in-game: enter each Eclipse, /dump C_UnitAuras.GetPlayerAuraBySpellID(48517/48518).)
local AURA_SOLAR = 48517
local AURA_LUNAR = 48518

-- DoTs tracked on target
-- baseDuration: approximate base (un-hasted) seconds; used as fallback
local DOTS = {
    { id = 8921,   name = "Moonfire", baseDuration = 24, r = 1.0, g = 0.30, b = 0.00 },
    { id = 93402,  name = "Sunfire",  baseDuration = 18, r = 1.0, g = 0.90, b = 0.10 },
    { id = 202347, name = "St.Flare", baseDuration = 24, r = 0.6, g = 0.20, b = 1.00 },
}

-- CDs shown as Cooldown frames in the icon row
local CD_SPELLS = {
    { id = 194223 }, -- Celestial Alignment
    { id = 102560 }, -- Incarnation: Chosen of Elune
    { id = 202770 }, -- Fury of Elune
    { id = 391528 }, -- Convoke the Spirits
    { id = 202425 }, -- Warrior of Elune
    { id = 88747  }, -- Wild Mushroom
    { id = 78674  }, -- Starsurge
    { id = 191034 }, -- Starfall
}

local PANDEMIC_PCT = 0.30

local SUGGEST = {
    MISSING  = "|cFFFF4444Apply %s!|r",
    PANDEMIC = "|cFFFFCC00Refresh %s|r",
    USE_CA   = "|cFF00FFFFUse Celestial Alignment!|r",
    SOLAR    = "|cFFFFAA00Cast Wrath|r",
    LUNAR    = "|cFF88AAFFCast Starfire|r",
    BOTH     = "|cFFFFFFFFBurn everything!|r",
    NONE     = "|cFFAAAAAACast to build Eclipse|r",
}

-------------------------------------------------------------------------------
-- Saved variable defaults
-------------------------------------------------------------------------------

local DEFAULTS = {
    x = 0, y = -180,
    scale = 1.0,
    locked = false,
    showOutOfCombat = false,
    showStellarFlare = false,
    minimapAngle = 225,
    minimapHide = false,
}

-------------------------------------------------------------------------------
-- Runtime state
-- DoT expiry stored as our own computed GetTime() + duration (normal numbers,
-- never secret API values) so arithmetic is safe.
-------------------------------------------------------------------------------

local st = {
    eclipse   = "NONE",
    isBalance = false,
    inCombat  = false,
    dots      = {},  -- [spellID] = { computedExpiry, duration }
    cdReady   = {},  -- [spellID] = bool (isActive flag, not a secret value)
}

-------------------------------------------------------------------------------
-- Aura scanning
-------------------------------------------------------------------------------

local function ScanBuffs(unit, fn)
    if not C_UnitAuras then return end
    local i = 1
    while true do
        local d = C_UnitAuras.GetBuffDataByIndex(unit, i)
        if not d then break end
        if fn(d) then return end
        i = i + 1
    end
end

local function ScanDebuffs(unit, filter, fn)
    if not C_UnitAuras then return end
    local i = 1
    while true do
        local d = C_UnitAuras.GetDebuffDataByIndex(unit, i, filter)
        if not d then break end
        if fn(d) then return end
        i = i + 1
    end
end

local function GetEclipseState()
    -- C_UnitAuras.GetPlayerAuraBySpellID does the spellID match internally
    -- and returns nil/non-nil without exposing the secret spellId field for
    -- us to compare directly (direct comparison taints and errors).
    local solar = C_UnitAuras.GetPlayerAuraBySpellID(AURA_SOLAR) ~= nil
    local lunar = C_UnitAuras.GetPlayerAuraBySpellID(AURA_LUNAR) ~= nil
    if solar and lunar then return "BOTH"
    elseif solar       then return "SOLAR"
    elseif lunar       then return "LUNAR"
    else                    return "NONE" end
end

-- DoT tracking is event-driven on Midnight. Target-debuff scanning is blocked:
-- AuraUtil.FindAuraByName's underlying GetAuraDataBySpellName was removed in 12.0.7
-- (caused a 166x "call a nil value" crash), and aura.spellId/.name are secret so we
-- can't match them ourselves. Instead we record an expiry whenever the PLAYER casts
-- a DoT (UNIT_SPELLCAST_SUCCEEDED — spellID is non-secret for the "player" unit) and
-- clear on target change. baseDuration is approximate (no haste) but always a normal
-- number, never a secret API value.
local DOT_BY_ID = {}
for _, dot in ipairs(DOTS) do DOT_BY_ID[dot.id] = dot end

local function ClearDots()
    for id in pairs(st.dots) do st.dots[id] = nil end
end

local function RecordDotCast(spellID)
    local dot = DOT_BY_ID[spellID]
    if not dot then return end
    st.dots[dot.id] = {
        computedExpiry = GetTime() + dot.baseDuration,
        duration       = dot.baseDuration,
    }
end

-- Clear DoT state when there's no valid target (a new target's DoTs are unknown
-- until we see the player recast them).
local function RefreshDots()
    if not (UnitExists("target") and not UnitIsDeadOrGhost("target")) then
        ClearDots()
    end
end

-------------------------------------------------------------------------------
-- Suggestion engine (only uses our own computed normal-number dot state)
-------------------------------------------------------------------------------

local function GetSuggestion()
    local now = GetTime()

    -- Missing DoTs (highest priority)
    for _, dot in ipairs(DOTS) do
        if dot.id ~= 202347 or EclipseTunnellerDB.showStellarFlare then
            local d = st.dots[dot.id]
            if not d or (d.computedExpiry - now) <= 0 then
                return string.format(SUGGEST.MISSING, dot.name)
            end
        end
    end

    -- CA ready — suggest it when either CA or Incarnation is off cooldown
    if st.cdReady[194223] or st.cdReady[102560] then
        return SUGGEST.USE_CA
    end

    -- Pandemic refresh
    for _, dot in ipairs(DOTS) do
        if dot.id ~= 202347 or EclipseTunnellerDB.showStellarFlare then
            local d = st.dots[dot.id]
            if d and d.computedExpiry > 0 then
                local remaining = d.computedExpiry - now  -- normal - normal = safe
                if remaining <= (d.duration * PANDEMIC_PCT) then
                    return string.format(SUGGEST.PANDEMIC, dot.name)
                end
            end
        end
    end

    -- Eclipse cast
    if     st.eclipse == "BOTH"  then return SUGGEST.BOTH
    elseif st.eclipse == "SOLAR" then return SUGGEST.SOLAR
    elseif st.eclipse == "LUNAR" then return SUGGEST.LUNAR
    else                              return SUGGEST.NONE end
end

-------------------------------------------------------------------------------
-- UI construction
-------------------------------------------------------------------------------

local FRAME_W  = 230
local FRAME_H  = 152
local BAR_W    = FRAME_W - 16

local function BuildUI()
    local db = EclipseTunnellerDB

    local f = CreateFrame("Frame", "EclipseTunnellerFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
    f:SetScale(db.scale)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left=3, right=3, top=3, bottom=3 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.10, 0.88)
    f:SetBackdropBorderColor(0.4, 0.3, 0.6, 0.9)
    f:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" and not db.locked then self:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        local _, _, _, x, y = self:GetPoint()
        db.x, db.y = x, y
    end)

    -- Eclipse label
    local eclipseLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    eclipseLabel:SetPoint("TOP", f, "TOP", 0, -8)
    eclipseLabel:SetText("NO ECLIPSE")
    f.eclipseLabel = eclipseLabel

    -- Suggestion text
    local suggest = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    suggest:SetPoint("TOP", eclipseLabel, "BOTTOM", 0, -1)
    suggest:SetText("")
    f.suggest = suggest

    -- Astral Power StatusBar (accepts secret values without arithmetic)
    local apBg = CreateFrame("Frame", nil, f)
    apBg:SetSize(BAR_W, 14)
    apBg:SetPoint("TOP", suggest, "BOTTOM", 0, -3)
    local apBgTex = apBg:CreateTexture(nil, "BACKGROUND")
    apBgTex:SetAllPoints()
    apBgTex:SetColorTexture(0.12, 0.12, 0.12, 1)

    local apBar = CreateFrame("StatusBar", nil, apBg)
    apBar:SetAllPoints()
    apBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    apBar:SetStatusBarColor(0.55, 0.30, 1.0, 1)
    apBar:SetMinMaxValues(0, 100)
    apBar:SetValue(0)

    local apLabel = apBg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    apLabel:SetAllPoints()
    apLabel:SetJustifyH("CENTER")
    apLabel:SetText("Astral Power")
    apLabel:SetTextColor(0.85, 0.85, 0.85, 1)

    f.apBar   = apBar
    f.apBg    = apBg
    f.apLabel = apLabel

    -- DoT StatusBars
    f.dotRows = {}
    for i, dot in ipairs(DOTS) do
        local anchor = (i == 1) and apBg or f.dotRows[i-1].bg

        local bg = CreateFrame("Frame", nil, f)
        bg:SetSize(BAR_W, 15)
        bg:SetPoint("TOP", anchor, "BOTTOM", 0, -3)
        local bgTex = bg:CreateTexture(nil, "BACKGROUND")
        bgTex:SetAllPoints()
        bgTex:SetColorTexture(0.10, 0.10, 0.10, 1)

        local bar = CreateFrame("StatusBar", nil, bg)
        bar:SetAllPoints()
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar:SetStatusBarColor(dot.r, dot.g, dot.b, 1)
        bar:SetMinMaxValues(0, dot.baseDuration)
        bar:SetValue(0)

        local label = bg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetAllPoints()
        label:SetJustifyH("CENTER")
        label:SetText(dot.name)

        f.dotRows[i] = { bg = bg, bar = bar, label = label }
        bg:SetShown(i < 3 or db.showStellarFlare)
    end

    -- Cooldown icon row
    local cdRow = CreateFrame("Frame", nil, f)
    cdRow:SetSize(BAR_W, 24)
    cdRow:SetPoint("BOTTOM", f, "BOTTOM", 0, 5)
    f.cdIcons = {}

    for i, cd in ipairs(CD_SPELLS) do
        local btn = CreateFrame("Frame", nil, cdRow)
        btn:SetSize(22, 22)
        btn:SetPoint("LEFT", cdRow, "LEFT", (i-1)*24, 0)

        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local iconID = C_Spell.GetSpellTexture(cd.id)
        if iconID then tex:SetTexture(iconID) end

        -- Cooldown frame — Blizzard's frame handles secret values internally
        local cdf = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        cdf:SetAllPoints()
        cdf:SetDrawEdge(false)
        cdf:SetDrawSwipe(true)
        cdf:SetReverse(false)

        btn.tex = tex
        btn.cdf = cdf
        f.cdIcons[cd.id] = btn
    end

    ET.frame = f
end

-------------------------------------------------------------------------------
-- Update functions
-------------------------------------------------------------------------------

local ECLIPSE_TEXT  = { SOLAR="SOLAR ECLIPSE", LUNAR="LUNAR ECLIPSE", BOTH="CELESTIAL", NONE="NO ECLIPSE" }
local ECLIPSE_COLOR = {
    SOLAR = {1.0, 0.78, 0.00},
    LUNAR = {0.45, 0.65, 1.00},
    BOTH  = {1.0,  1.0,  1.00},
    NONE  = {0.45, 0.45, 0.45},
}

local function UpdateEclipse()
    local e = st.eclipse
    ET.frame.eclipseLabel:SetText(ECLIPSE_TEXT[e] or "NO ECLIPSE")
    local c = ECLIPSE_COLOR[e] or ECLIPSE_COLOR.NONE
    ET.frame.eclipseLabel:SetTextColor(c[1], c[2], c[3], 1)
end

local function UpdateAP()
    local f = ET.frame
    local maxAP = UnitPowerMax("player", ASTRAL_POWER_TYPE) or 100
    f.apBar:SetMinMaxValues(0, maxAP)
    -- SetValue accepts secret values — no arithmetic needed
    f.apBar:SetValue(UnitPower("player", ASTRAL_POWER_TYPE))
end

local function UpdateDots()
    local f   = ET.frame
    local now = GetTime()
    for i, dot in ipairs(DOTS) do
        local row = f.dotRows[i]
        if row.bg:IsShown() then
            local d = st.dots[dot.id]
            if not d then
                -- Not on target
                row.bar:SetMinMaxValues(0, dot.baseDuration)
                row.bar:SetValue(0)
                row.label:SetText(dot.name .. "  MISSING")
                row.label:SetTextColor(1, 0.25, 0.25, 1)
                row.bar:SetStatusBarColor(0.55, 0.10, 0.10, 1)
            else
                -- computedExpiry and duration are our own normal numbers
                local remaining = d.computedExpiry - now  -- safe: normal - normal
                if remaining <= 0 then
                    row.bar:SetMinMaxValues(0, d.duration)
                    row.bar:SetValue(0)
                    row.label:SetText(dot.name .. "  EXPIRED")
                    row.label:SetTextColor(1, 0.25, 0.25, 1)
                    row.bar:SetStatusBarColor(0.55, 0.10, 0.10, 1)
                else
                    row.bar:SetMinMaxValues(0, d.duration)
                    row.bar:SetValue(remaining)
                    local pandemic = remaining <= (d.duration * PANDEMIC_PCT)
                    if pandemic then
                        row.bar:SetStatusBarColor(1.0, 0.75, 0.0, 1)
                        row.label:SetTextColor(1.0, 0.85, 0.0, 1)
                    else
                        row.bar:SetStatusBarColor(dot.r, dot.g, dot.b, 1)
                        row.label:SetTextColor(0.9, 0.9, 0.9, 1)
                    end
                    row.label:SetText(dot.name .. "  " .. string.format("%.1fs", remaining))
                end
            end
        end
    end
end

local function UpdateCDs()
    local f = ET.frame
    for _, cd in ipairs(CD_SPELLS) do
        local icon = f.cdIcons[cd.id]
        if icon then
            local data = C_Spell.GetSpellCooldown(cd.id)
            if data and data.isActive then
                icon.tex:SetDesaturated(true)
                -- SetCooldown accepts secret values; use pcall anonymous closure
                pcall(function() icon.cdf:SetCooldown(data.startTime, data.duration) end)
                st.cdReady[cd.id] = false
            else
                icon.tex:SetDesaturated(false)
                icon.cdf:Clear()
                st.cdReady[cd.id] = true
            end
        end
    end
end

local function UpdateSuggest()
    ET.frame.suggest:SetText(st.inCombat and GetSuggestion() or "")
end

-------------------------------------------------------------------------------
-- Full update
-------------------------------------------------------------------------------

local function FullUpdate()
    if not ET.frame then return end
    st.eclipse = GetEclipseState()
    RefreshDots()
    UpdateEclipse()
    UpdateAP()
    UpdateDots()
    UpdateCDs()
    UpdateSuggest()
    local db = EclipseTunnellerDB
    ET.frame:SetShown(st.isBalance and (st.inCombat or db.showOutOfCombat))
end

-------------------------------------------------------------------------------
-- Ticker (0.1s for smooth bar updates)
-------------------------------------------------------------------------------

local ticker

local function StartTicker()
    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(0.1, FullUpdate)
end

local function StopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local function CheckSpec()
    local _, classFile = UnitClass("player")
    local idx = GetSpecialization()
    st.isBalance = (classFile == "DRUID") and (idx == 1)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
ev:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
ev:RegisterEvent("UNIT_AURA")
ev:RegisterEvent("UNIT_POWER_UPDATE")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

-- Minimap button — left-click toggles the HUD, right-click locks/unlocks, drag repositions.
local MM_RADIUS = 80
local function ETAngleOffset(a)
    return MM_RADIUS * math.cos(math.rad(a)), MM_RADIUS * math.sin(math.rad(a))
end

local function BuildMinimapButton()
    if ET.minimapBtn then return end
    local db = EclipseTunnellerDB
    local btn = CreateFrame("Button", "EclipseTunnellerMinimapButton", Minimap)
    btn:SetSize(24, 24)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:EnableMouse(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("AnyUp")

    -- Self-contained round icon (gold ring baked in) — SetAllPoints centers it cleanly.
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\AddOns\\EclipseTunneller\\Media\\minimap.png")

    btn:SetPoint("CENTER", Minimap, "CENTER", ETAngleOffset(db.minimapAngle or 225))

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cFF54a3ffEclipseTunneller|r")
        GameTooltip:AddLine("Left-click: Toggle HUD", 1, 1, 1)
        GameTooltip:AddLine("Right-click: Lock/unlock", 1, 1, 1)
        GameTooltip:AddLine("Drag: Reposition", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            SlashCmdList["ET"](EclipseTunnellerDB.locked and "unlock" or "lock")
        else
            SlashCmdList["ET"]("")
        end
    end)

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local s = UIParent:GetEffectiveScale()
            local angle = math.deg(math.atan2(py / s - my, px / s - mx))
            EclipseTunnellerDB.minimapAngle = angle
            self:ClearAllPoints()
            self:SetPoint("CENTER", Minimap, "CENTER", ETAngleOffset(angle))
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    if db.minimapHide then btn:Hide() end
    ET.minimapBtn = btn
end

ev:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        if not EclipseTunnellerDB then
            EclipseTunnellerDB = CopyTable(DEFAULTS)
        end
        for k, v in pairs(DEFAULTS) do
            if EclipseTunnellerDB[k] == nil then EclipseTunnellerDB[k] = v end
        end
        BuildMinimapButton()

    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        CheckSpec()
        if not ET.frame then BuildUI() end
        if st.isBalance then StartTicker() end
        FullUpdate()

    elseif event == "PLAYER_REGEN_DISABLED" then
        st.inCombat = true
        if st.isBalance then StartTicker() end

    elseif event == "PLAYER_REGEN_ENABLED" then
        st.inCombat = false
        FullUpdate()
        if not EclipseTunnellerDB.showOutOfCombat then StopTicker() end

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        CheckSpec()
        if st.isBalance then StartTicker() else StopTicker() end
        FullUpdate()

    elseif event == "UNIT_AURA" then
        if arg1 == "player" then
            st.eclipse = GetEclipseState()
            if ET.frame then UpdateEclipse(); UpdateSuggest() end
        end

    elseif event == "UNIT_POWER_UPDATE" and arg1 == "player" then
        if ET.frame then UpdateAP() end

    elseif event == "PLAYER_TARGET_CHANGED" then
        ClearDots()        -- new target: DoT state unknown until recast
        RefreshDots()      -- (also clears if there's no valid target)
        if ET.frame then UpdateDots(); UpdateSuggest() end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" then
        RecordDotCast(arg3)   -- arg3 = spellID (non-secret for the player unit)
        if ET.frame then UpdateDots(); UpdateSuggest() end
    end
end)

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------

SLASH_ET1 = "/et"
SlashCmdList["ET"] = function(msg)
    msg = strtrim(msg):lower()
    if msg == "" then
        -- Toggle: flip showOutOfCombat and force a full update so the frame
        -- appears immediately without needing to enter combat.
        EclipseTunnellerDB.showOutOfCombat = not EclipseTunnellerDB.showOutOfCombat
        if EclipseTunnellerDB.showOutOfCombat and st.isBalance then
            StartTicker()
        end
        FullUpdate()
        local state = EclipseTunnellerDB.showOutOfCombat and "shown" or "hidden (combat only)"
        print("|cFF54a3ffEclipseTunneller:|r " .. state)
    elseif msg == "lock" then
        EclipseTunnellerDB.locked = true
        print("|cFF54a3ffEclipseTunneller:|r Locked.")
    elseif msg == "unlock" then
        EclipseTunnellerDB.locked = false
        print("|cFF54a3ffEclipseTunneller:|r Unlocked — drag to reposition.")
    elseif msg == "combat" then
        EclipseTunnellerDB.showOutOfCombat = not EclipseTunnellerDB.showOutOfCombat
        if EclipseTunnellerDB.showOutOfCombat and st.isBalance then
            StartTicker()
        end
        print("|cFF54a3ffEclipseTunneller:|r Show out of combat: "
            .. tostring(EclipseTunnellerDB.showOutOfCombat))
        FullUpdate()
    elseif msg == "stellar" then
        EclipseTunnellerDB.showStellarFlare = not EclipseTunnellerDB.showStellarFlare
        if ET.frame then
            ET.frame.dotRows[3].bg:SetShown(EclipseTunnellerDB.showStellarFlare)
        end
        print("|cFF54a3ffEclipseTunneller:|r Stellar Flare row: "
            .. tostring(EclipseTunnellerDB.showStellarFlare))
    elseif msg == "reset" then
        EclipseTunnellerDB.x, EclipseTunnellerDB.y = 0, -180
        if ET.frame then
            ET.frame:ClearAllPoints()
            ET.frame:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
        end
        print("|cFF54a3ffEclipseTunneller:|r Position reset.")
    elseif msg == "debug" then
        local _, cls = UnitClass("player")
        local spec = GetSpecialization()
        print("|cFF54a3ffEclipseTunneller DEBUG:|r")
        print("  class=" .. tostring(cls) .. "  spec=" .. tostring(spec))
        print("  isBalance=" .. tostring(st.isBalance))
        print("  inCombat=" .. tostring(st.inCombat))
        print("  eclipse=" .. tostring(st.eclipse))
        print("  frame=" .. tostring(ET.frame ~= nil))
        print("  showOutOfCombat=" .. tostring(EclipseTunnellerDB.showOutOfCombat))
        print("  ticker=" .. tostring(ticker ~= nil))
    else
        print("|cFF54a3ffEclipseTunneller|r — Balance Druid Eclipse HUD")
        print("  /et          toggle (show/hide out of combat)")
        print("  /et lock     lock frame position")
        print("  /et unlock   unlock frame (drag to move)")
        print("  /et combat   same as /et toggle")
        print("  /et stellar  toggle Stellar Flare DoT row")
        print("  /et reset    reset frame position")
        print("  /et debug    print current state to chat")
    end
end
