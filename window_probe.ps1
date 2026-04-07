#Requires -Version 5.1
<#
.SYNOPSIS
  Print foreground window metadata (and optionally a filtered list of top-level windows).

.PARAMETER List
  Also list visible windows (filtered).

.PARAMETER TitleContains
  Filter list by case-insensitive title substring.

.PARAMETER ProcessContains
  Filter list by case-insensitive process name substring.

.PARAMETER Limit
  Max rows when -List (default 25).
#>
param(
    [string]$EnvFile = '',
    [switch]$List,
    [string]$TitleContains = '',
    [string]$ProcessContains = '',
    [int]$Limit = 25
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

$common = Join-Path $root 'bridge_ps_common.ps1'
if (-not (Test-Path -LiteralPath $common)) {
    Write-Host '[FAIL] window_probe bridge_ps_common.ps1 not found' -ForegroundColor Red
    exit 1
}
. $common

try {
    Initialize-BridgeClient -ProjectRoot $root -EnvFile $EnvFile
}
catch {
    Write-Host "[FAIL] window_probe config - $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

try {
    $ts = [DateTime]::UtcNow.ToString('o')
    Write-Host "probe_at_utc: $ts"
    $a = Invoke-BridgeGet '/window/active' -Authenticated
    if ($a.active) {
        Write-Host "active_hwnd: $($a.active.hwnd)"
        Write-Host "active_title: $($a.active.title)"
        Write-Host "active_process: $($a.active.process_name)"
        Write-Host "active_pid: $($a.active.pid)"
    }
    else {
        Write-Host 'active: (null)'
    }

    if (-not $List) {
        Write-Host '[PASS] window_probe' -ForegroundColor Green
        exit 0
    }

    $r = Invoke-BridgeGet '/windows' -Authenticated
    $ws = @($r.windows)
    $ti = $TitleContains.Trim().ToLowerInvariant()
    $pr = $ProcessContains.Trim().ToLowerInvariant()
    if ($ti) {
        $ws = $ws | Where-Object {
            $_.title -and ($_.title.ToLowerInvariant().IndexOf($ti) -ge 0)
        }
    }
    if ($pr) {
        $ws = $ws | Where-Object {
            $_.process_name -and ($_.process_name.ToLowerInvariant().IndexOf($pr) -ge 0)
        }
    }
    $shown = [Math]::Min($Limit, $ws.Count)
    Write-Host "list_matches: $($ws.Count) (showing first $shown)"
    $i = 0
    foreach ($w in $ws | Select-Object -First $Limit) {
        Write-Host "  [$i] hwnd=$($w.hwnd) pid=$($w.pid) proc=$($w.process_name) title=$($w.title)"
        $i++
    }
    Write-Host '[PASS] window_probe' -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "[FAIL] window_probe $($_.Exception.Message)" -ForegroundColor Red
    Write-BridgeFailDetail $_
    exit 1
}
