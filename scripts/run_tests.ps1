# run_tests.ps1 - run every harness in tests\ against this checkout.
# Usage: scripts\run_tests.ps1 [-Lua path\to\lua.exe]
param([string]$Lua)

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $Lua) {
    $cmd = Get-Command lua -ErrorAction SilentlyContinue
    if ($cmd) { $Lua = $cmd.Source }
    elseif (Test-Path 'C:\Users\bradj\AppData\Local\Programs\Lua\bin\lua.exe') {
        $Lua = 'C:\Users\bradj\AppData\Local\Programs\Lua\bin\lua.exe'
    } else {
        Write-Error 'No lua interpreter found - pass -Lua path\to\lua.exe'
        exit 1
    }
}

$failed = @()
Get-ChildItem (Join-Path $repo 'tests') -Filter '*.lua' | Sort-Object Name | ForEach-Object {
    Write-Host "== $($_.Name)"
    # Route through cmd so lua's stderr doesn't trip PowerShell error handling.
    & cmd /c "`"$Lua`" `"$($_.FullName)`" `"$repo`" 2>&1"
    if ($LASTEXITCODE -ne 0) { $failed += $_.Name }
    Write-Host ''
}

if ($failed.Count -gt 0) {
    Write-Host "FAILED: $($failed -join ', ')"
    exit 1
}
Write-Host 'ALL SUITES PASS'
