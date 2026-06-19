# EclipseTunneller — CLAUDE.md

Balance Druid **Eclipse HUD** for WoW Midnight (12.x). Author: Nelnamara.
Shows Eclipse state, DoT timers, Astral Power, a cast suggestion, and a minimap button.
Auto-shows in combat (or always, if `showOutOfCombat`).

## Files
- `EclipseTunneller.lua` — single-file addon.

## Key notes
- `ET` is the addon table; `BuildUI()` / `BuildMinimapButton()` are **local** functions and must be defined **before** the `ev:SetScript("OnEvent", ...)` closure so they're captured as upvalues.
- Frame visibility is auto-managed (`st.isBalance and (st.inCombat or db.showOutOfCombat)`), so the minimap button toggles `showOutOfCombat` (via the slash) rather than hard-toggling the frame.
- Eclipse detection uses the **buff** IDs `1233346` (Solar Eclipse) / `1233272` (Lunar Eclipse) via `C_UnitAuras.GetPlayerAuraBySpellID`. Midnight 12.0.7 reworked Eclipse into an activated 15s buff; old 48517/48518 (Legion) showed "NO ECLIPSE".
- Celestial Alignment `194223` / Incarnation `102560` drive the CA suggestion (logic was once inverted — suggest CA when one is **ready**, i.e. `cdReady[CA] or cdReady[Inc]`).
- **DoT tracking is event-driven** (UNIT_SPELLCAST_SUCCEEDED on `"player"`, spellID non-secret there): casting Moonfire `8921` / Sunfire `93402` / Stellar Flare `202347` records `GetTime()+baseDuration`; `PLAYER_TARGET_CHANGED` clears. **Do NOT use `AuraUtil.FindAuraByName`** — its `GetAuraDataBySpellName` was removed in 12.0.7 (166× "call a nil value" crash), and scanning by `aura.spellId`/`.name` is blocked (secret). Timers are approximate (no haste scaling).

## Slash
`/et` (toggle HUD / `showOutOfCombat`) · `lock`/`unlock` · `combat` · `stellar` · `reset`

## Build / release / deploy
- BigWigs packager on **`v*` tag push**. CurseForge secret: **`CURSFORGE_API_KEY`** (misspelled, leave as-is).
- Local test: copy to `D:\World of Warcraft\_retail_\Interface\AddOns\EclipseTunneller\`.
- Current version: **1.0.3** (Interface 120007) — pending tag (Eclipse-aura + DoT-crash fixes).

## Conventions
- **Never** append a `Co-Authored-By` trailer to commits.
