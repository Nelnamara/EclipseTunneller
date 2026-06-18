# EclipseTunneller — CLAUDE.md

Balance Druid **Eclipse HUD** for WoW Midnight (12.x). Author: Nelnamara.
Shows Eclipse state, DoT timers, Astral Power, a cast suggestion, and a minimap button.
Auto-shows in combat (or always, if `showOutOfCombat`).

## Files
- `EclipseTunneller.lua` — single-file addon.

## Key notes
- `ET` is the addon table; `BuildUI()` / `BuildMinimapButton()` are **local** functions and must be defined **before** the `ev:SetScript("OnEvent", ...)` closure so they're captured as upvalues.
- Frame visibility is auto-managed (`st.isBalance and (st.inCombat or db.showOutOfCombat)`), so the minimap button toggles `showOutOfCombat` (via the slash) rather than hard-toggling the frame.
- Eclipse spells: Solar `1233346`, Lunar `1233272` (verify cast names in-game).
- Celestial Alignment `194223` / Incarnation `102560` drive the CA suggestion (logic was once inverted — suggest CA when one is **ready**, i.e. `cdReady[CA] or cdReady[Inc]`).

## Slash
`/et` (toggle HUD / `showOutOfCombat`) · `lock`/`unlock` · `combat` · `stellar` · `reset`

## Build / release / deploy
- BigWigs packager on **`v*` tag push**. CurseForge secret: **`CURSFORGE_API_KEY`** (misspelled, leave as-is).
- Local test: copy to `D:\World of Warcraft\_retail_\Interface\AddOns\EclipseTunneller\`.
- Current version: **1.0.2** (Interface 120007).

## Conventions
- **Never** append a `Co-Authored-By` trailer to commits.
