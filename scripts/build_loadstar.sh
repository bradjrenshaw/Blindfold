#!/bin/bash
# build_loadstar.sh — rebuild the bundled Loadstar speech library from source.
#
# Builds https://github.com/bradjrenshaw/loadstar for both platforms on macOS
# and copies the results into src/lib:
#   libloadstar.dylib   universal (arm64 + x86_64): Steam may run Balatro
#                       natively or under Rosetta, and the library must load
#                       either way (the same reason liblovely.dylib is fat)
#   loadstar.dll        x86_64 Windows, cross-built with mingw-w64
# and records the loadstar commit in src/lib/LOADSTAR_VERSION.
#
# Usage:
#   scripts/build_loadstar.sh                    loadstar checkout at ../loadstar
#   scripts/build_loadstar.sh /path/to/loadstar
#
# Needs: rustup targets aarch64-apple-darwin, x86_64-apple-darwin,
# x86_64-pc-windows-gnu, and mingw-w64 (brew install mingw-w64).

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
loadstar="${1:-$repo/../loadstar}"
loadstar="$(cd "$loadstar" && pwd)"
lib="$repo/src/lib"

step() { echo "== $*"; }

if [ -n "$(git -C "$loadstar" status --porcelain)" ]; then
    echo "WARNING: $loadstar has uncommitted changes; LOADSTAR_VERSION will say so." >&2
fi
rev="$(git -C "$loadstar" rev-parse --short HEAD)"
[ -n "$(git -C "$loadstar" status --porcelain)" ] && rev="$rev-dirty"

for t in aarch64-apple-darwin x86_64-apple-darwin x86_64-pc-windows-gnu; do
    step "Building loadstar ($t)"
    (cd "$loadstar" && cargo build --release --target "$t" -p loadstar-ffi)
done

step "Merging the macOS slices"
lipo -create \
    "$loadstar/target/aarch64-apple-darwin/release/libloadstar.dylib" \
    "$loadstar/target/x86_64-apple-darwin/release/libloadstar.dylib" \
    -output "$lib/libloadstar.dylib"
# The dylib records its build path as its install name; make it relative so
# nothing ever goes looking for the build tree.
install_name_tool -id "@rpath/libloadstar.dylib" "$lib/libloadstar.dylib"
codesign --force --sign - "$lib/libloadstar.dylib"

cp "$loadstar/target/x86_64-pc-windows-gnu/release/loadstar.dll" "$lib/loadstar.dll"
echo "$rev" > "$lib/LOADSTAR_VERSION"

lipo -info "$lib/libloadstar.dylib"
echo "Loadstar $rev -> $lib"
