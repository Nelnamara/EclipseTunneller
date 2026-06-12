# EclipseTunneller

> **WoW:** 12.0.x (Midnight) · **Author:** Nelnamara · **Spec:** Balance Druid

A compact, focused HUD for Balance Druids. Shows Eclipse state, Astral Power, DoT timers with pandemic windows, major cooldown icons, and a context-aware cast suggestion — all in one glanceable frame.

---

## Features

- **Eclipse state** — Solar / Lunar / Celestial Alignment displayed in spec colors
- **Astral Power bar** — turns gold at 90+ to signal spend window
- **DoT timers** — Moonfire and Sunfire bars with pandemic refresh highlighting
- **Stellar Flare row** — optional third DoT bar (`/et stellar`)
- **Cooldown icon row** — Celestial Alignment, Incarnation, Fury of Elune, Convoke, Warrior of Elune, Wild Mushroom, Starsurge, Starfall
- **Cast suggestion** — priority-based text hint for your next action
- **Spec-aware** — only appears when you are Balance spec
- **Combat-aware** — hides when out of combat by default (toggle with `/et combat`)

---

## Slash Commands

| Command | Description |
|---|---|
| `/et` | Toggle visibility |
| `/et lock` | Lock frame position |
| `/et unlock` | Unlock frame (drag to move) |
| `/et combat` | Toggle out-of-combat display |
| `/et stellar` | Toggle Stellar Flare DoT row |
| `/et reset` | Reset frame position to default |

---

## Installation

1. Download the latest release zip
2. Extract to `World of Warcraft\_retail_\Interface\AddOns\`
3. Folder must be named **`EclipseTunneller`**
4. Log in on a Balance Druid — the HUD appears automatically on entering combat

---

## Changelog

### v1.0.0
- Initial release: Eclipse HUD with AP bar, DoT timers, CD icons, cast suggestion

---

## License

Personal use. Author: Nelnamara.
