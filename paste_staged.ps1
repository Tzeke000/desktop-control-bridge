#Requires -Version 5.1
<#
.SYNOPSIS
  Optionally verify foreground window, then send Ctrl+V (and optionally Enter) via the bridge.

.DESCRIPTION
  Clipboard must already hold the exact payload (use clipboard_stage.ps1). This script does not modify the clipboard.
  Default does NOT press Enter — use -PressEnter only after you visually confirmed the paste.

.PARAMETER ExpectTitleContains
  Case-insensitive substring; if set, must match active window title or exit 1 before paste.

.PARAMETER ExpectProcessContains
  Case-insensitive substring against process_name; combine with title for tighter checks.

.PARAMETER VerifyOnly
  Only run foreground checks (if any); never paste.

.PARAMETER NoPaste
  After successful verification, exit without Ctrl+V (focus sanity check only).

.PARAMETER PressEnter
  After paste, press Enter once (submission) — use only when intended.

.PARAMETER DelayMs
  Delay after verification before paste (focus settle).
#>
param(
    [string]$EnvFile = '',
    [string]$ExpectTitleContains = '',
    [string]$ExpectProcessContains = '',
    [int]$DelayMs = 120,
    [switch]$VerifyOnly,
    [switch]$NoPaste,
    [switch]$PressEnter
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

$common = Join-Path $root 'bridge_ps_common.ps1'
if (-not (Test-Path -LiteralPath $common)) {
    Write-Host '[FAIL] paste_staged bridge_ps_common.ps1 not found' -ForegroundColor Red
    exit 1
}
. $common

try {
    Initialize-BridgeClient -ProjectRoot $root -EnvFile $EnvFile
}
catch {
    Write-Host "[FAIL] paste_staged config - $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

function Test-BridgeForegroundMatch {
    $a = Invoke-BridgeGet '/window/active' -Authenticated
    if (-not $a.active) {
        Write-Host '[FAIL] paste_staged no foreground window' -ForegroundColor Red
        return $false
    }
    $ti = $ExpectTitleContains.Trim()
    $pr = $ExpectProcessContains.Trim()
    if ($ti) {
        if ($a.active.title.ToLowerInvariant().IndexOf($ti.ToLowerInvariant()) -lt 0) {
            Write-Host '[FAIL] paste_staged title mismatch (expected substring not in active title)' -ForegroundColor Red
            return $false
        }
    }
    if ($pr) {
        $pn = [string]$a.active.process_name
        if (-not $pn -or $pn.ToLowerInvariant().IndexOf($pr.ToLowerInvariant()) -lt 0) {
            Write-Host '[FAIL] paste_staged process mismatch' -ForegroundColor Red
            return $false
        }
    }
    return $true
}

$wantCheck = $ExpectTitleContains.Trim() -or $ExpectProcessContains.Trim()
if ($VerifyOnly -and -not $wantCheck) {
    Write-Host '[FAIL] paste_staged -VerifyOnly requires -ExpectTitleContains and/or -ExpectProcessContains' -ForegroundColor Red
    exit 1
}

if ($wantCheck) {
    if (-not (Test-BridgeForegroundMatch)) {
        exit 1
    }
    Write-Host '[PASS] paste_staged foreground ok' -ForegroundColor Green
}

if ($VerifyOnly) {
    exit 0
}

if ($NoPaste) {
    Write-Host '[PASS] paste_staged (skip paste)' -ForegroundColor Green
    exit 0
}

Start-Sleep -Milliseconds $DelayMs
Invoke-BridgeJsonPost '/keyboard/hotkey' @{ keys = @('ctrl', 'v') }
if ($PressEnter) {
    Start-Sleep -Milliseconds 120
    Invoke-BridgeJsonPost '/keyboard/press' @{ key = 'enter' }
}
Write-Host '[PASS] paste_staged paste sent' -ForegroundColor Green
exit 0
