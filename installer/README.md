# Blindfold Installer

The Blindfold Installer is [Loadstone](https://github.com/bradjrenshaw/loadstone)
built with `profile.json` baked in: a single-mod profile that opens straight
to Blindfold's page (Install/Update, Uninstall, Settings, Launch game) and
resolves packages only from the Loadstone registry. Everything it does comes
from `../loadstone-packages/blindfold.json`, so changing what gets installed
where is a manifest change, not installer code.

Self-update: a single-mod build checks Blindfold's latest release and
offers its own platform's installer when that was built from a newer
Loadstone. The release scripts pass every installer build on hand to
`loadstone package --installer`, so a release should be packaged with both
`BlindfoldInstaller.exe` and `BlindfoldInstaller.dmg` in the repo root:
build the other platform's first (`build_release_macos.sh vX.Y.Z
--installer-only` on a Mac, or the Windows script) and copy it over. On
macOS the app updates itself in place (installing from the new disk image)
once it has been copied out of the disk image, typically into Applications;
run from inside the image or from a read-only copy, it says to move it
first.

## Building

Both release scripts build it from a Loadstone checkout next to this repo
(`../loadstone`, or `$LOADSTONE_REPO`):

- **macOS** (`scripts/build_release_macos.sh`): Loadstone's
  `scripts/build_macos_app.sh --profile installer/profile.json --name
  "Blindfold Installer"` produces a universal, statically linked,
  ad-hoc-signed `Blindfold Installer.app`, zipped as
  `BlindfoldInstaller.dmg`. The first run builds a static wxWidgets
  (cached under `~/Library/Caches/loadstone`).
- **Windows** (`scripts/build_release.ps1`): Loadstone's CMake build from a
  Visual Studio developer prompt, with static wxWidgets at
  `$env:LOADSTONE_WX_STATIC`, `-DLOADSTONE_EMBED_PROFILE=installer\profile.json`
  and `-DLOADSTONE_APP_NAME=BlindfoldInstaller`, giving
  `BlindfoldInstaller.exe`.

To try a profile without rebuilding, put it next to a Loadstone executable
as `loadstone.json` (on macOS, in `Loadstone.app/Contents/MacOS/`).
