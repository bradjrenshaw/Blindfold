# build_release.ps1 — assemble the release artifacts for a Blindfold release.
#
# Usage: scripts\build_release.ps1 -Version v0.1.0
#
# Produces at the repo root:
#   Blindfold.zip            what the installer downloads/extracts:
#                              version.dll     (bundled Lovely Injector -> game folder)
#                              Blindfold/**    (src\ payload -> %APPDATA%\Balatro\Mods)
#   Blindfold-loadstone.zip  the Loadstone payload, plus loadstone-release.json
#   BlindfoldInstaller.exe   the Blindfold Installer: Loadstone with
#                              installer\profile.json baked in (skip with
#                              -NoInstaller). Needs a Loadstone checkout at
#                              ..\loadstone (or $env:LOADSTONE_REPO), a Visual
#                              Studio developer prompt, Ninja, and static
#                              wxWidgets at $env:LOADSTONE_WX_STATIC.
#
# Then publish them as assets on a GitHub release (the command is printed at
# the end).
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
foreach ($lib in 'loadstar.dll', 'prism.dll') {
    if (-not (Test-Path (Join-Path $src "lib\$lib"))) {
        throw "Missing src\lib\$lib - a release without the speech libraries would be log-only. Aborting."
    }
}
Write-Host "   Lovely + Loadstar + Prism present"

# --- Stamp the Lovely manifest ----------------------------------------------------
# lovely.toml's [manifest] version is what Lovely reports for the mod. It is
# stamped IN THE REPO (not just the staged copy) so it ships committed with
# the release and dev builds inherit the latest release baseline.
Write-Step "Stamping lovely.toml"
$numeric = $Version.TrimStart('v')
$manifestPath = Join-Path $src 'lovely.toml'
$toml = [IO.File]::ReadAllText($manifestPath)
$re = New-Object Text.RegularExpressions.Regex('version = "[^"]*"')
$stamped = $re.Replace($toml, 'version = "' + $numeric + '"', 1)
if ($stamped -ne $toml) {
    [IO.File]::WriteAllText($manifestPath, $stamped, (New-Object Text.UTF8Encoding($false)))
    Write-Host "   version = $numeric  (repo file updated - commit it with the release)"
} else {
    Write-Host "   already $numeric"
}

# --- Stage and zip ---------------------------------------------------------------
Write-Step "Building Blindfold.zip"
$stage = Join-Path $env:TEMP "blindfold_release_$PID"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null
try {
    Copy-Item $src (Join-Path $stage 'Blindfold') -Recurse
    Copy-Item $lovely (Join-Path $stage 'version.dll')
    # macOS injector + launch scripts ride along in the same zip; each
    # platform's installer keeps only its own files (and Loadstone routes the
    # scripts by platform). Compress-Archive drops unix exec bits, which the
    # installers restore on extraction.
    foreach ($macFile in 'liblovely.dylib', 'run_lovely_macos.sh', 'steam_lovely_macos.sh') {
        $from = Join-Path $repo "third_party\lovely\$macFile"
        if (-not (Test-Path $from)) { throw "Bundled macOS Lovely file missing at '$from'." }
        Copy-Item $from (Join-Path $stage $macFile)
    }
    if (-not (Test-Path (Join-Path $src 'lib\libloadstar.dylib'))) {
        throw "Missing src\lib\libloadstar.dylib - macOS users would get a release without speech. Aborting."
    }
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

    # Payload zip for Loadstone Mod Manager: Blindfold/** plus the macOS launch
    # scripts (routed into the game folder on macOS by loadstone-packages\
    # blindfold.json) — no bundled Lovely (the manager installs tools as
    # dependencies and keeps them current) and no root README. Manual installs
    # keep using Blindfold.zip above.
    $managerZip = Join-Path $repo 'Blindfold-loadstone.zip'
    if (Test-Path $managerZip) { Remove-Item $managerZip -Force }
    Compress-Archive -Path @(
        (Join-Path $stage 'Blindfold'),
        (Join-Path $stage 'run_lovely_macos.sh'),
        (Join-Path $stage 'steam_lovely_macos.sh')
    ) -DestinationPath $managerZip
    Write-Host "   $managerZip"
} finally {
    Remove-Item $stage -Recurse -Force
}

