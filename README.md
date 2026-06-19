# EclipseTunneller

> **WoW:** 12.0.7+ (Midnight) · **Author:** Nelnamara · **Spec:** Balance Druid

A compact, focused HUD for Balance Druids in World of Warcraft: Midnight. Shows Eclipse state, Astral Power, DoT timers with pandemic windows, major cooldown icons, and a context-aware cast suggestion — all in one glanceable frame.

Built from the ground up for Midnight's secret-value API restrictions. No arithmetic on restricted power or cooldown values, no `COMBAT_LOG_EVENT_UNFILTERED` dependency.

---

## Features

- **Eclipse state** — Solar / Lunar / Celestial displayed in spec colors with a live window timer. In Midnight, Eclipse is an *activated* 15s buff (Wrath → Solar, Starfire → Lunar); Celestial Alignment (15s) and Incarnation: Chosen of Elune (20s) light up **both** eclipses (shown as CELESTIAL)
- **Astral Power bar** — live display using Midnight-safe `StatusBar:SetValue` pattern; turns gold at 90+ to signal a spend window
- **DoT timers** — Moonfire and Sunfire remaining duration tracked from your own casts (event-driven, name-matched) with pandemic refresh highlighting
- **Stellar Flare row** — optional third DoT bar (toggle with `/et stellar`)
- **Cooldown icon row** — Celestial Alignment, Incarnation, Fury of Elune, Convoke, Warrior of Elune, Wild Mushroom, Starsurge, Starfall
- **Cast suggestion** — priority-based text hint for your next action
- **Spec-aware** — only appears when you are Balance spec
- **Combat-aware** — hides when out of combat by default (toggle with `/et combat`)
- **Minimap button** — toggle out-of-combat visibility from the minimap, with a matching AddOns-list icon

---

## Requirements

- WoW Midnight 12.0.7+
- No library dependencies

---

## Installation

1. Download the latest release zip from CurseForge
2. Extract to `World of Warcraft\_retail_\Interface\AddOns\`
3. Folder must be named **`EclipseTunneller`**
4. Log in on a Balance Druid — the HUD appears automatically on entering combat

---

## Usage

### Slash Commands

- **`/et`** — Toggle out-of-combat visibility
- **`/et lock`** / **`/et unlock`** — Lock/unlock the frame (drag to move)
- **`/et combat`** — Toggle out-of-combat display
- **`/et stellar`** — Toggle the Stellar Flare DoT row
- **`/et reset`** — Reset frame position to default
- **`/et debug`** — Print current Eclipse state and DoT timers to chat

---

## Compatibility / Midnight Notes

WoW Midnight introduced secret-value restrictions on many API return values. EclipseTunneller is fully compliant:

- Astral Power is displayed via `StatusBar:SetValue()` — no arithmetic performed on the restricted value
- **DoTs and Eclipse are tracked event-driven from your own casts**, not by scanning auras. `aura.spellId`/`.name` are secret even on the player, and `AuraUtil.FindAuraByName`'s name lookup was removed in 12.0.7. Casting a DoT records `GetTime() + baseDuration`; casting an Eclipse activation opens its window
- DoTs and Eclipse are matched by **spell name**, not ID — Midnight uses override spell IDs (Moonfire casts as `1269918`, not `8921`) and hero specs vary, so name-matching is the stable key
- Cooldown frames use anonymous `pcall` closures around `SetCooldown()` for secret startTime/duration values
- No `COMBAT_LOG_EVENT_UNFILTERED` dependency — tracking rides `UNIT_SPELLCAST_SUCCEEDED` on the `player` token (where `spellID` is non-secret) plus `UNIT_POWER_UPDATE`

---

## Changelog

### v1.0.4
- Celestial Alignment (15s) and Incarnation: Chosen of Elune (20s) now register as CELESTIAL — both eclipses active — with the window timer shown in the readout

### v1.0.3
- **Eclipse detection reworked for Midnight** — Eclipse is now an activated buff (IDs `1233346` Solar / `1233272` Lunar). The buff aura wasn't reliably readable, so the HUD now records a window on the activation cast, matched by name to survive hero-spec variants (some remove Solar) and override IDs. Old Legion IDs (`48517`/`48518`, `164547`/`164812`) do nothing on 12.0.7
- **DoT detection reworked** — fixed a 166× crash from `AuraUtil.FindAuraByName` (`GetAuraDataBySpellName` was removed in 12.0.7); DoTs are now tracked event-driven from player casts and matched by spell name (Midnight override IDs broke ID matching)

### v1.0.2
- Minimap button artwork; standard 24px size

### v1.0.1
- Minimap button and AddOns-list icon (addon artwork)
- Interface bumped to 120007
- Fixed an inverted Celestial Alignment suggestion (suggest CA when it's *ready*)

### v1.0.0
- Initial release: Eclipse HUD with AP bar, DoT timers, CD icons, cast suggestion
- Full Midnight 12.0.7 compatibility

---

## Roadmap

<details>
<summary>Planned</summary>

- **Major-cooldown active display** — surface "majors active" with a timer in the larger readout space
- **Per-hero-spec suggestions** — tailor the cast hint to the active hero tree (e.g. specs that drop Solar Eclipse)
- **Haste-scaled DoT timers** — refine the event-driven durations once haste is readable safely
- **Configurable cooldown row** — choose which majors appear

</details>

---

## Feature Requests

<details>
<summary>How to request</summary>

Open an issue on [GitHub](https://github.com/Nelnamara/EclipseTunneller/issues) or leave a CurseForge comment.

</details>

---

## License

All Rights Reserved. Author: Nelnamara · [CurseForge](https://www.curseforge.com/wow/addons/eclipsetunneller) · [GitHub](https://github.com/Nelnamara/EclipseTunneller)
