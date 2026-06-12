-- EclipseTunneller
-- Balance Druid Eclipse HUD for WoW Midnight (12.x)
-- Author: Nelnamara

local ADDON = "EclipseTunneller"
EclipseTunneller = {}
local ET = EclipseTunneller

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

local ASTRAL_POWER_TYPE = 8  -- Enum.PowerType.LunarPower / AstralPower

-- Eclipse buff IDs (verify on live if Blizzard renumbers in 12.x)
local AURA_SOLAR   = 164547
local AURA_LUNAR   = 164812

-- DoT debuff IDs tracked on the current target
local DOTS = {
    { id = 8921,   name = "Moonfire", r = 1.0, g = 0.30, b = 0.00 },
    { id = 93402,  name = "Sunfire",  r = 1.0, g = 0.90, b = 0.10 },
    { id = 202347, name = "St.Flare", r = 0.6, g = 0.20, b = 1.00 },
}

-- Cooldown spells shown in the icon row
-- Inactive talents will simply show no CD (C_Spell returns nil for unlearned spells)
local CD_SPELLS = {
    { id = 194223 }, -- Celestial Alignment
    { id = 102560 }, -- Incarnation: Chosen of Elune
    { id = 202770 }, -- Fury of Elune
    { id = 391528 }, -- Convoke the Spirits
    { id = 202425 }, -- Warrior of Elune
    { id = 88747  }, -- Wild Mushroom
    { id = 78674  }, -- Starsurge  (track its cooldown if specced)
    { id = 191034 }, -- Starfall
}

-- Pandemic refresh window = 30% of base duration
local PANDEMIC_PCT = 0.30

-- Suggested-cast priority strings
local SUGGEST = {
    MISSING_DOT  = "|cFFFF4444Apply %s!|r",
    PANDEMIC_DOT = "|cFFFFCC00Refresh %s|r",
    SPEND_AP     = "|cFFFFD700Spend Astral Power|r",
    USE_CD       = "|cFF00FFFF%s ready!|r",
    SOLAR_CAST   = "|cFFFFAA00Cast Wrath|r",
    LUNAR_CAST   = "|cFF88AAFF Cast Starfire|r",
    NO_ECLIPSE   = "|cFFAAAAAACast to build Eclipse|r",
    BOTH         = "|cFFFFFFFFBurn it all!|r",
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
}

-------------------------------------------------------------------------------
-- Runtime state
-------------------------------------------------------------------------------

local st = {
    eclipse   = "NONE",   -- "SOLAR" | "LUNAR" | "BOTH" | "NONE"
    ap        = 0,
    apMax     = 100,
    isBalance = false,
    inCombat  = false,
    dots      = {},       -- [spellID] = { expiry, duration }
    cds       = {},       -- [spellID] = { start, duration }
}

-------------------------------------------------------------------------------
-- Aura helpers (Midnight C_UnitAuras API)
-------------------------------------------------------------------------------

local function ScanBuffs(unit, fn)
    if not C_UnitAuras then return end
    local i = 1
    while true do
        local data = C_UnitAuras.GetBuffDataByIndex(unit, i)
        if not data then break end
        if fn(data) then return true end
        i = i + 1
    end
end

local function ScanDebuffs(unit, filter, fn)
    if not C_UnitAuras then return end
    local i = 1
    while true do
        local data = C_UnitAuras.GetDebuffDataByIndex(unit, i, filter)
        if not data then break end
        if fn(data) then return true end
        i = i + 1
    end
end

local function GetEclipseState()
    local solar, lunar = false, false
    ScanBuffs("player", function(d)
        if d.spellId == AURA_SOLAR then solar = true end
        if d.spellId == AURA_LUNAR then lunar = true end
    end)
    if solar and lunar then return "BOTH"
    elseif solar       then return "SOLAR"
    elseif lunar       then return "LUNAR"
    else                    return "NONE" end
end

local function GetDotOnTarget(spellID)
    local expiry, duration
    ScanDebuffs("target", "PLAYER", function(d)
        if d.spellId == spellID then
            expiry   = d.expirationTime
            duration = d.duration
            return true
        end
    end)
    return expiry, duration
end

local function IsPandemic(expiry, baseDuration)
    if not expiry or expiry == 0 then return false end
    return (expiry - GetTime()) <= (baseDuration * PANDEMIC_PCT)
