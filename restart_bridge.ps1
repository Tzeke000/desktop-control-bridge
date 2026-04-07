#Requires -Version 5.1
<#
.SYNOPSIS
  stop_bridge.ps1 then start_bridge.ps1; optional pause between.

.PARAMETER EnvFile
  Optional .env path.

.PARAMETER WaitSeconds
  Sleep after stop before start (default 3).
#>
param(
    [string]$EnvFile = '',
    [int]$WaitSeconds = 3
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. (Join-Path $root 'bridge_lifecycle.ps1')

$stopS = Join-Path $root 'stop_bridge.ps1'
$startS = Join-Path $root 'start_bridge.ps1'

Write-Host '--- restart_bridge: stopping ---' -ForegroundColor Cyan
& $stopS -EnvFile $EnvFile
$stopCode = $LASTEXITCODE
# 0 = stopped or was already down; 1 = error — still try start if was "not verified"
if ($stopCode -ne 0) {
    Write-Host '[WARN] restart_bridge: stop returned non-zero; continuing with start' -ForegroundColor DarkYellow
}

if ($WaitSeconds -gt 0) {
    Write-Host "       waiting ${WaitSeconds}s..." -ForegroundColor DarkGray
    Start-Sleep -Seconds $WaitSeconds
}

Write-Host '--- restart_bridge: starting ---' -ForegroundColor Cyan
& $startS -EnvFile $EnvFile
$startCode = $LASTEXITCODE
if ($startCode -ne 0) {
    Write-Host '[FAIL] restart_bridge: start failed' -ForegroundColor Red
    exit 1
}

$port = Get-BridgeResolvedPort -ProjectRoot $root -EnvFile $EnvFile
if (Test-BridgeHealthOk -Port $port) {
    Write-Host '[PASS] restart_bridge: health OK after restart' -ForegroundColor Green
    exit 0
}
Write-Host '[FAIL] restart_bridge: health not OK after start' -ForegroundColor Red
exit 1
