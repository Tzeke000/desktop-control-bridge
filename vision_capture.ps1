#Requires -Version 5.1
<#
.SYNOPSIS
  Capture a bridge screenshot and print project + OpenClaw workspace paths (no token printed).

.PARAMETER EnvFile
  Optional .env path (same rules as other bridge scripts).

.PARAMETER Context
  Call POST /screenshot/context (includes active window + UTC timestamp).
#>
param(
    [string]$EnvFile = '',
    [switch]$Context
)

$ErrorActionPreference = 'Stop'

$common = Join-Path $PSScriptRoot 'bridge_ps_common.ps1'
if (-not (Test-Path -LiteralPath $common)) {
    Write-Host '[FAIL] bridge_ps_common.ps1 not found' -ForegroundColor Red
    exit 1
}
. $common

try {
    Initialize-BridgeClient -ProjectRoot $PSScriptRoot -EnvFile $EnvFile
}
catch {
    Write-Host "[FAIL] config - $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

try {
    $path = if ($Context) { '/screenshot/context' } else { '/screenshot' }
    $r = Invoke-BridgeJsonPost $path @{}
    if (-not $r.original_path) { throw 'Response missing original_path' }
    if (-not $r.workspace_path) { throw 'Response missing workspace_path' }
    if (-not (Test-Path -LiteralPath $r.original_path)) { throw "Missing file: $($r.original_path)" }
    if (-not (Test-Path -LiteralPath $r.workspace_path)) { throw "Missing file: $($r.workspace_path)" }

    Write-Host '[PASS] vision capture' -ForegroundColor Green
    Write-Host "original_path:  $($r.original_path)"
    Write-Host "workspace_path: $($r.workspace_path)"
    if ($Context) {
        Write-Host "captured_at:    $($r.captured_at)"
        if ($r.active_window) {
            Write-Host "active_title:   $($r.active_window.title)"
            Write-Host "active_process: $($r.active_window.process_name)"
        }
    }
    exit 0
}
catch {
    Write-Host "[FAIL] vision capture - $($_.Exception.Message)" -ForegroundColor Red
    Write-BridgeFailDetail $_
    exit 1
}
