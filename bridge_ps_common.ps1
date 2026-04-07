#Requires -Version 5.1
<#
  Dot-source only: .\bridge_ps_common.ps1
  Shared helpers for bridge PowerShell scripts. Never writes BRIDGE_TOKEN to output.
#>

function Get-BridgeDotEnv {
    param([string]$Path)
    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $map }
    Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#')) { return }
        $i = $line.IndexOf('=')
        if ($i -lt 1) { return }
        $key = $line.Substring(0, $i).Trim()
        $val = $line.Substring($i + 1).Trim()
        if ($val.Length -ge 2 -and (($val.StartsWith('"') -and $val.EndsWith('"')) -or ($val.StartsWith("'") -and $val.EndsWith("'")))) {
            $val = $val.Substring(1, $val.Length - 2)
        }
        $map[$key] = $val
    }
    $map
}

function Initialize-BridgeClient {
    param(
        [string]$ProjectRoot,
        [string]$EnvFile = ''
    )
    $envPath = if ($EnvFile) {
        if ([System.IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $ProjectRoot $EnvFile }
    }
    else {
        Join-Path $ProjectRoot '.env'
    }
    if (-not (Test-Path -LiteralPath $envPath)) {
        throw "Missing .env at $envPath"
    }
    $vars = Get-BridgeDotEnv -Path $envPath
    $hostIp = '127.0.0.1'
    if ($vars['BRIDGE_HOST'] -and $vars['BRIDGE_HOST'].Trim()) {
        $bh = $vars['BRIDGE_HOST'].Trim()
        if ($bh -ne '127.0.0.1') {
            throw "BRIDGE_HOST must be 127.0.0.1 for local bridge scripts (found: $bh)"
        }
        $hostIp = $bh
    }
    $port = 47821
    if ($vars['BRIDGE_PORT'] -and $vars['BRIDGE_PORT'].Trim()) {
        $port = [int]$vars['BRIDGE_PORT'].Trim()
    }
    if ($port -lt 1 -or $port -gt 65535) {
        throw "Invalid BRIDGE_PORT: $port"
    }
    $tok = ''
    if ($vars['BRIDGE_TOKEN']) {
        $tok = [string]$vars['BRIDGE_TOKEN'].Trim()
    }
    if (-not $tok) {
        throw 'BRIDGE_TOKEN is empty in .env'
    }
    $script:Bridge_BaseUrl = "http://${hostIp}:$port"
    $script:Bridge_BearerHeaders = @{ Authorization = "Bearer $tok" }
}

function Invoke-BridgeJsonPost {
    param(
        [string]$RelativePath,
        [hashtable]$BodyHashtable = @{},
        [int]$TimeoutSec = 120
    )
    $json
    if ($null -eq $BodyHashtable -or $BodyHashtable.Count -eq 0) {
        $json = '{}'
    }
    else {
        $json = $BodyHashtable | ConvertTo-Json -Compress -Depth 10
    }
    Invoke-RestMethod -Uri ($script:Bridge_BaseUrl + $RelativePath) -Method Post `
        -Headers $script:Bridge_BearerHeaders -ContentType 'application/json; charset=utf-8' `
        -Body $json -TimeoutSec $TimeoutSec
}

function Invoke-BridgeGet {
    param(
        [string]$RelativePath,
        [switch]$Authenticated,
        [int]$TimeoutSec = 60
    )
    if ($Authenticated) {
        Invoke-RestMethod -Uri ($script:Bridge_BaseUrl + $RelativePath) -Method Get `
            -Headers $script:Bridge_BearerHeaders -TimeoutSec $TimeoutSec
    }
    else {
        Invoke-RestMethod -Uri ($script:Bridge_BaseUrl + $RelativePath) -Method Get -TimeoutSec $TimeoutSec
    }
}

function Write-BridgeFailDetail {
    param($ErrorRecord)
    if ($ErrorRecord.Exception.Response) {
        try {
            $reader = New-Object System.IO.StreamReader($ErrorRecord.Exception.Response.GetResponseStream())
            $body = $reader.ReadToEnd()
            if ($body) { Write-Host "       $body" -ForegroundColor DarkYellow }
        }
        catch { }
    }
    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        Write-Host "       $($ErrorRecord.ErrorDetails.Message)" -ForegroundColor DarkYellow
    }
}

function Test-BridgeActionStep {
    param(
        [string]$Name,
        [scriptblock]$Script
    )
    try {
        & $Script
        Write-Host "[PASS] $Name" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[FAIL] $Name - $($_.Exception.Message)" -ForegroundColor Red
        Write-BridgeFailDetail $_
        return $false
    }
}

function Invoke-BridgeSmoke_MouseTest {
    Invoke-BridgeJsonPost '/mouse/move' @{ x = 200; y = 200; duration = 0 }
    Start-Sleep -Milliseconds 150
    Invoke-BridgeJsonPost '/mouse/click' @{ button = 'left'; x = 200; y = 200; clicks = 1 }
}

function Invoke-BridgeSmoke_NotepadTest {
    Invoke-BridgeJsonPost '/app/open' @{ path_or_name = 'notepad' }
    Start-Sleep -Seconds 1
    Invoke-BridgeJsonPost '/window/focus' @{ title = 'Notepad' }
    Start-Sleep -Milliseconds 400
    Invoke-BridgeJsonPost '/keyboard/type' @{ text = 'hello from emil bridge test'; mode = 'type'; interval = 0 }
}

function Invoke-BridgeSmoke_BrowserTest {
    Invoke-BridgeJsonPost '/browser/open-url' @{ url = 'https://example.com'; browser = 'default' }
}

function Invoke-BridgeSmoke_ScreenshotTest {
    $r = Invoke-BridgeJsonPost '/screenshot' @{}
    if (-not $r.path) { throw 'Response missing path' }
    if (-not (Test-Path -LiteralPath $r.path)) { throw "File not found: $($r.path)" }
    return $r.path
}
