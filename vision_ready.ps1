#Requires -Version 5.1
<#
.SYNOPSIS
  Vision + bridge readiness: reachability, workspace, screenshot handoff, local OCR.

.PARAMETER EnvFile
  Optional .env path.
#>
param(
    [string]$EnvFile = ''
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$script:failCount = 0

function Step {
    param([string]$Name, [scriptblock]$Sb)
    try {
        & $Sb
        Write-Host "[PASS] $Name" -ForegroundColor Green
    }
    catch {
        Write-Host "[FAIL] $Name - $($_.Exception.Message)" -ForegroundColor Red
        $script:failCount++
    }
}

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
    Write-Host "[FAIL] config - $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$py = Join-Path $root '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $py)) { $py = 'python' }
$ocrScript = Join-Path $root 'scripts\vision_ocr.py'

Step 'bridge GET /health' {
    $h = Invoke-BridgeGet '/health'
    if (-not $h.ok) { throw 'health not ok' }
}

Step 'bridge GET /status (authenticated)' {
    $s = Invoke-BridgeGet '/status' -Authenticated
    if (-not $s.status) { throw 'bad status payload' }
    Write-Host "       bridge_state=$($s.status) control=$($s.control_enabled)" -ForegroundColor DarkGray
}

$vars = @{}
$resolvedEnv = if ($EnvFile) {
    if ([System.IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $root $EnvFile }
}
else {
    Join-Path $root '.env'
}
if (Test-Path -LiteralPath $resolvedEnv) {
    $vars = Get-BridgeDotEnv -Path $resolvedEnv
}
function Get-DefaultVisionWorkspace {
    Join-Path $env:USERPROFILE '.openclaw\workspace\bridge-vision'
}
function Get-VisionWorkspacePath {
    param([hashtable]$V, [string]$ProjectRoot)
    if ($V['BRIDGE_VISION_WORKSPACE'] -and $V['BRIDGE_VISION_WORKSPACE'].Trim()) {
        $p = $V['BRIDGE_VISION_WORKSPACE'].Trim()
        if ([System.IO.Path]::IsPathRooted($p)) { return $p }
        return (Join-Path $ProjectRoot $p)
    }
    return Get-DefaultVisionWorkspace
}
$visionDir = Get-VisionWorkspacePath -V $vars -ProjectRoot $root

Step 'vision workspace folder exists' {
    if (-not (Test-Path -LiteralPath $visionDir)) {
        New-Item -ItemType Directory -Force -Path $visionDir | Out-Null
    }
    if (-not (Test-Path -LiteralPath $visionDir)) { throw "cannot use $visionDir" }
    Write-Host "       $visionDir" -ForegroundColor DarkGray
}

$script:lastWorkspacePath = ''
Step 'POST /screenshot handoff (original + workspace files)' {
    $r = Invoke-BridgeJsonPost '/screenshot' @{}
    if (-not $r.workspace_path) { throw 'no workspace_path' }
    if (-not (Test-Path -LiteralPath $r.original_path)) { throw 'missing original' }
    if (-not (Test-Path -LiteralPath $r.workspace_path)) { throw 'missing workspace copy' }
    $script:lastWorkspacePath = $r.workspace_path
    Write-Host "       workspace=$($r.workspace_path)" -ForegroundColor DarkGray
}

Step 'local OCR on workspace screenshot (RapidOCR)' {
    if (-not $script:lastWorkspacePath) { throw 'no path from previous step' }
    $oa = @($ocrScript, $script:lastWorkspacePath, '--quiet-meta')
    & $py @oa
    if ($LASTEXITCODE -ne 0) { throw "vision_ocr.py exit $LASTEXITCODE" }
}

Write-Host ''
if ($script:failCount -eq 0) {
    Write-Host 'vision_ready: all checks passed' -ForegroundColor Green
    exit 0
}
Write-Host ('vision_ready: {0} check(s) failed' -f $script:failCount) -ForegroundColor Red
exit 1
