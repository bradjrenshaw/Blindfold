# build_release.ps1 — assemble the release artifacts for a Blindfold release.
#
# Usage: scripts\build_release.ps1 -Version v0.1.0
#
# Produces at the repo root:
#   Blindfold.zip            what the installer downloads/extracts:
#                              version.dll     (bundled Lovely Injector -> game folder)
#                              Blindfold/**    (src\ payload -> %APPDATA%\Balatro\Mods)
#   BlindfoldInstaller.exe   the installer itself (skip with -NoInstaller)
#
# Then publish both as assets on a GitHub release, e.g.:
#   gh release create v0.1.0 Blindfold.zip BlindfoldInstaller.exe --title v0.1.0 --notes "..."
# The installer reads releases via the GitHub API, so the tag (vX.Y.Z) is the
# version users see and update-checks compare against.

param(
    # The release tag (vX.Y.Z) — stamped into Blindfold/version inside the zip
    # so the mod announces it and update-checks against the releases channel.
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [switch]$NoInstaller
)

if ($Version -notmatch '^v\d+\.\d+(\.\d+)?$') {
    throw "Version must look like v0.1.0 (got '$Version')."
}

$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$src  = Join-Path $repo 'src'

function Write-Step($msg) { Write-Host "== $msg" }

# --- Preflight: everything the zip must ship -----------------------------------
Write-Step "Checking release contents"
$lovely = Join-Path $repo 'third_party\lovely\version.dll'
if (-not (Test-Path $lovely)) {
    throw "Bundled Lovely missing at '$lovely'."
}
if (-not (Test-Path (Join-Path $src 'lib\prism.dll'))) {
    throw "Missing src\lib\prism.dll - a release without the speech library would be log-only. Aborting."
}
Write-Host "   Lovely + Prism present"

# --- Stage and zip ---------------------------------------------------------------
Write-Step "Building Blindfold.zip"
$stage = Join-Path $env:TEMP "blindfold_release_$PID"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null
try {
    Copy-Item $src (Join-Path $stage 'Blindfold') -Recurse
    Copy-Item $lovely (Join-Path $stage 'version.dll')
    # Overwrite any local dev stamp with the release tag.
    Set-Content -Path (Join-Path $stage 'Blindfold\version') -Value $Version -Encoding Ascii -NoNewline

    # Manual installers open the zip first - put the instructions right there.
    $install_txt = @"
Blindfold $Version - manual installation
========================================

The easy way is BlindfoldInstaller.exe from the same release page, which
does all of this for you. To install by hand instead:

1. Copy version.dll (from this zip) into Balatro's game folder, next to
   Balatro.exe. Find the folder via Steam: right-click Balatro ->
   Manage -> Browse local files. (version.dll is the Lovely Injector,
   the mod loader - skip this copy if you already run other Lovely mods.)

2. Copy the Blindfold folder (from this zip) into:
       %APPDATA%\Balatro\Mods
   so it ends up at %APPDATA%\Balatro\Mods\Blindfold. Create the Mods
   folder if it does not exist. Paste the path above into a File
   Explorer address bar to get there.

3. Launch Balatro through Steam. You should hear "Blindfold $Version
   loaded."

Updating: delete %APPDATA%\Balatro\Mods\Blindfold and copy in the new
zip's Blindfold folder (your settings live outside it and survive).

Uninstalling: delete %APPDATA%\Balatro\Mods\Blindfold, and version.dll
from the game folder if no other mods need it. Game saves are separate
and unaffected.

Full documentation: https://github.com/bradjrenshaw/Blindfold
"@
    Set-Content -Path (Join-Path $stage 'INSTALL.txt') -Value $install_txt -Encoding Ascii

    $zip = Join-Path $repo 'Blindfold.zip'
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip
    Write-Host "   $zip"
} finally {
    Remove-Item $stage -Recurse -Force
}

# --- Installer ---------------------------------------------------------------------
if (-not $NoInstaller) {
    Write-Step "Building the installer (cargo release)"
    Push-Location (Join-Path $repo 'installer')
    try {
        # cargo writes progress to stderr; route through cmd so PowerShell 5.1
        # doesn't promote those lines to errors under ErrorActionPreference Stop.
        & cmd /c "cargo build --release 2>&1"
        if ($LASTEXITCODE -ne 0) { throw "cargo build failed" }
    } finally {
        Pop-Location
    }
    Copy-Item (Join-Path $repo 'installer\target\release\blindfold-installer.exe') `
              (Join-Path $repo 'BlindfoldInstaller.exe') -Force
    Write-Host "   $(Join-Path $repo 'BlindfoldInstaller.exe')"
}

Write-Host ""
Write-Host "Done. Publish with:"
Write-Host "  gh release create $Version Blindfold.zip BlindfoldInstaller.exe --title $Version --notes `"...`""
