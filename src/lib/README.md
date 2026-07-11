# Speech library (bundled)

The **64-bit** Prism runtime, committed so a plain clone speaks out of the box
(Balatro is x64 - x86 builds will not load):

- `prism.dll` - [Prism](https://github.com/ethindp/prism), a unified native
  abstraction over screen readers and TTS engines (NVDA, JAWS, SAPI, OneCore,
  ...). **Mozilla Public License 2.0**, redistributed unmodified; Prism in
  turn incorporates simdutf (Apache-2.0), the NVDA controller client RPC
  definitions (relicensed MPL-2.0 with permission), and SAPI-bridge helpers
  credited to the NVGT project. Full license texts live in the Prism
  repository's `LICENSES/` directory.

Prism talks to the screen readers directly, so no separate client DLLs
(nvdaControllerClient64, SAAPI64, ...) are needed.

If `prism.dll` is missing or fails to load, the mod still runs and writes
every announcement to `%APPDATA%/Balatro/blindfold.log`, so behavior can be
verified without speech.
