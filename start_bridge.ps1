#Requires -Version 5.1
<#
.SYNOPSIS
  Start desktop-control-bridge (tray + API) in a new console window; avoid duplicate if /health already OK.

.PARAMETER EnvFile
  Optional .env path (relative to project root or absolute).
#>
param([string]$EnvFile = '')

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. (Join-Path $root 'bridge_lifecycle.ps1')

if (-not (Test-Path -LiteralPath (Join-Path $root 'run.py'))) {
    Write-Host '[FAIL] start_bridge: run.py not found (run from repo root?)' -ForegroundColor Red
    exit 1
}

$port = Get-BridgeResolvedPort -ProjectRoot $root -EnvFile $EnvFile
$py = Get-BridgePythonExe -ProjectRoot $root

if (Test-BridgeHealthOk -Port $port) {
    $lp = Get-BridgeListenPid -Port $port
    $meta0 = Read-BridgeLifecycleMeta -ProjectRoot $root
    $okPid = $false
    if ($lp) {
        $okPid = Test-BridgePidLooksLikeRunner -ProcessId $lp -ProjectRoot $root
        if (-not $okPid -and $meta0 -and $meta0.pid) {
            $okPid = Test-BridgePidLooksLikeRunner -ProcessId $lp -ProjectRoot $root -TrustedMetaPid ([int]$meta0.pid)
        }
        if (-not $okPid) {
            $okPid = Test-BridgePidLooksLikeRunner -ProcessId $lp -ProjectRoot $root -TrustedAsListenOwner
        }
    }
    if ($lp -and $okPid) {
        Ensure-BridgeLogDir -ProjectRoot $root
        Write-BridgeLifecycleMeta -ProjectRoot $root -Object @{
            pid            = $lp
            port           = $port
            lastKnownUtc   = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
            lastAction     = 'health-refresh'
            python         = $py
        }
    }
    Write-Host "[PASS] start_bridge: already running (health OK on 127.0.0.1:$port)" -ForegroundColor Green
    if ($lp) { Write-Host "       listen_pid=$lp" -ForegroundColor DarkGray }
    exit 0
}

$rootEsc = $root.Replace("'", "''")
$pyEsc = $py.Replace("'", "''")
$inner = "Set-Location -LiteralPath '$rootEsc'; & '$pyEsc' run.py"

Start-Process -FilePath "powershell.exe" -WorkingDirectory $root `
    -ArgumentList @('-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $inner) `
    | Out-Null

$deadline = (Get-Date).AddSeconds(28)
$up = $false
while ((Get-Date) -lt $deadline) {
    if (Test-BridgeHealthOk -Port $port -TimeoutSec 2) {
        $up = $true
        break
    }
    Start-Sleep -Milliseconds 500
}

if (-not $up) {
    Write-Host '[FAIL] start_bridge: health did not become OK (check the new window for errors)' -ForegroundColor Red
    exit 1
}

Start-Sleep -Milliseconds 400
$lp = Get-BridgeListenPid -Port $port
$verify = $false
if ($lp) {
    $verify = Test-BridgePidLooksLikeRunner -ProcessId $lp -ProjectRoot $root
    if (-not $verify) {
        $verify = Test-BridgePidLooksLikeRunner -ProcessId $lp -ProjectRoot $root -TrustedAsListenOwner
    }
}
if ($lp -and $verify) {
    Ensure-BridgeLogDir -ProjectRoot $root
    Write-BridgeLifecycleMeta -ProjectRoot $root -Object @{
        pid          = $lp
        port         = $port
        startedUtc   = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        python       = $py
        lastAction   = 'start'
    }
    Write-Host "[PASS] start_bridge: running on 127.0.0.1:$port listen_pid=$lp" -ForegroundColor Green
}
else {
    Write-Host "[PASS] start_bridge: health OK on 127.0.0.1:$port (listen PID not verified — check meta later)" -ForegroundColor Green
    if ($lp) { Write-Host "       listen_pid=$lp (unverified)" -ForegroundColor DarkYellow }
}
exit 0
