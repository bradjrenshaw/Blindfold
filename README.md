# Blindfold

An accessibility mod for **Balatro** that provides screen reader support for
blind players. 

For discussion of Blindfold, as well as my other modding projects, I have a
[Discord](https://discord.gg/Dz8u2Pr9py/).

If you would like to support my modding work, I also have a
[Patreon](https://www.patreon.com/bradjrenshaw/).

## Features

- Screenreader output for all game screens and events
- Full keyboard and controller support, all rebindable
- Play-by-play scoring announcements, with per-announcement toggles
- Status hotkeys for the numbers you need mid-hand (hands, discards, score,
  money, joker slots)
- Review buffers for re-reading detail at your own pace
- Translations for all of Balatro's languages

## Installation

### Windows
1. Download `BlindfoldInstaller.exe` from the
   [latest release](https://github.com/bradjrenshaw/Blindfold/releases/latest).
2. Run it. It finds your Steam install of Balatro automatically (use
   Browse... if you keep the game somewhere unusual) and shows one row of
   buttons: press **Install**.

   Windows SmartScreen may warn about an unrecognized app the first time:
   choose "More info", then "Run anyway".
3. Launch Balatro through Steam. You should hear **"Blindfold loaded."**

Prefer a console? Run `BlindfoldInstaller.exe --cli` for the same flows as a
menu.

### macOS
1. Download `BlindfoldInstaller.app.zip` (extracting it to get `BlindfoldInstaller.app`) from the
   [latest release](https://github.com/bradjrenshaw/Blindfold/releases/latest).
2. Run it. It finds your Steam install of Balatro automatically and shows one row of
   buttons: press **Install**.
3. Launch Balatro through Steam. You should hear **"Blindfold loaded."**

Prefer a console? Run `./BlindfoldInstaller.app/Contents/MacOS/blindfold-installer --cli` for the same flows as a menu.

**Updating:** run the installer again. It tells you when a newer version is
out and the Install/Update button adjusts. "Install dev build" instead
installs the very latest work-in-progress code from this repository.

### Manual installation

Prefer to place files yourself? Each release also ships `Blindfold.zip`
(this README is included in it):

1. **Copy Injector Files**:
   * **Windows**: Copy `version.dll` from the zip into Balatro's game folder, next to `Balatro.exe` (Steam: right-click Balatro → Manage → Browse local files).
   * **macOS**: Copy `liblovely.dylib` and `run_lovely_macos.sh` from the zip into Balatro's game folder, next to `Balatro.app`.
   This is the [Lovely Injector](https://github.com/ethangreen-dev/lovely-injector) mod loader — skip it if you already run other Lovely mods.
2. **Copy Mod Payload**:
   * **Windows**: Copy the zip's `Blindfold` folder (excluding `lib/libprism.dylib` which is Mac-only) into `%APPDATA%\Balatro\Mods`, so it ends up at `%APPDATA%\Balatro\Mods\Blindfold` (create `Mods` if it doesn't exist yet).
   * **macOS**: Copy the zip's `Blindfold` folder (excluding `lib/prism.dll` which is Windows-only) into `~/Library/Application Support/Balatro/Mods`, so it ends up at `~/Library/Application Support/Balatro/Mods/Blindfold` (create `Mods` if it doesn't exist yet).
3. Launch Balatro through Steam.

To update manually, delete the `Blindfold` folder under `Mods` and copy in the new zip's folder — settings live outside it and survive. To uninstall manually, delete the `Blindfold` folder under `Mods` and the injector files.

**Uninstalling:** the installer's Uninstall button removes the mod and
offers to also remove the Lovely Injector and Blindfold's settings. Your
game saves are never touched.

## Getting started

Start Balatro through Steam and wait for "Blindfold loaded." From there:

- **Arrow keys** (or d-pad / left stick) move between controls; each speaks
  as you land on it. Screens are laid out as rows: up/down switches rows,
  left/right moves within one.
- **Enter** (or A) activates the focused control.
- The **play screen** reads top to bottom: your jokers and consumables, the
  blind, played cards, your hand, then the action buttons. Select cards in
  your hand with Enter (controller A), then press **X to play** or **C to
  discard** (controller X / Y).
- **Space** (controller LT + A) picks up the focused card so you can
  reorder: move to where it should go and press it again to place ("place
  between X and Y" tells you where a drop lands). Works on jokers,
  consumables, and hand cards — hands score left to right.
- **S sells / U uses** the focused joker or consumable (controller LB / RB).
- **Status chords** answer the common questions instantly: hands left
  (Ctrl+X, controller LT+X), discards left (Ctrl+C, LT+Y), score and goal
  (Ctrl+S, LT+B), money (Ctrl+M, RT+X), joker slots (Ctrl+J, RT+Y).
- **Ctrl+arrows** (controller right stick) open the review buffers:
  Left/Right switch buffers (game status, card detail), Up/Down step through
  their lines — for re-reading anything at your own pace.
- Announcement toggles, speech options, and rebinding all live in
  **Options → Blindfold**.

## Controls

Everything is rebindable in Options → Blindfold → Keybindings.

| Action | Keyboard | Controller |
| --- | --- | --- |
| Move (sliders and tab strips adjust with left/right) | Arrow keys | D-pad or left stick |
| Jump to the start / end of the current row | Home / End | — |
| Select a card / activate a button (on a joker or consumable: pick up / place) | Enter | A |
| Pick up / place (reorder jokers, consumables, or hand cards) | Space | LT + A |
| Play hand | X | X |
| Discard | C | Y |
| Sell the focused joker or consumable | S | LB |
| Use the focused consumable | U | RB |
| Previous / next tab (menus) | `[` / `]` | left/right on the tab strip |
| View deck | D | RT + RB |
| Run info | Tab | Back, or LT + LB |
| Back / deselect all | Backspace or Shift | B |
| Pause / game menu | Escape (left native) | Start |
| Review buffers (switch buffer / browse its lines) | Ctrl + Left/Right, Ctrl + Up/Down | Right stick |
| Read hands remaining | Ctrl + X | LT + X |
| Read discards remaining | Ctrl + C | LT + Y |
| Read score and goal (e.g. "3000 of 80000") | Ctrl + S | LT + B |
| Read money | Ctrl + M | RT + X |
| Read joker slots (e.g. "3 of 5 jokers") | Ctrl + J | RT + Y |
| Debug: dump the current screen's controls to the log | F8 | — |

## Languages

The mod follows the game's language setting and ships translations for all
of Balatro's languages (German, French, Spanish, Italian, Portuguese,
Dutch, Polish, Russian, Japanese, Korean, Chinese, Indonesian). These are machine translations, so please let me know if anything is incorrect.

## Credits
I would like to thank Rashad Naqeeb for inspiring this project (you knew what you were doing when you put the idea in my head.) I would like to thank Rashad Naqeeb, Aaron Ramirez, and Austin Hicks for early testing.

I would also like to thank my Patreon supporters:
* Ahmad Abukhdair
* Alex19EP
* Chris Shaw
* Garrett Burgess
* Nancy Feldman
* rashad naqeeb
* Todd Shaughnessy