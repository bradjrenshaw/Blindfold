#!/bin/bash
# deploy_macos.sh — one-command developer install for Blindfold on macOS.
# The macOS counterpart of scripts/deploy.ps1.
#
#   1. Finds your Steam install of Balatro (library folders; override with
#      --game-dir).
#   2. Installs the bundled Lovely Injector (third_party/lovely/liblovely.dylib)
#      plus the two launch scripts next to Balatro.app.
#   3. Links ~/Library/Application Support/Balatro/Mods/Blindfold -> <repo>/src
#      as a symlink, so a plain `git pull` updates the installed mod (restart
#      the game to pick changes up).
#
# Usage:
#   scripts/deploy_macos.sh
#   scripts/deploy_macos.sh --game-dir "/path/to/Balatro"   folder containing Balatro.app
#   scripts/deploy_macos.sh --uninstall                     remove the mod link (Lovely is left alone)
#
# Lovely injects through DYLD_INSERT_LIBRARIES, which Steam does not set, so
# after deploying you must either set Steam's Launch Options (printed at the
# end) or start the game with the game folder's run_lovely_macos.sh.

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$repo/src"
mods="$HOME/Library/Application Support/Balatro/Mods"
link="$mods/Blindfold"

game_dir=""
uninstall=0
while [ $# -gt 0 ]; do
    case "$1" in
        --game-dir) game_dir="$2"; shift 2 ;;
        --uninstall) uninstall=1; shift ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

step() { echo "== $*"; }

# --- Uninstall ---------------------------------------------------------------
if [ "$uninstall" = 1 ]; then
    if [ -L "$link" ]; then
        rm "$link"
        echo "Removed mod link: $link"
    elif [ -e "$link" ]; then
        echo "WARNING: '$link' is a real folder, not this script's link; not touching it." >&2
    else
        echo "Mod link not present; nothing to remove."
    fi
    echo "Lovely Injector (liblovely.dylib in the game folder) was left in place."
    exit 0
fi

# --- 1. Locate Balatro ---------------------------------------------------------
find_balatro() {
    if [ -n "$game_dir" ]; then
        if [ -d "$game_dir/Balatro.app" ]; then echo "$game_dir"; return; fi
        echo "No Balatro.app under '$game_dir'." >&2; exit 1
    fi
    local steam="$HOME/Library/Application Support/Steam"
    local libs=("$steam")
    local vdf="$steam/steamapps/libraryfolders.vdf"
    if [ -f "$vdf" ]; then
        while IFS= read -r p; do libs+=("$p"); done \
            < <(sed -n 's/^[[:space:]]*"path"[[:space:]]*"\([^"]*\)".*/\1/p' "$vdf")
    fi
    local lib
    for lib in "${libs[@]}"; do
        if [ -d "$lib/steamapps/common/Balatro/Balatro.app" ]; then
            echo "$lib/steamapps/common/Balatro"; return
        fi
    done
    echo "Couldn't find Balatro. Re-run with: scripts/deploy_macos.sh --game-dir '/path/to/Balatro' (the folder containing Balatro.app)." >&2
    exit 1
}

step "Locating Balatro"
game="$(find_balatro)"
echo "   $game"

# --- 2. Lovely Injector ---------------------------------------------------------
step "Installing Lovely Injector"
for f in liblovely.dylib run_lovely_macos.sh steam_lovely_macos.sh; do
    from="$repo/third_party/lovely/$f"
    to="$game/$f"
    if [ ! -f "$from" ]; then
        echo "Bundled Lovely file missing at '$from' - incomplete checkout?" >&2; exit 1
    fi
    if [ -f "$to" ] && cmp -s "$from" "$to"; then
        echo "   $f already up to date"
    else
        cp "$from" "$to"
        echo "   installed $f"
    fi
    case "$f" in *.sh) chmod +x "$to" ;; esac
done
# Files that came through a browser download carry a quarantine flag and
# will not load; a git checkout does not, but clear it just in case.
xattr -d com.apple.quarantine "$game/liblovely.dylib" 2>/dev/null || true

# --- 3. Speech library sanity check --------------------------------------------
step "Checking speech library"
if [ ! -f "$src/lib/libloadstar.dylib" ]; then
    echo "   WARNING: missing src/lib/libloadstar.dylib - the mod will run LOG-ONLY (no speech)." >&2
else
    xattr -d com.apple.quarantine "$src/lib/libloadstar.dylib" 2>/dev/null || true
    echo "   Loadstar present"
fi

# --- 4. Version stamp -----------------------------------------------------------
step "Stamping the version"
if sha="$(git -C "$repo" rev-parse --short=7 HEAD 2>/dev/null)"; then
    printf 'main@%s' "$sha" > "$src/version"
    echo "   main@$sha"
    git -C "$repo" config core.hooksPath .githooks
else
    echo "   WARNING: not a git checkout? Version stamp skipped." >&2
fi

# --- 4b. Bundle the docs -----------------------------------------------------------
step "Bundling docs"
mkdir -p "$src/docs"
for doc in README.md changes.md; do
    if [ -f "$repo/$doc" ]; then
        cp "$repo/$doc" "$src/docs/$doc"
        echo "   $doc"
    else
        echo "   WARNING: $doc not found at repo root - the in-game button will 404." >&2
    fi
done

# --- 5. Mod link ------------------------------------------------------------------
step "Linking the mod"
mkdir -p "$mods"
if [ -L "$link" ]; then
    current="$(readlink "$link")"
    if [ "$current" = "$src" ]; then
        echo "   already linked: $link"
    else
        rm "$link"
        ln -s "$src" "$link"
        echo "   re-linked (previously -> $current)"
    fi
elif [ -e "$link" ]; then
    echo "A real folder already exists at '$link'. Remove it (it's another install of the mod), then re-run." >&2
    exit 1
else
    ln -s "$src" "$link"
    echo "   $link -> $src"
fi

echo
echo "Done. Lovely only loads when DYLD_INSERT_LIBRARIES is set, so either:"
echo "  * Steam -> Balatro -> Properties -> General -> Launch Options:"
echo "      \"$game/steam_lovely_macos.sh\" %command%"
echo "  * or start the game from a terminal with: \"$game/run_lovely_macos.sh\""
echo "You should hear 'Blindfold loaded.'"
echo "Update later with: git pull   (then restart the game)"
echo "Uninstall with:    scripts/deploy_macos.sh --uninstall"
