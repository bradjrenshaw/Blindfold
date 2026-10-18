#!/bin/bash
# build_release_macos.sh — assemble the release artifacts for a Blindfold
# release on macOS. The counterpart of scripts/build_release.ps1; both produce
# the same cross-platform zips, so a release can be cut from either OS.
#
# Usage: scripts/build_release_macos.sh v1.2.0 [--no-installer | --installer-only]
#
# --installer-only builds just BlindfoldInstaller.app.zip, for a release cut on
# Windows (whose zips and loadstone-release.json must not be rebuilt here).
#
# Produces at the repo root:
#   Blindfold.zip              what the standalone installers download/extract:
#                                version.dll, liblovely.dylib, *_lovely_macos.sh
#                                  (bundled Lovely Injector -> game folder,
#                                  each installer keeps its own platform's files)
#                                Blindfold/**  (src/ payload -> the Mods folder)
#   Blindfold-loadstone.zip    payload for Loadstone Mod Manager: Blindfold/**
#                                plus the two macOS launch scripts at the root
#                                (routed by loadstone-packages/blindfold.json);
#                                no bundled Lovely — the manager installs it as
#                                a dependency.
#   loadstone-release.json     the Loadstone release manifest for that zip
#   BlindfoldInstaller.app.zip the macOS Blindfold Installer: Loadstone with
#                                installer/profile.json baked in (skip with
#                                --no-installer; needs a Loadstone checkout at
#                                ../loadstone or $LOADSTONE_REPO)
#
# Then publish, e.g.:
#   gh release create v1.2.0 Blindfold.zip Blindfold-loadstone.zip loadstone-release.json \
#       BlindfoldInstaller.app.zip --title v1.2.0 --notes "..."
# Keep Blindfold.zip FIRST in that list: old standalone installers download the
# first .zip asset on the release, and upload order preserves that.

set -euo pipefail

version="${1:-}"
no_installer=0
installer_only=0
shift || true
while [ $# -gt 0 ]; do
    case "$1" in
        --no-installer) no_installer=1; shift ;;
        --installer-only) installer_only=1; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done
