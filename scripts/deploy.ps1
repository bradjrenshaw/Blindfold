# deploy.ps1 — one-command install for Blindfold (testers and dev alike).
#
#   1. Finds your Balatro install (Steam registry + library folders; override
#      with -GameDir).
#   2. Installs the bundled Lovely Injector (third_party\lovely\version.dll)
#      next to Balatro.exe.
#   3. Links %APPDATA%\Balatro\Mods\Blindfold -> <repo>\src as a directory
#      junction, so a plain `git pull` updates the installed mod (restart the
#      game to pick changes up). No admin rights needed for the link; writing
#      version.dll into a Program Files game folder MAY need an elevated
#      PowerShell — the script says so if it hits that.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1
#   ... -GameDir "D:\Games\Balatro"    explicit game folder (contains Balatro.exe)
#   ... -Uninstall                     remove the mod link (Lovely is left alone)

param(
    [string]$GameDir,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$src  = Join-Path $repo 'src'
$mods = Join-Path $env:APPDATA 'Balatro\Mods'
$link = Join-Path $mods 'Blindfold'

function Write-Step($msg) { Write-Host "== $msg" }

# --- Uninstall ---------------------------------------------------------------
if ($Uninstall) {
    if (Test-Path $link) {
        $item = Get-Item $link -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $item.Delete()
            Write-Host "Removed mod link: $link"
        } else {
            Write-Warning "'$link' is a real folder, not this script's link; not touching it."
        }
    } else {
        Write-Host "Mod link not present; nothing to remove."
    }
    Write-Host "Lovely Injector (version.dll in the game folder) was left in place."
    return
}

# --- 1. Locate Balatro ---------------------------------------------------------
function Find-Balatro {
    param([string]$Override)
    if ($Override) {
        if (Test-Path (Join-Path $Override 'Balatro.exe')) { return $Override }
        throw "No Balatro.exe under '$Override'."
    }

    $libraries = New-Object System.Collections.Generic.List[string]
    $steam = $null
    try {
        $steam = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath
    } catch {}
    if ($steam) {
        $steam = $steam -replace '/', '\'
        $libraries.Add($steam)
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            $raw = Get-Content $vdf -Raw
            foreach ($m in [regex]::Matches($raw, '"path"\s+"([^"]+)"')) {
                $libraries.Add(($m.Groups[1].Value -replace '\\\\', '\'))
            }
        }
    }
    $libraries.Add('C:\Program Files (x86)\Steam')

    foreach ($lib in $libraries) {
        $dir = Join-Path $lib 'steamapps\common\Balatro'
        if (Test-Path (Join-Path $dir 'Balatro.exe')) { return $dir }
    }
    throw "Couldn't find Balatro. Re-run with: scripts\deploy.ps1 -GameDir 'C:\path\to\Balatro' (the folder containing Balatro.exe)."
}

Write-Step "Locating Balatro"
$game = Find-Balatro -Override $GameDir
Write-Host "   $game"

# --- 2. Lovely Injector ---------------------------------------------------------
Write-Step "Installing Lovely Injector"
$lovelySrc = Join-Path $repo 'third_party\lovely\version.dll'
if (-not (Test-Path $lovelySrc)) {
    throw "Bundled Lovely missing at '$lovelySrc' - incomplete checkout?"
}
$lovelyDst = Join-Path $game 'version.dll'
$needCopy = $true
if (Test-Path $lovelyDst) {
    if ((Get-FileHash $lovelySrc).Hash -eq (Get-FileHash $lovelyDst).Hash) {
        $needCopy = $false
        Write-Host "   already up to date"
    }
}
if ($needCopy) {
    try {
        Copy-Item $lovelySrc $lovelyDst -Force
        Write-Host "   installed version.dll"
    } catch {
        Write-Warning "Couldn't write into the game folder (elevation needed?)."
        Write-Warning "Either re-run this script from an elevated PowerShell, or copy manually:"
        Write-Warning "  '$lovelySrc'"
        Write-Warning "    -> '$lovelyDst'"
        throw
    }
}

# --- 3. Speech library sanity check --------------------------------------------
Write-Step "Checking speech library"
if (-not (Test-Path (Join-Path $src 'lib\prism.dll'))) {
    Write-Warning "Missing src\lib\prism.dll - the mod will run LOG-ONLY (no speech)."
} else {
    Write-Host "   Prism present"
}

# --- 4. Version stamp -----------------------------------------------------------
# The mod announces this at boot and update-checks against the tip of main.
# The post-merge hook (installed below) refreshes it on every git pull.
Write-Step "Stamping the version"
try {
    $sha = (git -C $repo rev-parse --short=7 HEAD 2>$null)
    if ($sha) {
        Set-Content -Path (Join-Path $src 'version') -Value "main@$sha" -Encoding Ascii -NoNewline
        Write-Host "   main@$sha"
        git -C $repo config core.hooksPath .githooks
    } else {
        Write-Warning "Not a git checkout? Version stamp skipped."
    }
} catch {
    Write-Warning "Version stamp failed: $_"
}

# --- 4b. Bundle the docs -----------------------------------------------------------
# README.md / changes.md live at the repo root but the in-game "View
# Documentation / View Changes" buttons open <mod>/docs/*, so copy them into
# src\docs (gitignored) — the junction then exposes them in the mod folder.
Write-Step "Bundling docs"
$docs = Join-Path $src 'docs'
New-Item -ItemType Directory -Force -Path $docs | Out-Null
foreach ($doc in 'README.md', 'changes.md') {
    $from = Join-Path $repo $doc
    if (Test-Path $from) {
        Copy-Item $from (Join-Path $docs $doc) -Force
        Write-Host "   $doc"
    } else {
        Write-Warning "   $doc not found at repo root - the in-game button will 404."
    }
}

# --- 5. Mod link ------------------------------------------------------------------
Write-Step "Linking the mod"
New-Item -ItemType Directory -Force -Path $mods | Out-Null
$srcFull = [IO.Path]::GetFullPath($src).TrimEnd('\')
if (Test-Path $link) {
    $item = Get-Item $link -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        $target = @($item.Target)[0]
        $targetFull = if ($target) { [IO.Path]::GetFullPath($target).TrimEnd('\') } else { '' }
        if ($targetFull -eq $srcFull) {
            Write-Host "   already linked: $link"
        } else {
            $item.Delete()
            New-Item -ItemType Junction -Path $link -Target $src | Out-Null
            Write-Host "   re-linked (previously -> $target)"
        }
    } else {
        throw "A real folder already exists at '$link'. Remove it (it's another install of the mod), then re-run."
    }
} else {
    New-Item -ItemType Junction -Path $link -Target $src | Out-Null
    Write-Host "   $link -> $src"
}

Write-Host ""
Write-Host "Done. Launch Balatro through Steam - you should hear 'Blindfold loaded.'"
Write-Host "Update later with: git pull   (then restart the game)"
Write-Host "Uninstall with:    scripts\deploy.ps1 -Uninstall"
