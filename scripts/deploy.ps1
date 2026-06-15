# deploy.ps1 — link the mod's src/ folder into Balatro's Mods directory.
#
# Uses a directory junction so edits in the repo are live immediately (just
# relaunch the game). Run once; after that, iterate by editing src/ and
# restarting Balatro. No admin rights needed for a junction.

$ErrorActionPreference = 'Stop'

$src  = (Resolve-Path (Join-Path $PSScriptRoot '..\src')).Path
$mods = Join-Path $env:APPDATA 'Balatro\Mods'
$link = Join-Path $mods 'balatro-access'

New-Item -ItemType Directory -Force -Path $mods | Out-Null

if (Test-Path $link) {
    $item = Get-Item $link -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Write-Host "Junction already present: $link -> $src"
        return
    }
    Write-Error "A real folder already exists at '$link'. Remove it manually, then re-run."
}

New-Item -ItemType Junction -Path $link -Target $src | Out-Null
Write-Host "Linked $link -> $src"
Write-Host "Make sure Lovely Injector is installed, then launch Balatro."
