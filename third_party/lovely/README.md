# Lovely Injector (bundled)

`version.dll` for Windows, as well as `liblovely.dylib` and `run_lovely_macos.sh` for MacOS are the [Lovely Injector](https://github.com/ethangreen-dev/lovely-injector),
**v0.9.0**, Windows x64 `lovely-x86_64-pc-windows-msvc.zip` and osx ARM64 `lovely-aarch64-apple-darwin.tar.gz` builds from the
upstream release. MIT licensed by its authors.

It is bundled so `scripts/deploy.ps1` can install the mod with no downloads.
The script copies this file next to `Balatro.exe`; the game's launcher then
loads Lovely, which applies the patches in `src/lovely.toml`.

To bump the version: download the new release zip from upstream, replace this
`version.dll`, update the version number above, and commit.
