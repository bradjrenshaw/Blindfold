#!/bin/bash
# Steam launch-options wrapper for the Lovely Injector on macOS.
#
# This script is part of Blindfold (not the Lovely Injector); it lives here
# because it is installed into the game folder alongside liblovely.dylib.
#
# Lovely injects through DYLD_INSERT_LIBRARIES, so launching Balatro from
# Steam normally loads the game unmodded. Point Steam at this script instead:
#
#   Steam -> Balatro -> Properties -> General -> Launch Options
#     "<game folder>/steam_lovely_macos.sh" %command%
#
# Do not set the variable directly in Launch Options. Steam does not parse
# that string with a shell, so
#     DYLD_INSERT_LIBRARIES=... %command%
# makes Steam try to exec a binary with that literal name and fail with
# "Failed to start process for this game : OS Error 260". The assignment has
# to happen inside a real shell, which is what this script provides.
#
# Steam passes the game binary (and its arguments) in "$@".

KNOWN="$HOME/Library/Application Support/Steam/steamapps/common/Balatro"

# Locate the folder holding liblovely.dylib by walking up from the binary
# Steam handed us, then fall back to the stock install location.
game_dir=""
if [ -n "${1-}" ] && [ -e "${1-}" ]; then
    d="$(cd "$(dirname "$1")" 2>/dev/null && pwd)"
    for _ in 1 2 3 4 5; do
        [ -f "$d/liblovely.dylib" ] && { game_dir="$d"; break; }
        d="$(dirname "$d")"
    done
fi
[ -z "$game_dir" ] && [ -f "$KNOWN/liblovely.dylib" ] && game_dir="$KNOWN"
if [ -z "$game_dir" ]; then
    echo "steam_lovely_macos.sh: liblovely.dylib not found next to Balatro.app" >&2
    exit 1
fi

# `open` and .app paths go through LaunchServices, which drops our
# environment, so run the real binary ourselves in those cases.
use_direct=0
case "${1-}" in
    "" | *.app | *.app/) use_direct=1 ;;
esac
[ "$(basename "${1-}")" = "open" ] && use_direct=1

cd "$game_dir" || exit 1
lovely="$game_dir/liblovely.dylib"
[ "$use_direct" = "1" ] && set -- "$game_dir/Balatro.app/Contents/MacOS/love"

# On Apple Silicon, run the game natively. Steam is an Intel program, so
# what it starts runs as Intel too, under Rosetta, even though Balatro ships
# an Apple Silicon build. The game compiles its Lua as it runs (LuaJIT), and
# under Rosetta every freshly compiled piece is translated a second time:
# frames ran several times slower in bursts, and the game's audio crackled.
# `arch` picks the native build; it is a protected system program, which
# drops DYLD_* from its own environment, so the injection is handed to the
# game with -e instead. Both the game and the injector must have a native
# build (a single-architecture Lovely download may not): otherwise fall
# through to the launch below, exactly as before.
has_arm64() { /usr/bin/file "$1" 2>/dev/null | grep -q arm64; }
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ] && [ -x /usr/bin/arch ] \
    && has_arm64 "$1" && has_arm64 "$lovely"; then
    exec /usr/bin/arch -arm64 -e DYLD_INSERT_LIBRARIES="$lovely" "$@"
fi

# Every helper process above runs BEFORE the export, so none of them inherit
# DYLD_INSERT_LIBRARIES (they would be injected too, and an architecture
# mismatch there aborts the launch before the game ever starts).
export DYLD_INSERT_LIBRARIES="$lovely"
exec "$@"
