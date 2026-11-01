### New installer
* Blindfold has a new installer, built on [Loadstone](https://github.com/bradjrenshaw/loadstone). It installs and updates both Blindfold and the Lovely Injector, lets you change Blindfold's settings, and has a Launch game button. If you used the old installer, download the new one (`BlindfoldInstaller.exe` on Windows, `BlindfoldInstaller.dmg` on macOS): it recognizes your existing copy of Blindfold and takes it over, keeping your settings. You can delete the old installer afterwards.

### macOS
* Blindfold now runs on macOS, on both Apple Silicon and Intel Macs. See the README for installing and launching (Steam needs a launch option to load mods on macOS; the installer's Launch game button handles this for you).

### Speech
* Speech now goes through Loadstar, a new speech library shared across my mods. Options -> Blindfold -> Voice has a voice picker: "Auto" picks the best available voice, or choose any voice your system offers, grouped by type with voices in your game language first. Rate, pitch and volume sliders appear when the chosen voice supports them.
* On macOS, speech uses the system voices directly (VoiceOver output is not supported).
* Your previous speech settings don't carry over; Blindfold starts on Auto with default rate.

### Steamodded and other mods
* Blindfold now works alongside Steamodded and the mods built on it. Supported screens include Steamodded's New Run screen, booster packs, collection pages (decks, blinds, tags, stickers, poker hands), the Run Info stake tab, and the compact cash-out breakdown.
* The Mods menu is readable: each mod is a row with its name, version and authors, its enable checkbox, and its config button. Blindfold's own config button opens Blindfold's settings.
* Unchecking Blindfold in the Mods menu now asks for confirmation (press again within 10 seconds), since switching it off also turns off all speech.
* Content from other mods is read properly: modded card and booster pack names, card types, rarities, editions and stickers. Tested with Cryptid, Paperback and Card Sleeves.
* The JokerDisplay mod's readouts are read right after a joker's name.
* Very large numbers from Talisman and Amulet are read the way the game shows them.
* Tutorial steps that ask you to choose something (such as Cryptid's intro) can now be completed, and tutorial dialogue reads in the right order.
* Hand level-ups are announced again when Steamodded is installed.

### Other improvements
* A new Screen review buffer reads everything on screen as text, for screens and mod panels Blindfold doesn't know.
* The play, shop, blind select, pack and cash-out screens end with an "Other controls" row, so buttons other mods add are reachable.
* Black Hole's level change is now announced, and a blind that pays nothing reads "Blind reward, 0 dollars" instead of being skipped.
* Fixed the game gradually slowing down over a long run.
* For mod authors: Blindfold has an API for labelling your UI and announcing through Blindfold; see the README.
