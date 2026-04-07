#Requires -Version 5.1
<#
.SYNOPSIS
  CLI wrapper for the local desktop control bridge (reads .env; never prints the token).

.PARAMETER EnvFile
  Optional path to .env. If relative, resolved from the project root (script directory).

.EXAMPLE
  .\invoke_bridge.ps1 health

.EXAMPLE
  .\invoke_bridge.ps1 status

.EXAMPLE
  .\invoke_bridge.ps1 open-url https://example.com

.EXAMPLE
  .\invoke_bridge.ps1 type 'Hello from the bridge'

.EXAMPLE
  .\invoke_bridge.ps1 hotkey ctrl,c

.EXAMPLE
  .\invoke_bridge.ps1 -EnvFile D:\secrets\bridge.env move 100 250
#>
param(
    [string]$EnvFile = '',
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet(
        'status', 'health', 'screenshot', 'open-url', 'app-open', 'type', 'hotkey', 'move', 'click',
        'mouse-test', 'notepad-test', 'browser-test', 'screenshot-test'
    )]
    [string]$Action,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArguments
)

$ErrorActionPreference = 'Stop'

$common = Join-Path $PSScriptRoot 'bridge_ps_common.ps1'
if (-not (Test-Path -LiteralPath $common)) {
    Write-Host '[FAIL] bridge_ps_common.ps1 not found next to invoke_bridge.ps1' -ForegroundColor Red
    exit 1
}
. $common