# --- Installer ---------------------------------------------------------------------
# Built before the release manifest so `loadstone package --installer` can stamp
# the exe's hash into it: running installers read that to offer self-update.
$installerExe = Join-Path $repo 'BlindfoldInstaller.exe'
if (-not $NoInstaller) {
    Write-Step "Building the installer (Loadstone, single-mod profile)"
    $loadstoneRepo = if ($env:LOADSTONE_REPO) { $env:LOADSTONE_REPO } else { Join-Path $repo '..\loadstone' }
    if (-not (Test-Path (Join-Path $loadstoneRepo 'app\CMakeLists.txt'))) {
        throw "Loadstone checkout not found at $loadstoneRepo (set LOADSTONE_REPO)."
    }
    if (-not $env:LOADSTONE_WX_STATIC) {
        throw "Set LOADSTONE_WX_STATIC to your static wxWidgets build (e.g. C:\dev\wx-static); see Loadstone's README."
    }
    $build = Join-Path $loadstoneRepo 'build-blindfold-installer'
    $profile = Join-Path $repo 'installer\profile.json'
    # cmake/cargo write progress to stderr; route through cmd so PowerShell 5.1
    # doesn't promote those lines to errors under ErrorActionPreference Stop.
    & cmd /c "cmake -S `"$loadstoneRepo\app`" -B `"$build`" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=`"$env:LOADSTONE_WX_STATIC`" -DLOADSTONE_EMBED_PROFILE=`"$profile`" -DLOADSTONE_APP_NAME=BlindfoldInstaller 2>&1"
    if ($LASTEXITCODE -ne 0) { throw "cmake configure failed (run from a Visual Studio developer prompt)" }
    & cmd /c "cmake --build `"$build`" 2>&1"
    if ($LASTEXITCODE -ne 0) { throw "cmake build failed" }
    Copy-Item (Join-Path $build 'BlindfoldInstaller.exe') $installerExe -Force
    Write-Host "   $installerExe"
}

# --- Loadstone release manifest ----------------------------------------------------
# loadstone-release.json describes this release to Loadstone Mod Manager: version, the
# manager zip's sha256, the frozen install steps, and the installer exe. Must be
# built from the same files that get uploaded — never regenerate it against a
# rebuilt zip or exe.
Write-Step "Building loadstone-release.json (Loadstone)"
if (Get-Command loadstone -ErrorAction SilentlyContinue) {
    $packageArgs = @('package', '--version', $Version,
        '--manifest', (Join-Path $repo 'loadstone-packages\blindfold.json'),
        '--artifact', $managerZip,
        '--out', (Join-Path $repo 'loadstone-release.json'))
    if (-not $NoInstaller) { $packageArgs += @('--installer', $installerExe) }
    # The macOS installer, built on a Mac (build_release_macos.sh --installer-only)
    # and copied here first, so Mac installers can self-update from this release too.
    $macInstaller = Join-Path $repo 'BlindfoldInstaller.app.zip'
    if (Test-Path $macInstaller) {
        $packageArgs += @('--installer', $macInstaller)
    } else {
        Write-Warning "No BlindfoldInstaller.app.zip in the repo root - this release won't offer macOS installers an update."
    }
    & loadstone @packageArgs
    if ($LASTEXITCODE -ne 0) { throw "loadstone package failed" }
} else {
    Write-Warning "loadstone CLI not found on PATH - skipping loadstone-release.json (install: cargo install --path <loadstone repo>\crates\loadstone-cli)"
}

Write-Host ""
Write-Host "Done. Publish with:"
Write-Host "  gh release create $Version Blindfold.zip Blindfold-loadstone.zip loadstone-release.json BlindfoldInstaller.exe BlindfoldInstaller.app.zip --title $Version --notes `"...`""
Write-Host "  BlindfoldInstaller.app.zip is built on a Mac (scripts/build_release_macos.sh $Version --installer-only)"
Write-Host "  and copied here BEFORE this script runs, so loadstone-release.json lists it for self-update."
Write-Host "NOTE: keep Blindfold.zip FIRST in that list. Old standalone installers"
Write-Host "download the first .zip asset on the release; upload order preserves that."
