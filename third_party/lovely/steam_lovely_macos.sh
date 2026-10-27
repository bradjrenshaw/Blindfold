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

# Every helper process above runs BEFORE the export, so none of them inherit
# DYLD_INSERT_LIBRARIES (they would be injected too, and an architecture
# mismatch there aborts the launch before the game ever starts).
cd "$game_dir" || exit 1
export DYLD_INSERT_LIBRARIES="$game_dir/liblovely.dylib"

[ "$use_direct" = "1" ] && exec "$game_dir/Balatro.app/Contents/MacOS/love"
exec "$@"