try {
    Initialize-BridgeClient -ProjectRoot $PSScriptRoot -EnvFile $EnvFile
}
catch {
    Write-Host "[FAIL] config - $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

function Invoke-One {
    param([scriptblock]$Block)
    try {
        & $Block
        return $true
    }
    catch {
        Write-Host "[FAIL] $Action - $($_.Exception.Message)" -ForegroundColor Red
        Write-BridgeFailDetail $_
        return $false
    }
}

$success = $false

switch ($Action) {
    'health' {
        $success = Invoke-One {
            $r = Invoke-BridgeGet '/health'
            if (-not $r.ok) { throw 'health.ok is not true' }
            Write-Host '[PASS] health' -ForegroundColor Green
        }
    }
    'status' {
        $success = Invoke-One {
            $r = Invoke-BridgeGet '/status' -Authenticated
            if (-not $r.status) { throw 'unexpected status response' }
            Write-Host '[PASS] status' -ForegroundColor Green
            Write-Host "       version=$($r.version) api_state=$($r.status) control_enabled=$($r.control_enabled)" -ForegroundColor DarkGray
        }
    }
    'screenshot' {
        $success = Invoke-One {
            $r = Invoke-BridgeJsonPost '/screenshot' @{}
            if (-not $r.path) { throw 'response missing path' }
            Write-Host '[PASS] screenshot' -ForegroundColor Green
            Write-Host "       path: $($r.path)" -ForegroundColor DarkGray
        }
    }
    'open-url' {
        if (-not $RemainingArguments -or $RemainingArguments.Count -lt 1) {
            Write-Host '[FAIL] open-url - requires <url>' -ForegroundColor Red
            exit 1
        }
        $url = $RemainingArguments[0]
        $success = Invoke-One {
            [void](Invoke-BridgeJsonPost '/browser/open-url' @{ url = $url; browser = 'default' })
            Write-Host '[PASS] open-url' -ForegroundColor Green
            Write-Host "       url_len=$($url.Length)" -ForegroundColor DarkGray
        }
    }
    'app-open' {
        if (-not $RemainingArguments -or $RemainingArguments.Count -lt 1) {
            Write-Host '[FAIL] app-open - requires <app>' -ForegroundColor Red
            exit 1
        }
        $app = $RemainingArguments[0]
        $success = Invoke-One {
            [void](Invoke-BridgeJsonPost '/app/open' @{ path_or_name = $app })
            Write-Host '[PASS] app-open' -ForegroundColor Green
            Write-Host "       target: $app" -ForegroundColor DarkGray
        }
    }
    'type' {
        if (-not $RemainingArguments -or $RemainingArguments.Count -lt 1) {
            Write-Host '[FAIL] type - requires <text>' -ForegroundColor Red
            exit 1
        }
        $text = [string]($RemainingArguments -join ' ')
        $success = Invoke-One {
            [void](Invoke-BridgeJsonPost '/keyboard/type' @{ text = $text; mode = 'type'; interval = 0 })
            Write-Host '[PASS] type' -ForegroundColor Green
            Write-Host "       chars=$($text.Length) (payload not logged)" -ForegroundColor DarkGray
        }
    }
    'hotkey' {
        if (-not $RemainingArguments -or $RemainingArguments.Count -lt 1) {
            Write-Host '[FAIL] hotkey - requires k1,k2,...' -ForegroundColor Red
            exit 1
        }
        $spec = ($RemainingArguments -join ' ').Trim()
        $keys = @(
            $spec.Split(',') |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
        )
        if ($keys.Count -lt 1) {
            Write-Host '[FAIL] hotkey - no keys after parse' -ForegroundColor Red
            exit 1
        }
        $success = Invoke-One {
            [void](Invoke-BridgeJsonPost '/keyboard/hotkey' @{ keys = [string[]]$keys })
            Write-Host '[PASS] hotkey' -ForegroundColor Green
            Write-Host "       keys: $($keys -join ' + ')" -ForegroundColor DarkGray
        }
    }
    'move' {
        if (-not $RemainingArguments -or $RemainingArguments.Count -lt 2) {
            Write-Host '[FAIL] move - requires <x> <y>' -ForegroundColor Red
            exit 1
        }
        $x = [int]$RemainingArguments[0]
        $y = [int]$RemainingArguments[1]
        $success = Invoke-One {
            [void](Invoke-BridgeJsonPost '/mouse/move' @{ x = $x; y = $y; duration = 0 })
            Write-Host '[PASS] move' -ForegroundColor Green
            Write-Host "       x=$x y=$y" -ForegroundColor DarkGray
        }
    }
    'click' {
        if (-not $RemainingArguments -or $RemainingArguments.Count -lt 1) {
            Write-Host '[FAIL] click - requires <button> (left|right|middle)' -ForegroundColor Red
            exit 1
        }
        $btn = $RemainingArguments[0].ToLowerInvariant()
        if ($btn -notin @('left', 'right', 'middle')) {
            Write-Host '[FAIL] click - button must be left, right, or middle' -ForegroundColor Red
            exit 1
        }
        $success = Invoke-One {
            [void](Invoke-BridgeJsonPost '/mouse/click' @{ button = $btn; clicks = 1 })
            Write-Host '[PASS] click' -ForegroundColor Green
            Write-Host "       button=$btn" -ForegroundColor DarkGray
        }
    }
    'mouse-test' {
        $success = Test-BridgeActionStep 'mouse-test (move 200,200 + left click)' {
            Invoke-BridgeSmoke_MouseTest
        }
    }
    'notepad-test' {
        $success = Test-BridgeActionStep 'notepad-test (open, focus, type)' {
            Invoke-BridgeSmoke_NotepadTest
        }
    }
    'browser-test' {
        $success = Test-BridgeActionStep 'browser-test (open https://example.com)' {
            Invoke-BridgeSmoke_BrowserTest
        }
    }
    'screenshot-test' {
        try {
            $p = Invoke-BridgeSmoke_ScreenshotTest
            Write-Host '[PASS] screenshot-test' -ForegroundColor Green
            Write-Host "       path: $p" -ForegroundColor DarkGray
            $success = $true
        }
        catch {
            Write-Host "[FAIL] screenshot-test - $($_.Exception.Message)" -ForegroundColor Red
            Write-BridgeFailDetail $_
            $success = $false
        }
    }
}

if ($success) {
    exit 0
}
exit 1
