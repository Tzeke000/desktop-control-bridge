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
        'status', 'health', 'see', 'see-context', 'see-active',
        'screenshot', 'screenshot-context', 'open-url', 'app-open', 'type', 'hotkey', 'move', 'click',
        'mouse-test', 'notepad-test', 'browser-test', 'screenshot-test',
        'active-window', 'focus-window', 'list-windows',
        'stage-text-file', 'paste', 'paste-enter',
        'cursor-pos', 'move-rel', 'click-here', 'open-or-focus', 'click-screenshot'
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
    'see' {
        $vs = Join-Path $PSScriptRoot 'vision_snapshot.ps1'
        $splat = @{ EnvFile = $EnvFile }
        if ($RemainingArguments -and $RemainingArguments.Count -ge 1) {
            $rn = $RemainingArguments[0].Trim().ToLowerInvariant()
            if ($rn -in @('top', 'bottom', 'left', 'right', 'center', 'content', 'full')) {
                $splat['Region'] = $RemainingArguments[0].Trim()
            }
        }
        & $vs @splat
        $success = ($LASTEXITCODE -eq 0)
    }
    'see-context' {
        $vs = Join-Path $PSScriptRoot 'vision_snapshot.ps1'
        & $vs -EnvFile $EnvFile -Context
        $success = ($LASTEXITCODE -eq 0)
    }
    'see-active' {
        $vs = Join-Path $PSScriptRoot 'vision_snapshot.ps1'
        & $vs -EnvFile $EnvFile -ActiveWindow
        $success = ($LASTEXITCODE -eq 0)
    }
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
            if (-not $r.original_path) { throw 'response missing original_path' }
            if (-not $r.workspace_path) { throw 'response missing workspace_path' }
            Write-Host '[PASS] screenshot' -ForegroundColor Green
            Write-Host "       original_path: $($r.original_path)" -ForegroundColor DarkGray
            Write-Host "       workspace_path: $($r.workspace_path)" -ForegroundColor DarkGray
        }
    }
    'screenshot-context' {
        $success = Invoke-One {
            $r = Invoke-BridgeJsonPost '/screenshot/context' @{}
            if (-not $r.original_path) { throw 'response missing original_path' }
            if (-not $r.workspace_path) { throw 'response missing workspace_path' }
            Write-Host '[PASS] screenshot-context' -ForegroundColor Green
            Write-Host "       original_path: $($r.original_path)" -ForegroundColor DarkGray
            Write-Host "       workspace_path: $($r.workspace_path)" -ForegroundColor DarkGray
            Write-Host "       captured_at: $($r.captured_at)" -ForegroundColor DarkGray
            if ($r.active_window) {
                Write-Host "       active_title: $($r.active_window.title)" -ForegroundColor DarkGray
                Write-Host "       active_process: $($r.active_window.process_name)" -ForegroundColor DarkGray
            }
            else {
                Write-Host '       active_window: (null)' -ForegroundColor DarkGray
            }
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
            $r = Invoke-BridgeSmoke_ScreenshotTest
            Write-Host '[PASS] screenshot-test' -ForegroundColor Green
            Write-Host "       original_path: $($r.original_path)" -ForegroundColor DarkGray
            Write-Host "       workspace_path: $($r.workspace_path)" -ForegroundColor DarkGray
            $success = $true
        }
        catch {
            Write-Host "[FAIL] screenshot-test - $($_.Exception.Message)" -ForegroundColor Red
            Write-BridgeFailDetail $_
            $success = $false
        }
    }
    'active-window' {
        $success = Invoke-One {
            $r = Invoke-BridgeGet '/window/active' -Authenticated
            if ($r.active) {
                Write-Host '[PASS] active-window' -ForegroundColor Green
                Write-Host "       hwnd=$($r.active.hwnd) pid=$($r.active.pid)" -ForegroundColor DarkGray
                Write-Host "       process=$($r.active.process_name)" -ForegroundColor DarkGray
                Write-Host "       title=$($r.active.title)" -ForegroundColor DarkGray
            }
            else {
                Write-Host '[PASS] active-window (none)' -ForegroundColor Green
                Write-Host '       active: (null)' -ForegroundColor DarkGray
            }
        }
    }
    'focus-window' {
        if (-not $RemainingArguments -or $RemainingArguments.Count -lt 1) {
            Write-Host '[FAIL] focus-window - requires <title_substring> [process_name]' -ForegroundColor Red
            exit 1
        }
        $title = [string]$RemainingArguments[0]
        $proc = $null
        if ($RemainingArguments.Count -ge 2) {
            $proc = [string]$RemainingArguments[1]
        }
        $success = Invoke-One {
            $body = @{ title = $title }
            if ($proc) { $body['process_name'] = $proc }
            [void](Invoke-BridgeJsonPost '/window/focus' $body)
            Write-Host '[PASS] focus-window' -ForegroundColor Green
            Write-Host "       title=$title" -ForegroundColor DarkGray
            if ($proc) { Write-Host "       process_name=$proc" -ForegroundColor DarkGray }
        }
    }
    'list-windows' {
        $titleF = ''
        $procF = ''
        if ($RemainingArguments -and $RemainingArguments.Count -ge 1) { $titleF = $RemainingArguments[0] }
        if ($RemainingArguments -and $RemainingArguments.Count -ge 2) { $procF = $RemainingArguments[1] }
        $success = Invoke-One {
            $r = Invoke-BridgeGet '/windows' -Authenticated
            $ws = @($r.windows)
            if ($titleF) {
                $t = $titleF.ToLowerInvariant()
                $ws = $ws | Where-Object { $_.title -and $_.title.ToLowerInvariant().IndexOf($t) -ge 0 }
            }
            if ($procF) {
                $p = $procF.ToLowerInvariant()
                $ws = $ws | Where-Object { $_.process_name -and $_.process_name.ToLowerInvariant().IndexOf($p) -ge 0 }
            }
            Write-Host '[PASS] list-windows' -ForegroundColor Green
            Write-Host "       count=$($ws.Count)" -ForegroundColor DarkGray
            $i = 0
            foreach ($w in $ws | Select-Object -First 40) {
                Write-Host "       [$i] $($w.process_name) | $($w.title)" -ForegroundColor DarkGray
                $i++
            }
        }
    }
    'stage-text-file' {
        if (-not $RemainingArguments -or $RemainingArguments.Count -lt 1) {
            Write-Host '[FAIL] stage-text-file - requires <path>' -ForegroundColor Red
            exit 1
        }
        $pth = $RemainingArguments[0]
        $cs = Join-Path $PSScriptRoot 'clipboard_stage.ps1'
        & $cs -LiteralPath $pth
        $success = ($LASTEXITCODE -eq 0)
    }
    'paste' {
        $ps = Join-Path $PSScriptRoot 'paste_staged.ps1'
        & $ps -EnvFile $EnvFile
        $success = ($LASTEXITCODE -eq 0)
    }
    'paste-enter' {
        $ps = Join-Path $PSScriptRoot 'paste_staged.ps1'
        & $ps -EnvFile $EnvFile -PressEnter
        $success = ($LASTEXITCODE -eq 0)
    }
    'cursor-pos' {
        $success = Invoke-One {
            $r = Invoke-BridgeGet '/mouse/position' -Authenticated
            Write-Host '[PASS] cursor-pos' -ForegroundColor Green
            Write-Host "       x=$($r.x) y=$($r.y)" -ForegroundColor DarkGray
        }
    }
    'move-rel' {
        if (-not $RemainingArguments -or $RemainingArguments.Count -lt 2) {
            Write-Host '[FAIL] move-rel - requires <dx> <dy>' -ForegroundColor Red
            exit 1
        }
        $dx = [int]$RemainingArguments[0]
        $dy = [int]$RemainingArguments[1]
        $success = Invoke-One {
            [void](Invoke-BridgeJsonPost '/mouse/move-relative' @{ dx = $dx; dy = $dy; duration = 0 })
            Write-Host '[PASS] move-rel' -ForegroundColor Green
            Write-Host "       dx=$dx dy=$dy" -ForegroundColor DarkGray
        }
    }
    'click-here' {
        $success = Invoke-One {
            [void](Invoke-BridgeJsonPost '/mouse/click' @{ button = 'left'; clicks = 1 })
            Write-Host '[PASS] click-here (left at current position)' -ForegroundColor Green
        }
    }
    'click-screenshot' {
        $success = Invoke-One {
            [void](Invoke-BridgeJsonPost '/mouse/click' @{ button = 'left'; clicks = 1 })
            Start-Sleep -Milliseconds 250
            $cap = Invoke-BridgeJsonPost '/screenshot' @{}
            Write-Host '[PASS] click-screenshot' -ForegroundColor Green
            Write-Host "       workspace_path: $($cap.workspace_path)" -ForegroundColor DarkGray
        }
    }
    'open-or-focus' {
        if (-not $RemainingArguments -or $RemainingArguments.Count -lt 1) {
            Write-Host '[FAIL] open-or-focus - requires notepad|cursor|chrome|edge|powershell|pwsh' -ForegroundColor Red
            exit 1
        }
        $key = $RemainingArguments[0].Trim().ToLowerInvariant()
        $map = @{
            'notepad'    = @{ open = 'notepad'; title = 'Notepad'; proc = $null }
            'cursor'     = @{ open = 'cursor'; title = 'Cursor'; proc = $null }
            'chrome'     = @{ open = 'chrome'; title = 'Chrome'; proc = $null }
            'edge'       = @{ open = 'edge'; title = 'Edge'; proc = $null }
            'powershell' = @{ open = 'powershell'; title = 'PowerShell'; proc = $null }
            'pwsh'       = @{ open = 'pwsh'; title = $null; proc = 'pwsh' }
        }
        if (-not $map.ContainsKey($key)) {
            Write-Host '[FAIL] open-or-focus - unknown app key' -ForegroundColor Red
            exit 1
        }
        $info = $map[$key]
        $success = Invoke-One {
            [void](Invoke-BridgeJsonPost '/app/open' @{ path_or_name = $info.open })
            Start-Sleep -Milliseconds 650
            $fb = @{}
            if ($info.title) { $fb['title'] = $info.title }
            if ($info.proc) { $fb['process_name'] = $info.proc }
            [void](Invoke-BridgeJsonPost '/window/focus' $fb)
            Write-Host '[PASS] open-or-focus' -ForegroundColor Green
            Write-Host "       key=$key open=$($info.open) focus_title~=$($info.title)" -ForegroundColor DarkGray
        }
    }
}

if ($success) {
    exit 0
}
exit 1
