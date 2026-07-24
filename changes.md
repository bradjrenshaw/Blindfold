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