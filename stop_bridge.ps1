#Requires -Version 5.1
<#
.SYNOPSIS
  Stop the bridge process if it can be verified (run.py + project path). Clears lifecycle meta.

.PARAMETER EnvFile
  Optional .env path for port resolution.
#>
param([string]$EnvFile = '')

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. (Join-Path $root 'bridge_lifecycle.ps1')

$port = Get-BridgeResolvedPort -ProjectRoot $root -EnvFile $EnvFile
$healthy = Test-BridgeHealthOk -Port $port

if (-not $healthy) {
    Remove-BridgeLifecycleMeta -ProjectRoot $root
    Write-Host "[PASS] stop_bridge: nothing to stop (no health on 127.0.0.1:$port)" -ForegroundColor Green
    exit 0
}

$listen = Get-BridgeListenPid -Port $port
$meta = Read-BridgeLifecycleMeta -ProjectRoot $root

$candidates = New-Object System.Collections.Generic.List[int]
foreach ($p in @($meta.pid, $listen)) {
    if ($null -eq $p) { continue }
    try {
        $i = [int]$p
        if ($i -gt 0 -and -not $candidates.Contains($i)) { $candidates.Add($i) }
    }
    catch { }
}

$target = $null
foreach ($c in $candidates) {
    if (Test-BridgePidLooksLikeRunner -ProcessId $c -ProjectRoot $root) {
        $target = $c
        break
    }
    if ($c -eq $listen -and (Test-BridgePidLooksLikeRunner -ProcessId $c -ProjectRoot $root -TrustedAsListenOwner)) {
        $target = $c
        break
    }
    if ($meta -and $meta.pid -and $c -eq [int]$meta.pid) {
        if (Test-BridgePidLooksLikeRunner -ProcessId $c -ProjectRoot $root -TrustedMetaPid ([int]$meta.pid)) {
            $target = $c
            break
        }
    }
}

if (-not $target -and $listen -and (Test-BridgePidLooksLikeRunner -ProcessId $listen -ProjectRoot $root -TrustedAsListenOwner)) {
    $target = $listen
}

if (-not $target) {
    Write-Host '[FAIL] stop_bridge: API up but could not verify a run.py process for this project; not killing' -ForegroundColor Red
    Write-Host '       Manually close the tray window or identify PID with Get-NetTCPConnection' -ForegroundColor DarkYellow
    exit 1
}

$ok = Stop-BridgeByPid -ProcessId $target -Force
if (-not $ok) {
    Write-Host "[FAIL] stop_bridge: Stop-Process failed for pid=$target" -ForegroundColor Red
    exit 1
}

$deadline = (Get-Date).AddSeconds(12)
while ((Get-Date) -lt $deadline) {
    if (-not (Test-BridgeHealthOk -Port $port -TimeoutSec 1)) {
        break
    }
    Start-Sleep -Milliseconds 300
}

Remove-BridgeLifecycleMeta -ProjectRoot $root

if (Test-BridgeHealthOk -Port $port -TimeoutSec 1) {
    Write-Host '[WARN] stop_bridge: health still OK; process tree may need manual close' -ForegroundColor Yellow
    exit 1
}

Write-Host "[PASS] stop_bridge: stopped pid=$target (127.0.0.1:$port down)" -ForegroundColor Green
exit 0
