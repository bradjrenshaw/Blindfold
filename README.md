# balatro-access

A screen-reader accessibility mod for **Balatro**, built on the
[Lovely Injector](https://github.com/ethangreen-dev/lovely-injector) only (no
Steamodded). It re-enables keyboard-driven focus navigation (which the release
build disables) and speaks the focused element via a screen reader.

Status: **skeleton** — proves the stack end to end (Lovely boot → Tolk speech →
keyboard-driven focus navigation → focus announcements). Real text extraction
and the non-focusable HUD readouts come next.

## Layout

```
src/            the mod itself (this folder is what gets linked into Mods/)
  lovely.toml   Lovely patches: register modules + boot after the Controller exists
  core.lua      entry point: installs the focus + keyboard hooks
  speech.lua    Tolk (FFI) speech with a log fallback
  lib/          drop the x64 Tolk DLLs here (gitignored) — see lib/README.md
scripts/
  deploy.ps1    junctions src/ into %APPDATA%/Balatro/Mods/balatro-access
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
4. **Launch Balatro.** You should hear / see "Balatro Access loaded."

## Controls (skeleton)

| Key | Action |
| --- | --- |
| Arrow keys | Move focus (drives the game's native focus navigation) |
| Enter | Select / activate focused element |
| Backspace | Cancel / deselect |
| Escape | (unchanged — game's pause / back) |

## Verifying without a screen reader

Every announcement is appended to `%APPDATA%/Balatro/balatro-access.log`. Tail
it while navigating the main menu to confirm focus changes are firing:

```powershell
Get-Content "$env:APPDATA\Balatro\balatro-access.log" -Wait -Tail 20
```

## Re-extracting game source

`game_src/` is the game's Lua, used as reference. It's a zip appended to
`Balatro.exe`; re-extract anytime with 7-Zip (`7z x Balatro.exe -ogame_src -ir!*.lua`).