end

local function GetCDRemaining(spellID)
    if not C_Spell then return nil end
    local data = C_Spell.GetSpellCooldown(spellID)
    if data and data.duration and data.duration > 1.5 then
        local remaining = (data.startTime + data.duration) - GetTime()
        return remaining > 0 and remaining or nil
    end
    return nil
end

-------------------------------------------------------------------------------
-- Suggestion engine
-------------------------------------------------------------------------------

local function GetSuggestion()
    -- 1. Missing DoTs (highest urgency)
    for _, dot in ipairs(DOTS) do
        if dot.id ~= 202347 or EclipseTunnellerDB.showStellarFlare then
            local expiry = st.dots[dot.id] and st.dots[dot.id].expiry or 0
            if expiry == 0 or (expiry - GetTime()) <= 0 then
                return string.format(SUGGEST.MISSING_DOT, dot.name)
            end
        end
    end
    -- 2. Major CD ready
    local caCD = GetCDRemaining(194223) or GetCDRemaining(102560)
    if not caCD and st.ap >= 50 then
        return string.format(SUGGEST.USE_CD, "Celestial Alignment")
    end
    -- 3. Pandemic refresh needed
    for _, dot in ipairs(DOTS) do
        if dot.id ~= 202347 or EclipseTunnellerDB.showStellarFlare then
            local d = st.dots[dot.id]
            if d and d.expiry > 0 and IsPandemic(d.expiry, d.duration or 16) then
                return string.format(SUGGEST.PANDEMIC_DOT, dot.name)
            end
        end
    end
    -- 4. Spend Astral Power
    if st.ap >= 90 then return SUGGEST.SPEND_AP end
    -- 5. Eclipse casts
    if     st.eclipse == "BOTH"  then return SUGGEST.BOTH
    elseif st.eclipse == "SOLAR" then return SUGGEST.SOLAR_CAST
    elseif st.eclipse == "LUNAR" then return SUGGEST.LUNAR_CAST
    else                              return SUGGEST.NO_ECLIPSE end
end

-------------------------------------------------------------------------------
-- UI construction
-------------------------------------------------------------------------------

local FRAME_W = 230
local FRAME_H = 148

local function MakeBar(parent, w, h)
    local bg = CreateFrame("Frame", nil, parent)
    bg:SetSize(w, h)
    local bgTex = bg:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(0.12, 0.12, 0.12, 1)
    local fill = bg:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", bg, "LEFT", 0, 0)
    fill:SetHeight(h)
    fill:SetWidth(1)
    local label = bg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetAllPoints()
    label:SetJustifyH("CENTER")
    return bg, fill, label
end

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
    f:SetBackdropColor(0.05, 0.05, 0.1, 0.88)
    f:SetBackdropBorderColor(0.4, 0.3, 0.6, 0.9)

    f:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" and not db.locked then self:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        local _, _, _, x, y = self:GetPoint()
        db.x, db.y = x, y
    end)

    -- ── Eclipse state label ──────────────────────────────────────────────────
    local eclipseLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    eclipseLabel:SetPoint("TOP", f, "TOP", 0, -8)
    eclipseLabel:SetText("NO ECLIPSE")
    eclipseLabel:SetTextColor(0.5, 0.5, 0.5, 1)
    f.eclipseLabel = eclipseLabel

    -- ── Suggestion text ──────────────────────────────────────────────────────
    local suggest = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    suggest:SetPoint("TOP", eclipseLabel, "BOTTOM", 0, -2)
    suggest:SetText("")
    f.suggest = suggest

    -- ── Astral Power bar ─────────────────────────────────────────────────────
    local apBg, apFill, apText = MakeBar(f, FRAME_W - 16, 14)
    apBg:SetPoint("TOP", suggest, "BOTTOM", 0, -3)
    apFill:SetColorTexture(0.55, 0.3, 1.0, 1)
    apText:SetTextColor(1, 1, 1, 1)
    f.apBg = apBg; f.apFill = apFill; f.apText = apText

    -- ── DoT bars ─────────────────────────────────────────────────────────────
    f.dotRows = {}
    for i, dot in ipairs(DOTS) do
        local bg, fill, label = MakeBar(f, FRAME_W - 16, 15)
        bg:SetPoint("TOP", (i == 1) and apBg or f.dotRows[i-1].bg, "BOTTOM", 0, -3)
        fill:SetColorTexture(dot.r, dot.g, dot.b, 1)
        label:SetText(dot.name)
        f.dotRows[i] = { bg=bg, fill=fill, label=label }
        bg:SetShown(i < 3 or db.showStellarFlare)
    end

    -- ── Cooldown icon row ─────────────────────────────────────────────────────
    local cdRow = CreateFrame("Frame", nil, f)
    cdRow:SetSize(FRAME_W - 16, 24)
    cdRow:SetPoint("BOTTOM", f, "BOTTOM", 0, 5)
    f.cdIcons = {}

    for i, cd in ipairs(CD_SPELLS) do
        local btn = CreateFrame("Frame", nil, cdRow)
        btn:SetSize(22, 22)
        btn:SetPoint("LEFT", cdRow, "LEFT", (i - 1) * 24, 0)

        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        local iconID = C_Spell.GetSpellTexture(cd.id)
        tex:SetTexture(iconID)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local dim = btn:CreateTexture(nil, "OVERLAY")
        dim:SetAllPoints()
        dim:SetColorTexture(0, 0, 0, 0.65)
        dim:Hide()

        local cdt = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        cdt:SetAllPoints()
        cdt:SetJustifyH("CENTER")
        cdt:SetText("")

        btn.tex = tex; btn.dim = dim; btn.cdt = cdt
        f.cdIcons[cd.id] = btn
    end

    ET.frame = f
