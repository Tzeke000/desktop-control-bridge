#Requires -Version 5.1
<#
  Dot-source only: .\bridge_ps_common.ps1
  Shared helpers for bridge PowerShell scripts. Never writes BRIDGE_TOKEN to output.
#>

# UTF-8 console reduces garbled Unicode (paths, active-window titles, OCR) on Windows.
try {
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [Console]::OutputEncoding = $utf8
    [Console]::InputEncoding = $utf8
    $OutputEncoding = $utf8
    if ($Host -and $Host.UI -and $Host.UI.RawUI) {
        $Host.UI.RawUI.OutputEncoding = $utf8
    }
}
catch { }

function Get-BridgeAnchorsFilePath {
    <#
    .SYNOPSIS
      Resolve anchors JSON path: BRIDGE_ANCHORS_PATH from .env / env, else data/anchors.json under project root.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        [string]$EnvFile = ''
    )
    $envPath = if ($EnvFile) {
        if ([System.IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $ProjectRoot $EnvFile }
    }
    else {
        Join-Path $ProjectRoot '.env'
    }
    if (Test-Path -LiteralPath $envPath) {
        $m = Get-BridgeDotEnv -Path $envPath
        if ($m['BRIDGE_ANCHORS_PATH'] -and $m['BRIDGE_ANCHORS_PATH'].Trim()) {
            $p = $m['BRIDGE_ANCHORS_PATH'].Trim()
            if ([System.IO.Path]::IsPathRooted($p)) { return $p }
            return (Join-Path $ProjectRoot $p)
        }
    }
    if ($env:BRIDGE_ANCHORS_PATH -and $env:BRIDGE_ANCHORS_PATH.Trim()) {
        $p2 = $env:BRIDGE_ANCHORS_PATH.Trim()
        if ([System.IO.Path]::IsPathRooted($p2)) { return $p2 }
        return (Join-Path $ProjectRoot $p2)
    }
    Join-Path $ProjectRoot 'data\anchors.json'
}

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

function Set-BridgeClipboardFromUtf8File {
    <#
    .SYNOPSIS
      Copy exact text from a UTF-8 (no BOM) file to the Windows clipboard via an STA PowerShell child (reliable Unicode).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath
    )
    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        throw "Clipboard stage file not found: $LiteralPath"
    }
    $fullSource = (Resolve-Path -LiteralPath $LiteralPath).Path
    $escaped = $fullSource.Replace("'", "''")
    $inner = Join-Path ([IO.Path]::GetTempPath()) ("bridge_clip_sta_" + [Guid]::NewGuid().ToString('N') + '.ps1')
    $staBody = @"
Add-Type -AssemblyName System.Windows.Forms
`$enc = New-Object System.Text.UTF8Encoding `$false
`$t = [IO.File]::ReadAllText('$escaped', `$enc)
[System.Windows.Forms.Clipboard]::SetText(`$t)
"@
    try {
        Set-Content -LiteralPath $inner -Value $staBody -Encoding UTF8
        $p = Start-Process -FilePath "powershell.exe" -ArgumentList @(
            '-Sta', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $inner
        ) -Wait -PassThru -WindowStyle Hidden
        if ($p.ExitCode -ne 0) {
            throw "STA clipboard helper exit code $($p.ExitCode)"
        }
    }
    finally {
        Remove-Item -LiteralPath $inner -Force -ErrorAction SilentlyContinue
    }
}

function Set-BridgeClipboardTextUtf8 {
    <#
    .SYNOPSIS
      Put exact Unicode string on the clipboard (writes a temp UTF-8 file then uses Set-BridgeClipboardFromUtf8File).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("bridge_clip_src_" + [Guid]::NewGuid().ToString('N') + '.txt')
    try {
        $enc = New-Object System.Text.UTF8Encoding $false
        [IO.File]::WriteAllText($tmp, $Text, $enc)
        Set-BridgeClipboardFromUtf8File -LiteralPath $tmp
    }
    finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-BridgePython {
    <#
    .SYNOPSIS
      Run Python in UTF-8 mode so Korean/Unicode (paths, window titles, OCR) decodes correctly in Windows consoles and pipes.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )
    & $PythonExe -X utf8 @ArgumentList
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
    if (-not $r.original_path) { throw 'Response missing original_path' }
    if (-not $r.workspace_path) { throw 'Response missing workspace_path' }
    if (-not (Test-Path -LiteralPath $r.original_path)) { throw "Missing project file: $($r.original_path)" }
    if (-not (Test-Path -LiteralPath $r.workspace_path)) { throw "Missing workspace file: $($r.workspace_path)" }
    return $r
}
