#Requires -Version 5.1
<#
.SYNOPSIS
  Run local OCR (RapidOCR) on a screenshot. No cloud; never prints BRIDGE_TOKEN.
#>
param(
    [string]$EnvFile = '',
    [string]$WorkspaceDir = '',
    [string]$Region = '',
    [string]$Crop = '',
    [switch]$ActiveWindow,
    [switch]$NoPreprocess,
    [switch]$QuietMeta,
    [Parameter(Position = 0)]
    [string]$ImagePath = ''
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

$common = Join-Path $root 'bridge_ps_common.ps1'
if (-not (Test-Path -LiteralPath $common)) {
    Write-Host '[FAIL] bridge_ps_common.ps1 not found' -ForegroundColor Red
    exit 1
}
. $common

$rx = 0
if ($Region.Trim()) { $rx++ }
if ($Crop.Trim()) { $rx++ }
if ($ActiveWindow) { $rx++ }
if ($rx -gt 1) {
    Write-Host '[FAIL] use only one of -Region, -Crop, -ActiveWindow' -ForegroundColor Red
    exit 1
}

if ($EnvFile) {
    $resolved = if ([System.IO.Path]::IsPathRooted($EnvFile)) {
        $EnvFile
    }
    else {
        Join-Path $root $EnvFile
    }
    if (Test-Path -LiteralPath $resolved) {
        $m = Get-BridgeDotEnv -Path $resolved
        if ($m['BRIDGE_VISION_WORKSPACE'] -and $m['BRIDGE_VISION_WORKSPACE'].Trim()) {
            $env:BRIDGE_VISION_WORKSPACE = $m['BRIDGE_VISION_WORKSPACE'].Trim()
        }
    }
}

$py = Join-Path $root '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $py)) {
    $py = 'python'
}

$scriptPath = Join-Path $root 'scripts\vision_ocr.py'
if (-not (Test-Path -LiteralPath $scriptPath)) {
    Write-Host '[FAIL] vision_ocr.py not found' -ForegroundColor Red
    exit 1
}

$argList = New-Object System.Collections.ArrayList
[void]$argList.Add($scriptPath)
if ($ImagePath -and $ImagePath.Trim()) {
    [void]$argList.Add($ImagePath.Trim())
}
if ($WorkspaceDir.Trim()) {
    [void]$argList.Add('--workspace-dir')
    [void]$argList.Add($WorkspaceDir.Trim())
}
if ($Region.Trim()) {
    [void]$argList.Add('--region')
    [void]$argList.Add($Region.Trim())
}
if ($Crop.Trim()) {
    [void]$argList.Add('--crop')
    [void]$argList.Add($Crop.Trim())
}
if ($ActiveWindow) {
    [void]$argList.Add('--active-window')
}
if ($NoPreprocess) {
    [void]$argList.Add('--no-preprocess')
}
if ($QuietMeta) {
    [void]$argList.Add('--quiet-meta')
}

& $py @($argList.ToArray())
$code = $LASTEXITCODE
if ($code -eq 0) {
    Write-Host '[PASS] vision_ocr' -ForegroundColor Green
    exit 0
}
Write-Host '[FAIL] vision_ocr' -ForegroundColor Red
exit 1
