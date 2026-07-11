# Blindfold Installer

A small Rust installer for end users (ported from the SayTheSpire2 installer).
GUI by default (wxWidgets via wxdragon — native, screen-reader-accessible
widgets); pass `--cli` for a console flow.

What it does:

1. Finds the Balatro install (Steam registry → `libraryfolders.vdf` → default
   path; Browse... as fallback) and validates it by `Balatro.exe`.
2. Downloads a chosen release of `Blindfold.zip` from GitHub (or installs from
   a local zip, or — "Install dev build" — the latest commit on main via the
   branch zipball, remapping `src/**` and `third_party/lovely/version.dll` to
   the same destinations) and extracts it, routed:
   - `version.dll` → the game folder (Lovely Injector; skipped if identical,
     so updates don't demand elevation for a no-op)
   - `Blindfold/**` → `%APPDATA%\Balatro\Mods` (replaced wholesale, so updates
     never leave stale files; settings live outside and survive)
3. Tracks the installed version in `Mods\Blindfold\version` and offers
   Update when GitHub has a newer tag (semver compare). Dev builds are
   recorded as `main@<sha>`; any release then shows as an available update.
4. Uninstall removes the mod folder and optionally `version.dll` (left alone
   if other Lovely mods are present) and the user files
   (`blindfold_settings.lua`, `blindfold_keybinds.lua`, `blindfold.log`).

If `Mods\Blindfold` is a junction — a developer install made by
`scripts\deploy.ps1` — Install is disabled (updates come from `git pull`),
but Uninstall still works: it removes just the link, never the checkout
behind it, after which a release can be installed normally.

Build: `cargo build --release` (or `scripts\build_release.ps1` at the repo
root, which also assembles `Blindfold.zip`). Tests: `cargo test`.
