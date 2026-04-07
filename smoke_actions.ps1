#Requires -Version 5.1
<#
.SYNOPSIS
  Calls the desktop control bridge API for quick interactive smoke checks.

.PARAMETER Action
  Single action to run, or 'all' to run mouse, notepad, browser, and screenshot tests in order.
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet('mouse-test', 'notepad-test', 'browser-test', 'screenshot-test', 'all')]
    [string]$Action = 'all'
)

$ErrorActionPreference = 'Stop'

$common = Join-Path $PSScriptRoot 'bridge_ps_common.ps1'
if (-not (Test-Path -LiteralPath $common)) {
    Write-Host '[FAIL] bridge_ps_common.ps1 not found' -ForegroundColor Red
    exit 1
}
. $common

try {
    Initialize-BridgeClient -ProjectRoot $PSScriptRoot
}
catch {
    Write-Host "[FAIL] config - $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$toRun = @()
switch ($Action) {
    'all'     { $toRun = @('mouse-test', 'notepad-test', 'browser-test', 'screenshot-test') }
    default   { $toRun = @($Action) }
}

$failed = 0
foreach ($step in $toRun) {
    switch ($step) {
        'mouse-test' {
            $ok = Test-BridgeActionStep 'mouse-test (move 200,200 + left click)' { Invoke-BridgeSmoke_MouseTest }
            if (-not $ok) { $failed++ }
        }
        'notepad-test' {
            $ok = Test-BridgeActionStep 'notepad-test (open, focus, type)' { Invoke-BridgeSmoke_NotepadTest }
            if (-not $ok) { $failed++ }
        }
        'browser-test' {
            $ok = Test-BridgeActionStep 'browser-test (open https://example.com)' { Invoke-BridgeSmoke_BrowserTest }
            if (-not $ok) { $failed++ }
        }
        'screenshot-test' {
            try {
                $p = Invoke-BridgeSmoke_ScreenshotTest
                Write-Host '[PASS] screenshot-test' -ForegroundColor Green
                Write-Host "       path: $p" -ForegroundColor DarkGray
            }
            catch {
                Write-Host "[FAIL] screenshot-test - $($_.Exception.Message)" -ForegroundColor Red
                Write-BridgeFailDetail $_
                $failed++
            }
        }
    }
}

Write-Host ''
if ($failed -eq 0) {
    Write-Host 'All requested actions passed.' -ForegroundColor Green
    exit 0
}
else {
    Write-Host ('{0} action(s) failed.' -f $failed) -ForegroundColor Red
    exit 1
}
