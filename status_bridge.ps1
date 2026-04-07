#Requires -Version 5.1
<#
.SYNOPSIS
  Report bridge reachability on 127.0.0.1:<port> and listener PID when available.

.PARAMETER EnvFile
  Optional .env path for port resolution.
#>
param([string]$EnvFile = '')

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. (Join-Path $root 'bridge_lifecycle.ps1')

$port = Get-BridgeResolvedPort -ProjectRoot $root -EnvFile $EnvFile
$health = Test-BridgeHealthOk -Port $port -TimeoutSec 3
$listen = Get-BridgeListenPid -Port $port
$meta = Read-BridgeLifecycleMeta -ProjectRoot $root

Write-Host "project_root: $root"
Write-Host "port:         $port"
Write-Host "health:       $(if ($health) { 'OK' } else { 'DOWN' })"
Write-Host "reachable:    http://127.0.0.1:$port/health"
if ($listen) {
    Write-Host "listen_pid:   $listen"
    $looks = Test-BridgePidLooksLikeRunner -ProcessId $listen -ProjectRoot $root
    if (-not $looks -and $meta -and $meta.pid -and [int]$meta.pid -eq $listen) {
        $looks = Test-BridgePidLooksLikeRunner -ProcessId $listen -ProjectRoot $root -TrustedMetaPid ([int]$meta.pid)
    }
    if (-not $looks) {
        $looks = Test-BridgePidLooksLikeRunner -ProcessId $listen -ProjectRoot $root -TrustedAsListenOwner
    }
    Write-Host "pid_matches:  $(if ($looks) { 'yes (run.py / listen owner / meta)' } else { 'no' })"
}
else {
    Write-Host 'listen_pid:   (none)'
}
if ($meta) {
    Write-Host "meta_pid:     $($meta.pid)"
    if ($meta.startedUtc) { Write-Host "started_utc:  $($meta.startedUtc)" }
    if ($meta.lastKnownUtc) { Write-Host "lastKnown_utc: $($meta.lastKnownUtc)" }
}

if ($health) {
    Write-Host '[PASS] status_bridge: running' -ForegroundColor Green
    exit 0
}
Write-Host '[FAIL] status_bridge: stopped (no health)' -ForegroundColor Red
exit 1
