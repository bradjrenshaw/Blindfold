# Speech libraries (bundled)

The **64-bit** Tolk runtime, committed so a plain clone speaks out of the box
(Balatro is x64 - x86 builds will not load):

- `Tolk.dll` - [Tolk](https://github.com/dkager/tolk), the screen-reader
  abstraction layer (LGPL v3). Built from the upstream source's x64 output.
- `nvdaControllerClient64.dll` - NVDA controller client (LGPL 2.1), NVDA support.
- `SAAPI64.dll` - JAWS support, redistributed as part of the Tolk bundle.

Optional (not bundled): `dolapi64.dll` for Dolphin/SystemAccess - drop it in
here if you need it.

If `Tolk.dll` is missing or fails to load, the mod still runs and writes every
announcement to `%APPDATA%/Balatro/blindfold.log`, so behavior can be verified
without speech.
