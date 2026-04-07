#Requires -Version 5.1
<#
.SYNOPSIS
  One-step "see now": bridge screenshot + local OCR on workspace copy (Emil perception loop).

.PARAMETER Context
  Use POST /screenshot/context (includes active-window metadata before capture).

.PARAMETER ActiveWindow
  OCR only the foreground window region (crop from full-screen PNG).

.PARAMETER Region
  Named crop: top, bottom, left, right, center, full.

.PARAMETER Crop
  Pixel crop X,Y,W,H passed to vision_ocr.py.

.PARAMETER EnvFile
  Passed through for .env / BRIDGE_VISION_WORKSPACE.

.PARAMETER NoPreprocess
  Forward to vision_ocr.py.

.PARAMETER QuietOcr
  OCR text only (no vision_ocr header).
#>
param(
    [string]$EnvFile = '',
    [switch]$Context,
    [switch]$ActiveWindow,
    [string]$Region = '',
    [string]$Crop = '',
    [switch]$NoPreprocess,
    [switch]$QuietOcr
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

$common = Join-Path $root 'bridge_ps_common.ps1'
if (-not (Test-Path -LiteralPath $common)) {
    Write-Host '[FAIL] bridge_ps_common.ps1 not found' -ForegroundColor Red
    exit 1
}
. $common

try {
    Initialize-BridgeClient -ProjectRoot $root -EnvFile $EnvFile
}
catch {
    Write-Host "[FAIL] vision_snapshot config - $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$opt = @()
if ($Region.Trim()) { $opt += '--region'; $opt += $Region.Trim() }
if ($Crop.Trim()) { $opt += '--crop'; $opt += $Crop.Trim() }
if ($ActiveWindow) { $opt += '--active-window' }
if ($NoPreprocess) { $opt += '--no-preprocess' }
if ($QuietOcr) { $opt += '--quiet-meta' }

$regionOpts = 0
if ($Region.Trim()) { $regionOpts++ }
if ($Crop.Trim()) { $regionOpts++ }
if ($ActiveWindow) { $regionOpts++ }
if ($regionOpts -gt 1) {
    Write-Host '[FAIL] use only one of -Region, -Crop, -ActiveWindow' -ForegroundColor Red
    exit 1
}

try {
    if ($Context) {
        $r = Invoke-BridgeJsonPost '/screenshot/context' @{}
    }
    else {
        $r = Invoke-BridgeJsonPost '/screenshot' @{}
    }
    if (-not $r.original_path -or -not $r.workspace_path) {
        throw 'screenshot response missing paths'
    }
    if (-not (Test-Path -LiteralPath $r.workspace_path)) {
        throw "workspace file missing: $($r.workspace_path)"
    }
}
catch {
    Write-Host "[FAIL] vision_snapshot screenshot - $($_.Exception.Message)" -ForegroundColor Red
    Write-BridgeFailDetail $_
    exit 1
}

Write-Host '========== vision_snapshot ==========' -ForegroundColor Cyan
Write-Host "original_path:  $($r.original_path)"
Write-Host "workspace_path: $($r.workspace_path)"
if ($Context -and $r.captured_at) {
    Write-Host "captured_at:    $($r.captured_at)"
}
if ($Context) {
    if ($r.active_window) {
        Write-Host "active_title:   $($r.active_window.title)"
        Write-Host "active_process: $($r.active_window.process_name)"
        Write-Host "active_pid:     $($r.active_window.pid)"
    }
    else {
        Write-Host 'active_window:  (null)'
    }
}
Write-Host '========== OCR ==========' -ForegroundColor Cyan

$py = Join-Path $root '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $py)) { $py = 'python' }
$ocrScript = Join-Path $root 'scripts\vision_ocr.py'
$allArgs = @($ocrScript, $r.workspace_path) + $opt
& $py @allArgs
$ocrExit = $LASTEXITCODE

Write-Host '========== end ==========' -ForegroundColor Cyan
if ($ocrExit -eq 0) {
    Write-Host '[PASS] vision_snapshot' -ForegroundColor Green
    exit 0
}
Write-Host '[FAIL] vision_snapshot (OCR step)' -ForegroundColor Red
exit 1
