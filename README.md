# Blindfold

An accessibility mod for **Balatro** that provides screen reader support for
blind players. 

For discussion of Blindfold, as well as my other modding projects, I have a
[Discord](https://discord.gg/Dz8u2Pr9py).

If you would like to support my modding work, I also have a
[Patreon](https://www.patreon.com/bradjrenshaw).

## Features

- Screenreader output for all game screens and events
- Full keyboard and controller support, all rebindable
- Play-by-play scoring announcements, with per-announcement toggles
- Status hotkeys for the numbers you need mid-hand (hands, discards, score,
  money, joker slots)
- Review buffers for re-reading detail at your own pace
- Translations for all of Balatro's languages

## Installation

The Blindfold Installer is [Loadstone](https://github.com/bradjrenshaw/loadstone)
set up for Blindfold alone. It installs the mod and the Lovely Injector mod
loader it needs, updates both, changes Blindfold's settings, and launches the
game.

### Windows
1. Download `BlindfoldInstaller.exe` from the
   [latest release](https://github.com/bradjrenshaw/Blindfold/releases/latest).
2. Run it. It finds your Steam install of Balatro automatically (use
   Browse... if you keep the game somewhere unusual): press **Install**.

   Windows SmartScreen may warn about an unrecognized app the first time:
   choose "More info", then "Run anyway".
3. Press **Launch game**, or launch Balatro through Steam as usual. You should
   hear **"Blindfold loaded."**

### macOS
1. Download `BlindfoldInstaller.dmg` from the
   [latest release](https://github.com/bradjrenshaw/Blindfold/releases/latest)
   and open it. It holds **Blindfold Installer** and a shortcut to your
   **Applications** folder.
2. Copy Blindfold Installer into Applications: drag it onto the shortcut, or
   select it, press Command-C, open Applications, and press Command-V. Then
   eject the disk image. (Run from Applications, the installer can also
   update itself.)
3. Open Blindfold Installer from Applications. The first time, macOS says it
   can't verify the developer: choose **Done**, then open System Settings →
   Privacy & Security, and under Security press **Open Anyway** next to
   "Blindfold Installer". (Or right-click the app → Open.)
4. It finds your Steam install of Balatro automatically: press **Install**.
5. Make sure Steam is running, then press **Launch game**. You should hear
   **"Blindfold loaded."**

#### Launching on macOS

Lovely injects itself with `DYLD_INSERT_LIBRARIES`, which Steam does not set
on its own, so a stock Steam launch loads Balatro without any mods.

The installer's **Launch game** button handles this for you: it starts the
game with Lovely loaded while Steam is running (achievements work; Balatro
won't start without Steam). To launch from Steam itself, and get the Steam
overlay, point Steam at the `steam_lovely_macos.sh` script the installer puts
in the game folder:

1. Steam → right-click **Balatro** → **Properties** → **General**.
2. Set **Launch Options** to the full path of that script followed by
   `%command%`, keeping the quotes (the path contains spaces) and writing the
   path out literally rather than using `~` or `$HOME`:

   ```
   "/Users/YOURNAME/Library/Application Support/Steam/steamapps/common/Balatro/steam_lovely_macos.sh" %command%
   ```
3. Launch from Steam as usual. Once this is set, the installer's **Launch
   game** button goes through Steam too.

Do **not** put `DYLD_INSERT_LIBRARIES=... %command%` in Launch Options
directly. Steam does not parse that string with a shell, so it tries to run a
program by that literal name and fails with *"Failed to start process for
this game : OS Error 260"*.

**Updating:** open the installer again. It tells you when a newer version is
out, and the Install button becomes **Update**. The version picker also
offers the development build: the very latest work-in-progress code from
this repository.

**Coming from the old installer?** Earlier releases shipped a different
Blindfold Installer. The new one recognizes a copy of Blindfold the old one
installed and takes it over; your settings are kept. You can delete the old
installer.

### Manual installation

Prefer to place files yourself? Each release also ships `Blindfold.zip`
(this README is included in it):

1. **Copy Injector Files**:
   * **Windows**: Copy `version.dll` from the zip into Balatro's game folder, next to `Balatro.exe` (Steam: right-click Balatro → Manage → Browse local files).
   * **macOS**: Copy `liblovely.dylib`, `run_lovely_macos.sh` and `steam_lovely_macos.sh` from the zip into Balatro's game folder, next to `Balatro.app`, and make the two `.sh` files executable (`chmod +x *.sh`).
   This is the [Lovely Injector](https://github.com/ethangreen-dev/lovely-injector) mod loader — skip it if you already run other Lovely mods.
2. **Copy Mod Payload**:
   * **Windows**: Copy the zip's `Blindfold` folder (excluding `lib/libloadstar.dylib` which is Mac-only) into `%APPDATA%\Balatro\Mods`, so it ends up at `%APPDATA%\Balatro\Mods\Blindfold` (create `Mods` if it doesn't exist yet).
   * **macOS**: Copy the zip's `Blindfold` folder (excluding `lib/loadstar.dll` and `lib/prism.dll`, which are Windows-only) into `~/Library/Application Support/Balatro/Mods`, so it ends up at `~/Library/Application Support/Balatro/Mods/Blindfold` (create `Mods` if it doesn't exist yet).
3. Launch Balatro through Steam. On macOS, set the Steam launch options
   first — see **Launching on macOS** above; without them the game starts
   unmodded.

#### macOS: unblocking the bundled libraries

If you download these files with a browser, macOS quarantines them and refuses
to load them. Both failures are quiet, so they are easy to misdiagnose:

* A quarantined `liblovely.dylib` means the mod never loads at all.
* A quarantined `lib/libloadstar.dylib` means the mod loads and writes to
  `blindfold.log` but never speaks. The log records the reason:
  `Loadstar NOT loaded ... library load disallowed by system policy`.

Clear it either way:

* **System Settings** — open Privacy & Security and go to the Security
  section. After a blocked load attempt there is a message naming the blocked
  library with an **Allow Anyway** button. Expect to do this once per library,
  relaunching the game in between.
* **Terminal** — remove the flag directly:

  ```
  xattr -d com.apple.quarantine "<game folder>/liblovely.dylib"
  xattr -d com.apple.quarantine "$HOME/Library/Application Support/Balatro/Mods/Blindfold/lib/libloadstar.dylib"
  ```

Installing through the installer avoids this entirely — files it extracts
itself are not quarantined.

To update manually, delete the `Blindfold` folder under `Mods` and copy in the new zip's folder — settings live outside it and survive. To uninstall manually, delete the `Blindfold` folder under `Mods` and the injector files.

**Uninstalling:** the installer's Uninstall button removes the mod and
offers to also remove Blindfold's settings. It leaves the Lovely Injector in
place, since other mods may use it. Your game saves are never touched.

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