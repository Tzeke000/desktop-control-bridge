#Requires -Version 5.1
<#
.SYNOPSIS
  Local verification: .env present, configured port, GET /health, optional GET /status with Bearer token.

.PARAMETER SkipStatus
  Skip the authenticated /status call (only /health and config checks).
#>
param(
    [string]$ProjectRoot = $PSScriptRoot,
    [switch]$SkipStatus
)

$ErrorActionPreference = "Stop"
$failCount = 0
$script:EnvFilePath = $null

$bsCommon = Join-Path $PSScriptRoot "bridge_ps_common.ps1"
if (-not (Test-Path -LiteralPath $bsCommon)) {
    Write-Host "[FAIL] bridge_ps_common.ps1 not found" -ForegroundColor Red
    exit 1
}
. $bsCommon

function Test-Step {
    param([string]$Name, [scriptblock]$Script)
    try {
        & $Script
        Write-Host "[PASS] $Name" -ForegroundColor Green
    }
    catch {
        Write-Host "[FAIL] $Name - $($_.Exception.Message)" -ForegroundColor Red
        $script:failCount++
    }
}

function Write-SkipStep {
    param([string]$Name, [string]$Reason)
    Write-Host "[SKIP] $Name - $Reason" -ForegroundColor Yellow
}

Test-Step ".env file exists" {
    $p = Join-Path $ProjectRoot ".env"
    if (-not (Test-Path -LiteralPath $p)) {
        throw "Missing .env - copy .env.example to .env"
    }
    $script:EnvFilePath = $p
}

$vars = @{}
if ($script:EnvFilePath) {
    $vars = Get-BridgeDotEnv -Path $script:EnvFilePath
}

$hostIp = "127.0.0.1"
if ($vars["BRIDGE_HOST"] -and $vars["BRIDGE_HOST"].Trim()) {
    $bh = $vars["BRIDGE_HOST"].Trim()
    if ($bh -ne "127.0.0.1") {
        Write-Host "[FAIL] BRIDGE_HOST must be 127.0.0.1 for verify.ps1 (found: $bh)" -ForegroundColor Red
        exit 1
    }
    $hostIp = $bh
}

$port = 47821
if ($vars["BRIDGE_PORT"] -and $vars["BRIDGE_PORT"].Trim()) {
    $port = [int]$vars["BRIDGE_PORT"].Trim()
}
$token = ""
if ($vars["BRIDGE_TOKEN"]) {
    $token = [string]$vars["BRIDGE_TOKEN"].Trim()
}

Test-Step "BRIDGE_PORT configured and valid" {
    if ($vars["BRIDGE_PORT"] -and $vars["BRIDGE_PORT"].Trim()) {
        Write-Host "       Using BRIDGE_PORT=$port from .env" -ForegroundColor DarkGray
    }
    else {
        Write-Host "       BRIDGE_PORT not set; using default $port" -ForegroundColor DarkGray
    }
    if ($port -lt 1 -or $port -gt 65535) { throw "Invalid BRIDGE_PORT: $port" }
}

$base = "http://${hostIp}:$port"

Test-Step "GET /health ($base)" {
    $r = Invoke-RestMethod -Uri "$base/health" -Method Get -TimeoutSec 5
    if ($null -eq $r.ok) { throw "Response missing ok: $($r | ConvertTo-Json -Compress)" }
    if (-not $r.ok) { throw "health.ok is false" }
}

if ($SkipStatus) {
    Write-SkipStep "GET /status (Bearer)" "Skipped (-SkipStatus)"
}
elseif (-not $token) {
    Write-SkipStep "GET /status (Bearer)" "BRIDGE_TOKEN not set in .env"
}
else {
    Test-Step "GET /status (Bearer token from .env)" {
        $headers = @{ Authorization = "Bearer $token" }
        $r = Invoke-RestMethod -Uri "$base/status" -Method Get -Headers $headers -TimeoutSec 5
        if (-not $r.status) { throw "Unexpected body: $($r | ConvertTo-Json -Compress)" }
        Write-Host "       api status=$($r.status) control_enabled=$($r.control_enabled)" -ForegroundColor DarkGray
    }
}

Write-Host ""
if ($failCount -eq 0) {
    Write-Host "All executed checks passed ($base)." -ForegroundColor Green
    exit 0
}
else {
    Write-Host ('{0} check(s) failed.' -f $failCount) -ForegroundColor Red
    exit 1
}
