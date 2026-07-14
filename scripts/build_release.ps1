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

# Full vX.Y.Z, not vX.Y: the installer's update check parses release tags
# with Rust's semver crate, which requires all three components.
if ($Version -notmatch '^v\d+\.\d+\.\d+$') {
    throw "Version must look like v0.1.0 - a leading v and all three of major.minor.patch (got '$Version')."
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
    # Bundle the docs the in-game buttons open (<mod>/docs/*).
    $stagedDocs = Join-Path $stage 'Blindfold\docs'
    New-Item -ItemType Directory -Force -Path $stagedDocs | Out-Null
    Copy-Item (Join-Path $repo 'README.md') $stagedDocs -Force
    Copy-Item (Join-Path $repo 'changes.md') $stagedDocs -Force
    # Overwrite any local dev stamp with the release tag.
    Set-Content -Path (Join-Path $stage 'Blindfold\version') -Value $Version -Encoding Ascii -NoNewline

    # Manual installers open the zip first - the README (with its Manual
    # installation section) rides along at the root.
    Copy-Item (Join-Path $repo 'README.md') (Join-Path $stage 'README.md')

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
