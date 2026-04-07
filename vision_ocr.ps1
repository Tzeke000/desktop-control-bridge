#Requires -Version 5.1
<#
.SYNOPSIS
  Run local OCR (RapidOCR) on a screenshot. No cloud; never prints BRIDGE_TOKEN.

.PARAMETER ImagePath
  Path to an image file. If empty, uses the newest .png in the OpenClaw bridge-vision workspace.

.PARAMETER EnvFile
  Optional .env path; applies BRIDGE_VISION_WORKSPACE to the environment when present.

.PARAMETER WorkspaceDir
  Override vision workspace directory for default (latest) mode.

.PARAMETER NoPreprocess
  Skip grayscale / contrast / resize.

.PARAMETER QuietMeta
  Text only (Python --quiet-meta).
#>
param(
    [string]$EnvFile = '',
    [string]$WorkspaceDir = '',
    [switch]$NoPreprocess,
    [switch]$QuietMeta,
    [Parameter(Position = 0)]
    [string]$ImagePath = ''
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

if ($EnvFile) {
    $common = Join-Path $root 'bridge_ps_common.ps1'
    if (Test-Path -LiteralPath $common) {
        . $common
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
