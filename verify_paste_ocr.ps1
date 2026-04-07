#Requires -Version 5.1
<#
.SYNOPSIS
  Lightweight "what text is on screen now" after a paste: screenshot + OCR a focused band (default: center), with context metadata.

.PARAMETER ActiveWindow
  OCR only the foreground window crop (good when the target app is focused).

.PARAMETER Content
  Use --region content (skip top browser chrome band).

.PARAMETER Perception
  Use vision_ocr --perception tuning.

.PARAMETER QuietOcr
  OCR lines only (no vision_ocr header).
#>
param(
    [string]$EnvFile = '',
    [switch]$ActiveWindow,
    [switch]$Content,
    [switch]$Perception,
    [switch]$FilterNoise,
    [switch]$Compact,
    [switch]$QuietOcr
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$vs = Join-Path $root 'vision_snapshot.ps1'
if ($Content -and $ActiveWindow) {
    Write-Host '[FAIL] verify_paste_ocr: use only one of -Content or -ActiveWindow' -ForegroundColor Red
    exit 1
}
$splat = @{
    EnvFile      = $EnvFile
    Context      = $true
    QuietOcr     = $QuietOcr
    Perception   = $Perception
    FilterNoise  = $FilterNoise
    Compact      = $Compact
}
if ($ActiveWindow) { $splat['ActiveWindow'] = $true }
elseif ($Content) { $splat['Region'] = 'content' }
else { $splat['Region'] = 'center' }
& $vs @splat
exit $LASTEXITCODE