# Full vX.Y.Z: the installer's update check parses release tags with Rust's
# semver crate, which requires all three components.
if ! [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must look like v0.1.0 - a leading v and all three of major.minor.patch (got '$version')." >&2
    exit 2
fi

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$repo/src"
lovely="$repo/third_party/lovely"
step() { echo "== $*"; }

if [ "$installer_only" = 0 ]; then
    # --- Preflight: everything the zip must ship -----------------------------------
    step "Checking release contents"
    for f in "$lovely/version.dll" "$lovely/liblovely.dylib" "$lovely/run_lovely_macos.sh" \
             "$lovely/steam_lovely_macos.sh"; do
        [ -f "$f" ] || { echo "Bundled Lovely file missing at '$f'." >&2; exit 1; }
    done
    for f in "$src/lib/loadstar.dll" "$src/lib/prism.dll" "$src/lib/libloadstar.dylib"; do
        [ -f "$f" ] || { echo "Missing $f - a release without the speech library would be log-only. Aborting." >&2; exit 1; }
    done
    echo "   Lovely + Loadstar present (Windows and macOS), Prism (Windows)"

    # --- Stamp the Lovely manifest ----------------------------------------------------
    # Stamped IN THE REPO so it ships committed with the release and dev builds
    # inherit the latest release baseline.
    step "Stamping lovely.toml"
    numeric="${version#v}"
    if grep -q "^version = \"$numeric\"" "$src/lovely.toml"; then
        echo "   already $numeric"
    else
        sed -i '' -E "0,/^version = \"[^\"]*\"/s//version = \"$numeric\"/" "$src/lovely.toml"
        echo "   version = $numeric  (repo file updated - commit it with the release)"
    fi

    # --- Stage and zip ---------------------------------------------------------------
    step "Building Blindfold.zip"
    stage="$(mktemp -d "${TMPDIR:-/tmp}/blindfold_release_XXXXXX")"
    trap 'rm -rf "$stage"' EXIT
    rsync -a --exclude '.DS_Store' "$src/" "$stage/Blindfold/"
    cp "$lovely/version.dll" "$lovely/liblovely.dylib" "$lovely/run_lovely_macos.sh" \
       "$lovely/steam_lovely_macos.sh" "$stage/"
    # Bundle the docs the in-game buttons open (<mod>/docs/*).
    mkdir -p "$stage/Blindfold/docs"
    cp "$repo/README.md" "$repo/changes.md" "$stage/Blindfold/docs/"
    # Overwrite any local dev stamp with the release tag.
    printf '%s' "$version" > "$stage/Blindfold/version"
    # Manual installers open the zip first - the README rides along at the root.
    cp "$repo/README.md" "$stage/README.md"

    zipfile="$repo/Blindfold.zip"
    rm -f "$zipfile"
    (cd "$stage" && zip -q -r -X "$zipfile" .)
    echo "   $zipfile"

    # Payload zip for Loadstone Mod Manager: Blindfold/** plus the macOS launch
    # scripts (the manager routes them into the game folder on macOS). No bundled
    # Lovely and no root README.
    manager_zip="$repo/Blindfold-loadstone.zip"
    rm -f "$manager_zip"
    (cd "$stage" && zip -q -r -X "$manager_zip" Blindfold run_lovely_macos.sh steam_lovely_macos.sh)
    echo "   $manager_zip"

    # --- Loadstone release manifest ----------------------------------------------------
    # Must be built from the same zip that gets uploaded.
    step "Building loadstone-release.json (Loadstone)"
    loadstone_bin="${LOADSTONE:-}"
    if [ -z "$loadstone_bin" ]; then
        if command -v loadstone >/dev/null 2>&1; then
            loadstone_bin="$(command -v loadstone)"
        else
            for cand in "$repo/../loadstone/target/release/loadstone" "$repo/../loadstone/target/debug/loadstone"; do
                [ -x "$cand" ] && { loadstone_bin="$cand"; break; }
            done
        fi
    fi
    if [ -n "$loadstone_bin" ]; then
        "$loadstone_bin" package --version "$version" \
            --manifest "$repo/loadstone-packages/blindfold.json" \
            --artifact "$manager_zip" \
            --out "$repo/loadstone-release.json"
        echo "   $repo/loadstone-release.json"
    else
        echo "   WARNING: loadstone CLI not found (PATH, \$LOADSTONE, or ../loadstone/target) - skipping loadstone-release.json (install: cargo install --path <loadstone repo>/crates/loadstone-cli)" >&2
    fi
fi

# --- Installer ---------------------------------------------------------------------
# The Blindfold Installer is Loadstone with installer/profile.json baked in
# (installer/README.md). Loadstone's script makes it universal, statically
# linked, and ad-hoc signed.
if [ "$no_installer" = 0 ] || [ "$installer_only" = 1 ]; then
    step "Building the installer (Loadstone, single-mod profile)"
    loadstone_repo="${LOADSTONE_REPO:-$repo/../loadstone}"
    [ -x "$loadstone_repo/scripts/build_macos_app.sh" ] || {
        echo "Loadstone checkout not found at $loadstone_repo (set LOADSTONE_REPO)." >&2; exit 1; }
    out="$(mktemp -d "${TMPDIR:-/tmp}/blindfold_installer_XXXXXX")"
    "$loadstone_repo/scripts/build_macos_app.sh" \
        --profile "$repo/installer/profile.json" \
        --name "Blindfold Installer" \
        --bundle-id com.bradjrenshaw.blindfold.installer \
        --out "$out"
    rm -f "$repo/BlindfoldInstaller.app.zip"
    (cd "$out" && ditto -c -k --keepParent "Blindfold Installer.app" "$repo/BlindfoldInstaller.app.zip")
    rm -rf "$out"
    echo "   $repo/BlindfoldInstaller.app.zip"
fi

if [ "$installer_only" = 1 ]; then
    echo
    echo "Done: BlindfoldInstaller.app.zip (copy it to the machine cutting the release)."
    exit 0
fi
echo
echo "Done. Publish with:"
echo "  gh release create $version Blindfold.zip Blindfold-loadstone.zip loadstone-release.json BlindfoldInstaller.app.zip --title $version --notes \"...\""
echo "NOTE: keep Blindfold.zip FIRST in that list (old standalone installers download the first .zip asset)."
echo "NOTE: a release cut here has no Windows BlindfoldInstaller.exe, so its loadstone-release.json"
echo "      carries no installer block and Windows installers won't offer to update themselves."
echo "      Cut from Windows (scripts/build_release.ps1) to ship the exe."
