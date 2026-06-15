# Native libraries (not committed)

Drop the **64-bit** Tolk runtime here. Balatro is x64, so the x86 builds will
not load.

Required:
- `Tolk.dll`
- `nvdaControllerClient64.dll`  (NVDA support)
- `SAAPI64.dll`                 (JAWS support)
- `dolapi64.dll`                (Dolphin/SystemAccess, optional)

Get them from the Tolk releases (the `x64` folder of the release zip):
https://github.com/dkager/tolk/releases

These DLLs are intentionally gitignored (`src/lib/*.dll`) — they are
third-party binaries and don't belong in the repo.

If this folder has no `Tolk.dll`, the mod still runs and writes every
announcement to `%APPDATA%/Balatro/balatro-access.log` so you can verify
behavior without speech.
