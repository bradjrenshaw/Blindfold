## v1.2.0
#### New installer
* Blindfold has a new installer, built on [Loadstone](https://github.com/bradjrenshaw/loadstone). It installs and updates both Blindfold and the Lovely Injector, lets you change Blindfold's settings, and has a Launch game button. If you used the old installer, download the new one (`BlindfoldInstaller.exe` on Windows, `BlindfoldInstaller.dmg` on macOS): it recognizes your existing copy of Blindfold and takes it over, keeping your settings. You can delete the old installer afterwards.

#### macOS
* Blindfold now runs on macOS, on both Apple Silicon and Intel Macs. See the README for installing and launching (Steam needs a launch option to load mods on macOS; the installer's Launch game button handles this for you).

#### Speech
* Speech now goes through Loadstar, a new speech library shared across my mods. Options -> Blindfold -> Voice has a voice picker: "Auto" picks the best available voice, or choose any voice your system offers, grouped by type with voices in your game language first. Rate, pitch and volume sliders appear when the chosen voice supports them.
* On macOS, speech uses the system voices directly (VoiceOver output is not supported).
* Your previous speech settings don't carry over; Blindfold starts on Auto with default rate.

#### Steamodded and other mods
* Blindfold now works alongside Steamodded and the mods built on it. Supported screens include Steamodded's New Run screen, booster packs, collection pages (decks, blinds, tags, stickers, poker hands), the Run Info stake tab, and the compact cash-out breakdown.
* The Mods menu is readable: each mod is a row with its name, version and authors, its enable checkbox, and its config button. Blindfold's own config button opens Blindfold's settings.
* Unchecking Blindfold in the Mods menu now asks for confirmation (press again within 10 seconds), since switching it off also turns off all speech.
* Content from other mods is read properly: modded card and booster pack names, card types, rarities, editions and stickers. Tested with Cryptid, Paperback and Card Sleeves.
* The JokerDisplay mod's readouts are read right after a joker's name.
* Very large numbers from Talisman and Amulet are read the way the game shows them.
* Tutorial steps that ask you to choose something (such as Cryptid's intro) can now be completed, and tutorial dialogue reads in the right order.
* Hand level-ups are announced again when Steamodded is installed.

#### Other improvements
* A new Screen review buffer reads everything on screen as text, for screens and mod panels Blindfold doesn't know.
* The play, shop, blind select, pack and cash-out screens end with an "Other controls" row, so buttons other mods add are reachable.
* Black Hole's level change is now announced, and a blind that pays nothing reads "Blind reward, 0 dollars" instead of being skipped.
* Fixed the game gradually slowing down over a long run.
* For mod authors: Blindfold has an API for labelling your UI and announcing through Blindfold; see the README.

## v1.0.9
* fix a crash that could occur when navigating the UI when the closing animation for free card packs is playing (specifically in blind select, such as the post-skip free packs.)
* The mod UI navigation keys now properly update the location of the cursor on screen (triggering hover tooltips, etc.)

## v1.0.8
* Moving in a direction with no UI element will no longer repeat the element you were already on.
* Every number should now read properly in scientific notation once it becomes large enough (replicating the game's behavior and formatting exactly.)
* Fixed extremely rare instances of lag due to logging. Only the logs for the current and previous session are now kept.

## v1.0.7
* Fixed a bug where blind rewards would be read out even when disabled for that blind.
* The blinds tab of Run Info is now rendered properly (a row of panels for the Small Blind, Big Blind, and Boss Blind.)
* Fixed a bug where you could not include modifier keys (control/shift/alt) when remapping keybindings.
* Fixed a bug where you could remap multiple inputs to the same  keybinding.
* You can now use the play hand and discard keybindings to trigger the next blind and reroll buttons in the shop respectively. The hotkey for discards remaining will quickly announce the reroll cost.
* Fixed a bug where some cards with dynamic text (for example Misprint) would not correctly render parts of the text that changed.
* Added an option to the mod settings menu that allows cards to be played in selection order. When enabled, selected cards also announce their selection position.

## v1.0.6
* Fixed various cases where the mod would allow you to complete actions that the tutorial blocked, causing various game softlocks.
* Fixed an issue where the hand requirements column of the Poker Hands table was missing.
* Fixed an issue with the run info screen where your focus would be moved to the first element of each tab instead of remaining on the tab bar.

## v1.0.5
* Fixed a bug where dragging a face-down card would speak its name.
* Fixed a bug where deviating from the tutorial (moving to another screen than the one it wants you to for example) would softlock the mod.
* The Poker Hands section of the run info screen should now be a lot easier to read. You can also now properly browse it as a table.

## v1.0.4
* Fixed an issue where certain tags were not being read out when a card is focused (for example eternal.)
* Keyword tooltips are now automatically read out when a card is focused. This can be configured under announcements in the mod settings.
* Fixed an issue where clearing your hand selection would act inconsistently (often not clearing the selection or simply announcing nothing.)
* Fixed an issue where some message text would not be read (the "Nope!" text on Wheel of fortune for example.)
* Various new events spoken, including editions being announced when applied to jokers (for example Wheel of Fortune, Hex.) These can be configured from the options menu.

## v1.0.3
* Fixed an issue that could prevent speech output from working if the file path of the mod contained utf-8 characters that did not directly convert to ANSI.
* Fixed a bug where there was no feedback for clearing your hand selection with backspace (keyboard) or b/circle (controller.)

## v1.0.2
* Added options for customizing the format of various scoring announcements. This should help when many announcements are being scored at a faster pace.
* The Amber Acorn showdown blind should now be a lot more fair.
* Fixed an issue where the speech handler slider in the mod options would not switch properly between handlers.
* The readme and changes.md are now properly included in the downloaded mod files.
* Added View Documentation and View Changes buttons to the mod's options menu.