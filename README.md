# Blindfold

A screen-reader accessibility mod for **Balatro**, built on the
[Lovely Injector](https://github.com/ethangreen-dev/lovely-injector) only (no
Steamodded). The mod owns its own keyboard-driven UI: game screens are
re-presented as navigable rows of spoken controls (an overlay "key graph",
after Factorio Access), and the mod drives the game's own functions to act.
Screens not yet owned fall back to speaking the game's native focus.

What works today:
- **The play screen is mod-owned**: jokers / consumables / played / hand as
  predictable rows plus a button row; select, pick-up/place reordering (jokers
  and hand — scoring order is left-to-right), sell / use, play / discard with
  proper guards and spoken feedback.
- **Speech via Tolk** (LuaJIT FFI), with a log fallback when Tolk isn't present.
- **Menus are mod-owned via a generic mirror**: the main menu, run setup (New
  Run / Continue / Challenges), the whole Options tree, run info, and deck view
  are re-presented as one flat vertical list in reading order — up/down moves,
  Enter activates, left/right adjusts the focused slider / cycle / tab. Values,
  tooltips, and inline option-info are spoken as before.
- **Cards**: playing cards (rank + suit, plus enhancement / edition / seal /
  debuff) and jokers / consumables (name + kind + edition, then the full ability
  description). **Review buffers** (Ctrl+arrows) hold the full detail.
- **Announcements**: scoring play-by-play, plays/discards with counts, shop
  prices, blind select, cash-out breakdown, screen changes — with per-
  announcement toggles in a native settings tab (Options → Blindfold).
- **Localization** layer with game-language detection and English fallback.

## Layout

```
src/            the mod itself (this folder is what gets linked into Mods/)
  lovely.toml   Lovely patches: register modules + boot after the Controller exists
  core.lua      entry point: hooks, per-frame tick, overlay/input wiring
  speech.lua    Tolk (FFI) speech with a log fallback
  overlay/      the owned-UI framework: key graph, builder, dispatcher,
                message builder (port of Tanglebeep / Factorio Access)
  overlays/     one module per owned screen (play.lua so far)
  ui/           proxy elements + announcement system for the native-focus
                fallback (ported from SayTheSpire2); also labels overlay cards
  buffers/      review cursors (game status + per-entity detail, Ctrl+arrows)
  events/       spoken game events: scoring sequence, plays/discards, cash-out
  input/        rebindable InputActions (keyboard-first; persisted rebinds)
  settings/     settings registry + the native Blindfold tab in Options
  loc/          localization manager + per-language string tables (en.lua)
  lib/          drop the x64 Tolk DLLs here (gitignored) — see lib/README.md
scripts/
  deploy.ps1    junctions src/ into %APPDATA%/Balatro/Mods/Blindfold
game_src/       extracted Balatro Lua, REFERENCE ONLY (gitignored)
```

## Setup

1. **Install Lovely Injector** (latest x64 release): drop its `version.dll` next
   to `Balatro.exe` in
   `C:\Program Files (x86)\Steam\steamapps\common\Balatro\`.
   https://github.com/ethangreen-dev/lovely-injector/releases
2. **(Optional, for speech)** Put the x64 `Tolk.dll` + screen-reader client DLLs
   in `src/lib/` — see `src/lib/README.md`. Skip this and the mod still logs
   every announcement.
3. **Deploy:** run `scripts/deploy.ps1` (junctions `src/` into the Mods folder).
4. **Launch Balatro.** You should hear / see "Blindfold loaded."

## Controls

Keyboard-first, one key one meaning, all rebindable in the Keybindings screen
(Options → Blindfold → Keybindings).

| Key | Action |
| --- | --- |
| Arrow keys | Move (mod-owned screens navigate by rows; sliders/cycles adjust) |
| Home / End | Jump to the start / end of the row |
| Enter | Select a card / activate a button |
| Space | Pick up / place (reorder jokers or hand cards; hands score left-to-right) |
| X / C | Play hand / Discard |
| S / U | Sell / Use the focused joker or consumable |
| `[` / `]` | Previous / next tab (menus) |
| Q | View deck |
| Tab | Run info |
| Backspace or Shift | Back / deselect all |
| Ctrl + arrows | Review buffers: Left/Right switch buffer, Up/Down browse |
| Escape | (unchanged — game's pause / back) |
| F8 | Debug: dump the owned overlay graph (or the focused UI tree) to the log |

## Verifying without a screen reader

Every announcement is appended to `%APPDATA%/Balatro/blindfold.log`. Tail it
while navigating to confirm announcements are firing:

```powershell
Get-Content "$env:APPDATA\Balatro\blindfold.log" -Wait -Tail 20
```

## Re-extracting game source

`game_src/` is the game's Lua, used as reference. It's a zip appended to
`Balatro.exe`; re-extract anytime with 7-Zip (`7z x Balatro.exe -ogame_src -ir!*.lua`).
