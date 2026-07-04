# Lovely Injector (bundled)

`version.dll` is the [Lovely Injector](https://github.com/ethangreen-dev/lovely-injector),
**v0.9.0**, Windows x64 build (`lovely-x86_64-pc-windows-msvc.zip` from the
upstream release). MIT licensed by its authors.

It is bundled so `scripts/deploy.ps1` can install the mod with no downloads.
The script copies this file next to `Balatro.exe`; the game's launcher then
loads Lovely, which applies the patches in `src/lovely.toml`.

To bump the version: download the new release zip from upstream, replace this
`version.dll`, update the version number above, and commit.
