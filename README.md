# Blindfold

A screen-reader accessibility mod for **Balatro**, built on the
[Lovely Injector](https://github.com/ethangreen-dev/lovely-injector) only (no
Steamodded). It re-enables keyboard-driven focus navigation (which the release
build disables) and speaks the focused element via a screen reader.

What works today:
- **Keyboard navigation** of the game's native focus system, with mouse-mode
  lockout so focus stays put.
- **Speech via Tolk** (LuaJIT FFI), with a log fallback when Tolk isn't present.
- **Menus**: buttons, sliders, cycles, checkboxes, tabs — with their current
  value spoken, and announced again when you change it. Control tooltips and
  inline option-info are read too.
- **Cards**: playing cards (rank + suit, plus enhancement / edition / seal /
  debuff) and jokers / consumables (name + kind + edition, then the full ability
  description).
- **Localization** layer with game-language detection and English fallback.

## Layout

```
src/            the mod itself (this folder is what gets linked into Mods/)
  lovely.toml   Lovely patches: register modules + boot after the Controller exists
  core.lua      entry point: keyboard + focus hooks, the per-frame focus tick
  speech.lua    Tolk (FFI) speech with a log fallback
  loc/          localization manager + per-language string tables (en.lua)
  ui/           proxy elements + announcement system (ported from SayTheSpire2)
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

| Key | Action |
| --- | --- |
| Arrow keys | Move focus / adjust the focused slider, cycle, or tab |
| Enter | Select / activate focused element |
| Backspace | Cancel / deselect |
| Escape | (unchanged — game's pause / back) |
| F8 | Debug: dump the focused control's UI tree to the log |

## Verifying without a screen reader

Every announcement is appended to `%APPDATA%/Balatro/blindfold.log`. Tail it
while navigating to confirm announcements are firing:

```powershell
Get-Content "$env:APPDATA\Balatro\blindfold.log" -Wait -Tail 20
```

## Re-extracting game source

`game_src/` is the game's Lua, used as reference. It's a zip appended to
`Balatro.exe`; re-extract anytime with 7-Zip (`7z x Balatro.exe -ogame_src -ir!*.lua`).
