#Requires -Version 5.1
<#
.SYNOPSIS
  Verify OpenClaw vision folder and that bridge screenshot copy works (optional API call).

.PARAMETER SkipApi
  Only check/create vision folder and list newest PNG (no live screenshot).

.PARAMETER EnvFile
  Optional .env path for API checks.
#>
param(
    [switch]$SkipApi,
    [string]$EnvFile = ''
)

$ErrorActionPreference = 'Stop'

function Get-DefaultVisionWorkspace {
    Join-Path $env:USERPROFILE '.openclaw\workspace\bridge-vision'
}

function Get-VisionWorkspacePath {
    param(
        [hashtable]$Vars,
        [string]$ProjectRoot
    )
    if ($Vars['BRIDGE_VISION_WORKSPACE'] -and $Vars['BRIDGE_VISION_WORKSPACE'].Trim()) {
        $p = $Vars['BRIDGE_VISION_WORKSPACE'].Trim()
        if ([System.IO.Path]::IsPathRooted($p)) { return $p }
        return (Join-Path $ProjectRoot $p)
    }
    return Get-DefaultVisionWorkspace
}

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

$root = $PSScriptRoot
$resolvedEnv = if ($EnvFile) {
    if ([System.IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $root $EnvFile }
}
else {
    Join-Path $root '.env'
}

$common = Join-Path $root 'bridge_ps_common.ps1'
if (-not (Test-Path -LiteralPath $common)) {
    Write-Host '[FAIL] bridge_ps_common.ps1 not found' -ForegroundColor Red
    exit 1
}
. $common

$script:vars = @{}
Step 'project .env exists' {
    if (-not (Test-Path -LiteralPath $resolvedEnv)) {
        throw "Missing .env at $resolvedEnv"
    }
    $script:vars = Get-BridgeDotEnv -Path $resolvedEnv
}

$vars = $script:vars
$visionDir = Get-VisionWorkspacePath -Vars $vars -ProjectRoot $root

Step 'vision workspace folder exists' {
    if (-not (Test-Path -LiteralPath $visionDir)) {
        New-Item -ItemType Directory -Force -Path $visionDir | Out-Null
    }
    if (-not (Test-Path -LiteralPath $visionDir)) {
        throw "Cannot create or access $visionDir"
    }
    Write-Host "       $visionDir" -ForegroundColor DarkGray
}

if (-not $SkipApi) {
    Step 'screenshot API returns both paths and files on disk' {
        Initialize-BridgeClient -ProjectRoot $root -EnvFile $EnvFile
        $r = Invoke-BridgeJsonPost '/screenshot' @{}
        if (-not $r.original_path -or -not $r.workspace_path) {
            throw 'API missing original_path or workspace_path'
        }
        if (-not (Test-Path -LiteralPath $r.original_path)) {
            throw "original missing: $($r.original_path)"
        }
        if (-not (Test-Path -LiteralPath $r.workspace_path)) {
            throw "workspace missing: $($r.workspace_path)"
        }
        Write-Host "       original=  $($r.original_path)" -ForegroundColor DarkGray
        Write-Host "       workspace= $($r.workspace_path)" -ForegroundColor DarkGray
    }

    Step 'newest PNG in workspace' {
        $latest = Get-ChildItem -LiteralPath $visionDir -Filter '*.png' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if (-not $latest) { throw "No .png files under $visionDir" }
        if ($latest.LastWriteTimeUtc -lt [datetime]::UtcNow.AddMinutes(-3)) {
            throw "Newest PNG is older than 3 minutes: $($latest.Name)"
        }
        Write-Host "       $($latest.FullName) ($($latest.LastWriteTime))" -ForegroundColor DarkGray
    }
}
else {
    Step 'newest PNG in workspace (optional, -SkipApi)' {
        $latest = Get-ChildItem -LiteralPath $visionDir -Filter '*.png' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($latest) {
            Write-Host "       $($latest.FullName)" -ForegroundColor DarkGray
        }
        else {
            Write-Host '       (no PNG files yet)' -ForegroundColor Yellow
        }
    }
}

Write-Host ''
if ($script:failCount -eq 0) {
    Write-Host 'Vision readiness: OK' -ForegroundColor Green
    exit 0
}
Write-Host ('Vision readiness: {0} step(s) failed.' -f $script:failCount) -ForegroundColor Red
exit 1