end

-------------------------------------------------------------------------------
-- Per-element update functions
-------------------------------------------------------------------------------

local ECLIPSE_TEXT  = { SOLAR="SOLAR ECLIPSE", LUNAR="LUNAR ECLIPSE", BOTH="CELESTIAL", NONE="NO ECLIPSE" }
local ECLIPSE_COLOR = {
    SOLAR = {1.0, 0.78, 0.0},
    LUNAR = {0.45, 0.65, 1.0},
    BOTH  = {1.0, 1.0, 1.0},
    NONE  = {0.45, 0.45, 0.45},
}

local function UpdateEclipse()
    local f = ET.frame
    local e = st.eclipse
    f.eclipseLabel:SetText(ECLIPSE_TEXT[e])
    local c = ECLIPSE_COLOR[e]
    f.eclipseLabel:SetTextColor(c[1], c[2], c[3], 1)
end

local function UpdateAP()
    local f = ET.frame
    local db = EclipseTunnellerDB
    local pct = st.apMax > 0 and (st.ap / st.apMax) or 0
    local w = math.max(1, (FRAME_W - 16) * pct)
    f.apFill:SetWidth(w)
    f.apText:SetText("Astral Power  " .. st.ap .. " / " .. st.apMax)
    if st.ap >= 90 then
        f.apFill:SetColorTexture(1.0, 0.85, 0.0, 1)
        f.apText:SetTextColor(1.0, 0.95, 0.5, 1)
    else
        f.apFill:SetColorTexture(0.55, 0.3, 1.0, 1)
        f.apText:SetTextColor(0.9, 0.9, 0.9, 1)
    end
end

local function UpdateDots()
    local f = ET.frame
    local now = GetTime()
    local barW = FRAME_W - 16

    for i, dot in ipairs(DOTS) do
        local row = f.dotRows[i]
        if row.bg:IsShown() then
            local d = st.dots[dot.id]
            local expiry   = d and d.expiry   or 0
            local duration = d and d.duration or 16

            if expiry == 0 or (expiry - now) <= 0 then
                row.fill:SetWidth(1)
                row.label:SetText(dot.name .. "  MISSING")
                row.label:SetTextColor(1, 0.2, 0.2, 1)
                row.fill:SetColorTexture(0.6, 0.1, 0.1, 1)
            else
                local remaining = expiry - now
                local pct = math.min(remaining / duration, 1)
                row.fill:SetWidth(math.max(1, barW * pct))
                local pandemic = IsPandemic(expiry, duration)
                if pandemic then
                    row.fill:SetColorTexture(1.0, 0.75, 0.0, 1)
                    row.label:SetTextColor(1.0, 0.85, 0.0, 1)
                else
                    row.fill:SetColorTexture(dot.r, dot.g, dot.b, 1)
                    row.label:SetTextColor(0.9, 0.9, 0.9, 1)
                end
                row.label:SetText(dot.name .. "  " .. string.format("%.1fs", remaining))
            end
        end
    end
