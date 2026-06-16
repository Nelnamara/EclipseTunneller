# EclipseTunneller

> **WoW:** 12.0.7+ (Midnight) · **Author:** Nelnamara · **Spec:** Balance Druid

A compact, focused HUD for Balance Druids in World of Warcraft: Midnight. Shows Eclipse state, Astral Power, DoT timers with pandemic windows, major cooldown icons, and a context-aware cast suggestion — all in one glanceable frame.

Built from the ground up for Midnight's secret-value API restrictions. No arithmetic on restricted power or cooldown values, no `COMBAT_LOG_EVENT_UNFILTERED` dependency.

---

## Features

- **Eclipse state** — Solar / Lunar / Celestial Alignment displayed in spec colors
- **Astral Power bar** — live display using Midnight-safe `StatusBar:SetValue` pattern; turns gold at 90+ to signal a spend window
- **DoT timers** — Moonfire and Sunfire remaining duration tracked via `UNIT_AURA` events with pandemic refresh highlighting
- **Stellar Flare row** — optional third DoT bar (toggle with `/et stellar`)
- **Cooldown icon row** — Celestial Alignment, Incarnation, Fury of Elune, Convoke, Warrior of Elune, Wild Mushroom, Starsurge, Starfall
- **Cast suggestion** — priority-based text hint for your next action
- **Spec-aware** — only appears when you are Balance spec
- **Combat-aware** — hides when out of combat by default (toggle with `/et combat`)

---

## Slash Commands

| Command | Description |
|---|---|
| `/et` | Toggle out-of-combat visibility |
| `/et lock` | Lock frame position |
| `/et unlock` | Unlock frame (drag to move) |
| `/et combat` | Toggle out-of-combat display |
| `/et stellar` | Toggle Stellar Flare DoT row |
| `/et reset` | Reset frame position to default |
| `/et debug` | Print current Eclipse state and DoT timers to chat |

---

## Installation

1. Download the latest release zip from CurseForge
2. Extract to `World of Warcraft\_retail_\Interface\AddOns\`
3. Folder must be named **`EclipseTunneller`**
4. Log in on a Balance Druid — the HUD appears automatically on entering combat

---

## Midnight Compatibility Notes

WoW Midnight introduced secret-value restrictions on many API return values. EclipseTunneller is fully compliant:

- Astral Power is displayed via `StatusBar:SetValue()` — no arithmetic performed on the restricted value
- DoT expiry is computed as `GetTime() + aura.duration` rather than reading the secret `expirationTime` field
- Cooldown frames use anonymous `pcall` closures around `SetCooldown()` for secret startTime/duration values
- All event handling uses the modern `UNIT_AURA` and `UNIT_POWER_UPDATE` event API

---

## Changelog

### v1.0.0
- Initial release: Eclipse HUD with AP bar, DoT timers, CD icons, cast suggestion
- Full Midnight 12.0.7 compatibility

---

## License

All Rights Reserved. Author: Nelnamara · [CurseForge](https://www.curseforge.com/wow/addons/eclipsetunneller) · [GitHub](https://github.com/Nelnamara/EclipseTunneller)
