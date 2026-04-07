#Requires -Version 5.1
<#
.SYNOPSIS
  Move to a saved anchor and click via the bridge (optional safety check vs foreground window).

.PARAMETER NoVerify
  Skip expect_process_contains / expect_title_contains checks.

.PARAMETER MoveOnly
  Move mouse only (no click).

.PARAMETER DoubleClick
  Double-click at target.

.PARAMETER ScreenshotAfter
  After click, POST /screenshot (same as invoke_bridge click-screenshot timing).

.PARAMETER Condition
  Disambiguate anchor when multiple conditions share app+name.
#>
param(
    [string]$EnvFile = '',
    [Parameter(Mandatory = $true)]
    [string]$App,
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [string]$Condition = '',
    [switch]$NoVerify,
    [switch]$MoveOnly,
    [switch]$DoubleClick,
    [switch]$ScreenshotAfter
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

$common = Join-Path $root 'bridge_ps_common.ps1'
if (-not (Test-Path -LiteralPath $common)) {
    Write-Host '[FAIL] click_anchor bridge_ps_common.ps1 not found' -ForegroundColor Red
    exit 1
}
. $common

$storePath = Get-BridgeAnchorsFilePath -ProjectRoot $root -EnvFile $EnvFile

function Read-AnchorsDoc([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Anchors file not found: $Path"
    }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $j = $raw | ConvertFrom-Json
    $list = New-Object System.Collections.ArrayList
    foreach ($a in @($j.anchors)) {
        [void]$list.Add($a)
    }
    return @{ version = $j.version; anchors = $list }
}

function Resolve-OneAnchor($doc, [string]$AppIn, [string]$NameIn, [string]$ConditionIn) {
    $appL = $AppIn.Trim().ToLowerInvariant()
    $nameL = $NameIn.Trim().ToLowerInvariant()
    $cands = @($doc.anchors | Where-Object {
            $_.app.ToLowerInvariant() -eq $appL -and $_.name.ToLowerInvariant() -eq $nameL
        })
    if ($cands.Count -eq 0) {
        throw "No anchor for app=$AppIn name=$NameIn"
    }
    if ($ConditionIn.Trim()) {
        $c2 = @($cands | Where-Object { [string]$_.condition -eq $ConditionIn.Trim() })
        if ($c2.Count -eq 1) { return $c2[0] }
        throw "Condition '$ConditionIn' did not match exactly for this anchor"
    }
    $pref = @($cands | Where-Object { -not $_.condition -or [string]$_.condition -eq '' })
    if ($pref.Count -eq 1) { return $pref[0] }
    if ($cands.Count -eq 1) { return $cands[0] }
    throw "Ambiguous anchor ($($cands.Count) matches); pass -Condition"
}

try {
    Initialize-BridgeClient -ProjectRoot $root -EnvFile $EnvFile
}
catch {
    Write-Host "[FAIL] click_anchor config - $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

try {
    $doc = Read-AnchorsDoc $storePath
    $rec = Resolve-OneAnchor $doc $App $Name $Condition

    if (-not $NoVerify) {
        $procNeed = ([string]$rec.expect_process_contains).Trim()
        $titleNeed = ([string]$rec.expect_title_contains).Trim()
        if ($procNeed -or $titleNeed) {
            $active = Invoke-BridgeGet '/window/active' -Authenticated
            if (-not $active.active) {
                throw 'No foreground window (cannot verify anchor safety)'
            }
            if ($procNeed) {
                $pn = [string]$active.active.process_name
                if ($pn.ToLowerInvariant().IndexOf($procNeed.ToLowerInvariant()) -lt 0) {
                    throw "Foreground process '$pn' does not contain required '$procNeed'"
                }
            }
            if ($titleNeed) {
                $ttl = [string]$active.active.title
                if ($ttl.ToLowerInvariant().IndexOf($titleNeed.ToLowerInvariant()) -lt 0) {
                    throw "Foreground title does not contain required '$titleNeed'"
                }
            }
            Write-Host '[PASS] click_anchor foreground check' -ForegroundColor Green
        }
    }

    $cx = [int]$rec.x
    $cy = [int]$rec.y
    $w = $rec.width
    $h = $rec.height
    if ($null -ne $w -and $null -ne $h) {
        try {
            $wi = [int]$w
            $hi = [int]$h
            if ($wi -gt 0 -and $hi -gt 0) {
                $cx = [int]([double]$rec.x + $wi / 2.0)
                $cy = [int]([double]$rec.y + $hi / 2.0)
            }
        }
        catch { }
    }

    [void](Invoke-BridgeJsonPost '/mouse/move' @{ x = $cx; y = $cy; duration = 0 })
    Start-Sleep -Milliseconds 80

    if (-not $MoveOnly) {
        $clicks = 1
        if ($DoubleClick) { $clicks = 2 }
        [void](Invoke-BridgeJsonPost '/mouse/click' @{ button = 'left'; x = $cx; y = $cy; clicks = $clicks })
    }

    if ($ScreenshotAfter) {
        Start-Sleep -Milliseconds 220
        $cap = Invoke-BridgeJsonPost '/screenshot' @{}
        Write-Host "[PASS] click_anchor screenshot workspace=$($cap.workspace_path)" -ForegroundColor Green
    }

    Write-Host "[PASS] click_anchor -> ($cx,$cy) move_only=$MoveOnly" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "[FAIL] click_anchor - $($_.Exception.Message)" -ForegroundColor Red
    Write-BridgeFailDetail $_
    exit 1
}