end

local function UpdateCDs()
    local f = ET.frame
    for _, cd in ipairs(CD_SPELLS) do
        local icon = f.cdIcons[cd.id]
        if icon then
            local remaining = GetCDRemaining(cd.id)
            if remaining then
                icon.dim:Show()
                icon.tex:SetDesaturated(true)
                icon.cdt:SetText(remaining >= 60
                    and string.format("%dm", math.ceil(remaining / 60))
                    or  string.format("%d", math.ceil(remaining)))
            else
                icon.dim:Hide()
                icon.tex:SetDesaturated(false)
                icon.cdt:SetText("")
            end
        end
    end
end

local function UpdateSuggest()
    if not ET.frame then return end
    ET.frame.suggest:SetText(st.inCombat and GetSuggestion() or "")
end

-------------------------------------------------------------------------------
-- Full update
-------------------------------------------------------------------------------

local function FullUpdate()
    if not ET.frame then return end

    -- Eclipse
    st.eclipse = GetEclipseState()

    -- Astral Power
    st.ap    = UnitPower("player",    ASTRAL_POWER_TYPE)
    st.apMax = UnitPowerMax("player", ASTRAL_POWER_TYPE)

    -- DoTs
    local hasTarget = UnitExists("target") and not UnitIsDeadOrGhost("target")
    for _, dot in ipairs(DOTS) do
        if hasTarget then
            local expiry, duration = GetDotOnTarget(dot.id)
            st.dots[dot.id] = { expiry = expiry or 0, duration = duration or 16 }
        else
            st.dots[dot.id] = { expiry = 0, duration = 16 }
        end
    end

    UpdateEclipse()
    UpdateAP()
    UpdateDots()
    UpdateCDs()
    UpdateSuggest()

    -- Show/hide
    local db = EclipseTunnellerDB
    ET.frame:SetShown(st.isBalance and (st.inCombat or db.showOutOfCombat))
end

-------------------------------------------------------------------------------
-- Ticker
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
-- Event handling
-------------------------------------------------------------------------------

local function CheckSpec()
    local _, classFile = UnitClass("player")
    local specIndex = GetSpecialization()
    st.isBalance = (classFile == "DRUID") and (specIndex == 1)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
events:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("UNIT_POWER_UPDATE")
events:RegisterEvent("UNIT_TARGET")

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        if not EclipseTunnellerDB then
            EclipseTunnellerDB = CopyTable(DEFAULTS)
        end
        for k, v in pairs(DEFAULTS) do
            if EclipseTunnellerDB[k] == nil then EclipseTunnellerDB[k] = v end
        end

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

    elseif event == "UNIT_AURA" and arg1 == "player" then
        st.eclipse = GetEclipseState()
        if ET.frame then UpdateEclipse(); UpdateSuggest() end

    elseif event == "UNIT_POWER_UPDATE" and arg1 == "player" then
        st.ap    = UnitPower("player", ASTRAL_POWER_TYPE)
        st.apMax = UnitPowerMax("player", ASTRAL_POWER_TYPE)
        if ET.frame then UpdateAP(); UpdateSuggest() end

    elseif event == "UNIT_TARGET" and arg1 == "player" then
        FullUpdate()
    end
end)

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------

SLASH_ET1 = "/et"
SlashCmdList["ET"] = function(msg)
    msg = strtrim(msg):lower()
    if msg == "lock" then
        EclipseTunnellerDB.locked = true
        print("|cFF54a3ffEclipseTunneller:|r Locked.")
    elseif msg == "unlock" then
        EclipseTunnellerDB.locked = false
        print("|cFF54a3ffEclipseTunneller:|r Unlocked — drag to reposition.")
    elseif msg == "combat" then
        EclipseTunnellerDB.showOutOfCombat = not EclipseTunnellerDB.showOutOfCombat
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
    else
        print("|cFF54a3ffEclipseTunneller|r — Balance Druid Eclipse HUD")
        print("  /et            toggle visibility")
        print("  /et lock       lock frame")
        print("  /et unlock     unlock frame (drag to move)")
        print("  /et combat     toggle out-of-combat display")
        print("  /et stellar    toggle Stellar Flare DoT row")
        print("  /et reset      reset frame position")
    end
end
