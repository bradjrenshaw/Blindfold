# run_game.ps1 - launch Balatro with Blindfold's dev server on, and BLOCK until
# the game exits. Meant to run as a background task: it finishes the moment
# the game quits or crashes, and meanwhile the live game is driven over
# http://127.0.0.1:8772 (see src\dev\server.lua and CLAUDE.md).
#
# The dev server is gated on a marker file in the save directory
# (%APPDATA%\Balatro\blindfold_dev.enable) rather than an environment
# variable, because Balatro launches through Steam and Steam doesn't pass our
# environment on. This script drops the marker; -Disable removes it.
#
#   -NoLaunch : only drop the marker (the next launch, however started, has
#               the dev server)
#   -Disable  : remove the marker and exit
param(
    [switch]$NoLaunch,
    [switch]$Disable
)

$ErrorActionPreference = 'Stop'
$Port = 8772
$marker = Join-Path $env:APPDATA 'Balatro\blindfold_dev.enable'

if ($Disable) {
    Remove-Item $marker -ErrorAction SilentlyContinue
    Write-Host "Dev server disabled (marker removed)."
    return
}

New-Item -ItemType Directory -Force -Path (Split-Path $marker) | Out-Null
Set-Content -Path $marker -Value '1' -Encoding Ascii
Write-Host "Dev server enabled: $marker"
if ($NoLaunch) { return }

if (Get-Process -Name Balatro -ErrorAction SilentlyContinue) {
    Write-Host "Balatro is already running - restart it to pick up the dev server (if it wasn't on)." -ForegroundColor Yellow
} else {
    Start-Process 'steam://rungameid/2379780'
    Write-Host "Launching Balatro through Steam; waiting for the dev server..." -ForegroundColor Cyan
}

$health = curl.exe -s --retry 90 --retry-connrefused --retry-delay 1 "http://127.0.0.1:$Port/health"
if ($health -match 'ok') {
    Write-Host "READY: dev server on http://127.0.0.1:$Port" -ForegroundColor Green
} else {
    Write-Host "WARNING: the dev server never answered /health - check blindfold.log." -ForegroundColor Yellow
}

# Block for the game's lifetime so a background run of this script ends when
# the game does.
$game = $null
$deadline = (Get-Date).AddSeconds(60)
while (-not $game -and (Get-Date) -lt $deadline) {
    $game = Get-Process -Name Balatro -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $game) { Start-Sleep -Milliseconds 500 }
}
if ($game) {
    $game.WaitForExit()
    Write-Host "Balatro exited."
} else {
    Write-Host "Balatro process not found."
}
