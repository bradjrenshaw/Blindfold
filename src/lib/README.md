# Speech libraries (bundled)

Committed so a plain clone speaks out of the box. All 64-bit (Balatro is
x64; x86 builds will not load).

- `loadstar.dll` (Windows) / `libloadstar.dylib` (macOS, universal arm64 +
  x86_64) - [Loadstar](https://github.com/bradjrenshaw/loadstar)'s speech
  layer, which `speech.lua` drives through LuaJIT FFI: one tree of voices,
  a worker thread so the game never blocks on a speech engine, and a queue
  with explicit interrupts. **MIT**. Native SAPI 5 on Windows and AVSpeech on
  macOS are built in. `LOADSTAR_VERSION` names the loadstar commit these were
  built from; rebuild both with `scripts/build_loadstar.sh` (macOS, needs
  mingw-w64 for the Windows DLL).
- `prism.dll` (Windows) - [Prism](https://github.com/ethindp/prism), which
  Loadstar loads at runtime for screen readers (NVDA, JAWS, Narrator, ...).
  **Mozilla Public License 2.0**, redistributed unmodified; Prism in turn
  incorporates simdutf (Apache-2.0), the NVDA controller client RPC
  definitions (relicensed MPL-2.0 with permission), and SAPI-bridge helpers
  credited to the NVGT project. Full license texts live in the Prism
  repository's `LICENSES/` directory. macOS needs no Prism: its only Mac
  screen-reader backend (VoiceOver) proved unreliable, and AVSpeech is native.

Prism talks to the screen readers directly, so no separate client DLLs
(nvdaControllerClient64, SAAPI64, ...) are needed.

If the Loadstar library is missing or fails to load, the mod still runs and
writes every announcement to `blindfold.log` (`%APPDATA%/Balatro` on Windows,
`~/Library/Application Support/Balatro` on macOS), so behavior can be
verified without speech.
