# Dot-source only: .\bridge_lifecycle.ps1
# Shared helpers for start/status/stop/restart_bridge scripts.

function Get-BridgeLifecycleMetaPath {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)
    Join-Path $ProjectRoot 'logs\bridge-lifecycle.json'
}

function Ensure-BridgeLogDir {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)
    $ld = Join-Path $ProjectRoot 'logs'
    if (-not (Test-Path -LiteralPath $ld)) {
        New-Item -ItemType Directory -Force -Path $ld | Out-Null
    }
}

function Read-BridgeLifecycleMeta {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)
    $mp = Get-BridgeLifecycleMetaPath -ProjectRoot $ProjectRoot
    if (-not (Test-Path -LiteralPath $mp)) {
        return $null
    }
    try {
        Get-Content -LiteralPath $mp -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        $null
    }
}

function Write-BridgeLifecycleMeta {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)]$Object
    )
    Ensure-BridgeLogDir -ProjectRoot $ProjectRoot
    $mp = Get-BridgeLifecycleMetaPath -ProjectRoot $ProjectRoot
    ($Object | ConvertTo-Json -Depth 6 -Compress) | Set-Content -LiteralPath $mp -Encoding UTF8
}

function Remove-BridgeLifecycleMeta {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)
    $mp = Get-BridgeLifecycleMetaPath -ProjectRoot $ProjectRoot
    if (Test-Path -LiteralPath $mp) {
        Remove-Item -LiteralPath $mp -Force
    }
}

function Get-BridgeResolvedPort {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [string]$EnvFile = ''
    )
    $common = Join-Path $ProjectRoot 'bridge_ps_common.ps1'
    if (-not (Test-Path -LiteralPath $common)) {
        return 47821
    }
    . $common
    $envPath = if ($EnvFile) {
        if ([IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $ProjectRoot $EnvFile }
    }
    else {
        Join-Path $ProjectRoot '.env'
    }
    $port = 47821
    if (Test-Path -LiteralPath $envPath) {
        $m = Get-BridgeDotEnv -Path $envPath
        if ($m['BRIDGE_PORT'] -and $m['BRIDGE_PORT'].Trim()) {
            try {
                $port = [int]$m['BRIDGE_PORT'].Trim()
            }
            catch { }
        }
    }
    return $port
}

function Get-BridgePythonExe {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)
    $v = Join-Path $ProjectRoot '.venv\Scripts\python.exe'
    if (Test-Path -LiteralPath $v) { return $v }
    return 'python'
}

function Test-BridgeHealthOk {
    param(
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutSec = 3
    )
    try {
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec $TimeoutSec
        return [bool]$r.ok
    }
    catch {
        return $false
    }
}

function Get-BridgeListenPid {
    param([Parameter(Mandatory = $true)][int]$Port)
    try {
        $rows = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
        if ($rows.Count -eq 0) {
            return $null
        }
        $p = $rows | Where-Object { $_.LocalAddress -eq '127.0.0.1' -or $_.LocalAddress -eq '::' } | Select-Object -First 1
        if (-not $p) { $p = $rows[0] }
        [int]$p.OwningProcess
    }
    catch {
        $null
    }
}

function Test-BridgePidLooksLikeRunner {
    param(
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [int]$TrustedMetaPid = -1,
        [switch]$TrustedAsListenOwner
    )
    try {
        $pr = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction Stop
        $line = [string]$pr.CommandLine
        if ($line -notmatch 'run\.py') {
            return $false
        }
        if ($TrustedMetaPid -ge 0 -and $ProcessId -eq $TrustedMetaPid) {
            return $true
        }
        if ($TrustedAsListenOwner) {
            return $true
        }
        $full = (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction SilentlyContinue).Path
        if (-not $full) { $full = $ProjectRoot }
        if ($line.IndexOf($full, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
        if ($line.IndexOf($ProjectRoot, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
        $exe = [string]$pr.ExecutablePath
        if ($exe -and $exe.IndexOf($full, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
        return $false
    }
    catch {
        $false
    }
}

function Stop-BridgeByPid {
    param(
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [switch]$Force
    )
    try {
        if ($Force) {
            Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        }
        else {
            Stop-Process -Id $ProcessId -ErrorAction Stop
        }
        return $true
    }
    catch {
        $false
    }
}
