# Blindfold Installer

The Blindfold Installer is [Loadstone](https://github.com/bradjrenshaw/loadstone)
built with `profile.json` baked in: a single-mod profile that opens straight
to Blindfold's page (Install/Update, Uninstall, Settings, Launch game) and
resolves packages only from the Loadstone registry. Everything it does comes
from `../loadstone-packages/blindfold.json`, so changing what gets installed
where is a manifest change, not installer code.

Self-update: a single-mod build checks Blindfold's own releases. The
`installer` block that `loadstone package --installer` stamps into
`loadstone-release.json` names the Windows exe; macOS builds do not
self-update yet.

## Building

Both release scripts build it from a Loadstone checkout next to this repo
(`../loadstone`, or `$LOADSTONE_REPO`):

- **macOS** (`scripts/build_release_macos.sh`): Loadstone's
  `scripts/build_macos_app.sh --profile installer/profile.json --name
  "Blindfold Installer"` produces a universal, statically linked,
  ad-hoc-signed `Blindfold Installer.app`, zipped as
  `BlindfoldInstaller.app.zip`. The first run builds a static wxWidgets
  (cached under `~/Library/Caches/loadstone`).
- **Windows** (`scripts/build_release.ps1`): Loadstone's CMake build from a
  Visual Studio developer prompt, with static wxWidgets at
  `$env:LOADSTONE_WX_STATIC`, `-DLOADSTONE_EMBED_PROFILE=installer\profile.json`
  and `-DLOADSTONE_APP_NAME=BlindfoldInstaller`, giving
  `BlindfoldInstaller.exe`.

To try a profile without rebuilding, put it next to a Loadstone executable
as `loadstone.json` (on macOS, in `Loadstone.app/Contents/MacOS/`).
