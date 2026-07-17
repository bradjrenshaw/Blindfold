# Blindfold Installer

A small Rust installer for end users (ported from the SayTheSpire2 installer).
GUI by default (wxWidgets via wxdragon — native, screen-reader-accessible
widgets); pass `--cli` for a console flow.

What it does:

1. Finds the Balatro install (Steam library folders/stock paths) and validates it by `Balatro.exe` (Windows) or `Balatro.app` (macOS).
2. Downloads a chosen release of `Blindfold.zip` from GitHub (or installs from
   a local zip, or — "Install dev build" — the latest commit on main via the
   branch zipball, remapping `src/**` and target injector files to
   the same destinations) and extracts it, routed:
   * **Windows**:
     * `version.dll` → the game folder (Lovely Injector; only written when missing)
     * `Blindfold/**` (excluding `lib/libprism.dylib`) → `%APPDATA%\Balatro\Mods`
   * **macOS**:
     * `liblovely.dylib` and `run_lovely_macos.sh` → the game folder (Lovely Injector; only written when missing)
     * `Blindfold/**` (excluding `lib/prism.dll`) → `~/Library/Application Support/Balatro/Mods`
3. Tracks the installed version in `Mods\Blindfold\version` and offers
   Update when GitHub has a newer tag (semver compare). Dev builds are
   recorded as `main@<sha>` and update-check against the tip of main
   instead — "Update dev build" appears whenever main has moved, so dev
   users can stay on that channel; the Install button ("Install release")
   remains the way back to stable.
4. Uninstall removes the mod folder and optionally the injector files (left alone
   if other Lovely mods are present) and the user files
   (`blindfold_settings.lua`, `blindfold_keybinds.lua`, `blindfold.log`).

If `Mods\Blindfold` is a junction — a developer install made by
`scripts\deploy.ps1` — Install is disabled (updates come from `git pull`),
but Uninstall still works: it removes just the link, never the checkout
behind it, after which a release can be installed normally.

Build: `cargo build --release` (or `scripts\build_release.ps1` at the repo
root, which also assembles `Blindfold.zip`). Tests: `cargo test`.
