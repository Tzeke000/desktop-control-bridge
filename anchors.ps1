#Requires -Version 5.1
<#
.SYNOPSIS
  Local-first JSON store for named screen anchors (click points / regions).

.EXAMPLE
  .\anchors.ps1 list
  .\anchors.ps1 list -App Cursor
  .\anchors.ps1 get -App Cursor -Name composer_input_fullscreen
  .\anchors.ps1 add -App Cursor -Name my_target -X 100 -Y 200 -Description "..." -ExpectProcess cursor
  .\anchors.ps1 update -App Cursor -Name my_target -X 150 -Y 250
  .\anchors.ps1 remove -App Cursor -Name my_target
  .\anchors.ps1 export -ExportPath D:\backup\anchors.json
  .\anchors.ps1 path
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet('list', 'get', 'add', 'update', 'remove', 'export', 'path')]
    [string]$Command = 'list',
    [string]$EnvFile = '',
    [string]$App = '',
    [string]$Name = '',
    [string]$Condition = '',
    [int]$X = -2147483648,
    [int]$Y = -2147483648,
    [int]$Width = -2147483648,
    [int]$Height = -2147483648,
    [string]$Description = '',
    [string]$Notes = '',
    [string]$ExpectProcess = '',
    [string]$ExpectTitle = '',
    [double]$Confidence = -1.0,
    [string]$Tags = '',
    [string]$ExportPath = ''
)

$ErrorActionPreference = 'Stop'
$omit = [int]::MinValue
$root = $PSScriptRoot

$common = Join-Path $root 'bridge_ps_common.ps1'
if (-not (Test-Path -LiteralPath $common)) {
    Write-Host '[FAIL] anchors.ps1 requires bridge_ps_common.ps1' -ForegroundColor Red
    exit 1
}
. $common

$storePath = Get-BridgeAnchorsFilePath -ProjectRoot $root -EnvFile $EnvFile

function Read-AnchorsDoc([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return @{ version = 1; anchors = New-Object System.Collections.ArrayList }
    }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if (-not $raw -or -not $raw.Trim()) {
        return @{ version = 1; anchors = New-Object System.Collections.ArrayList }
    }
    $j = $raw | ConvertFrom-Json
    $ver = 1
    if ($null -ne $j.version) { $ver = [int]$j.version }
    $list = New-Object System.Collections.ArrayList
    foreach ($a in @($j.anchors)) {
        [void]$list.Add($a)
    }
    return @{ version = $ver; anchors = $list }
}

function AnchorToHashtable($a) {
    $tags = @()
    if ($a.tags) { $tags = @($a.tags) }
    return @{
        app                     = [string]$a.app
        name                    = [string]$a.name
        condition               = if ($null -eq $a.condition) { '' } else { [string]$a.condition }
        x                       = [int]$a.x
        y                       = [int]$a.y
        width                   = $a.width
        height                  = $a.height
        description             = if ($null -eq $a.description) { '' } else { [string]$a.description }
        notes                   = if ($null -eq $a.notes) { '' } else { [string]$a.notes }
        expect_process_contains = if ($null -eq $a.expect_process_contains) { '' } else { [string]$a.expect_process_contains }
        expect_title_contains   = if ($null -eq $a.expect_title_contains) { '' } else { [string]$a.expect_title_contains }
        confidence              = $a.confidence
        tags                    = $tags
        created_at              = [string]$a.created_at
        updated_at              = [string]$a.updated_at
    }
}

function Write-AnchorsDoc($doc, [string]$Path) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $out = @{ version = [int]$doc.version; anchors = @() }
    foreach ($a in $doc.anchors) {
        $out.anchors += AnchorToHashtable $a
    }
    ($out | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $Path -Encoding UTF8
}

function MatchAnchor($a, [string]$app, [string]$name, [string]$condition) {
    if ($a.app -ne $app) { return $false }
    if ($a.name -ne $name) { return $false }
    $c = ''
    if ($null -ne $a.condition -and "$($a.condition)" -ne '') { $c = [string]$a.condition }
    if ($c -ne $condition) { return $false }
    return $true
}

function NowUtcIso() {
    [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
}

try {
    switch ($Command) {
        'path' {
            Write-Host $storePath
            exit 0
        }
        'list' {
            $doc = Read-AnchorsDoc $storePath
            $filter = $App.Trim().ToLowerInvariant()
            $i = 0
            foreach ($a in $doc.anchors) {
                if ($filter -and $a.app.ToLowerInvariant().IndexOf($filter) -lt 0) { continue }
                $tags = ''
                if ($a.tags) { $tags = ($a.tags -join ',') }
                Write-Host ("[{0}] {1} / {2} [{3}] -> ({4},{5}) tags=[{6}]" -f $i, $a.app, $a.name, $a.condition, $a.x, $a.y, $tags)
                if ($a.description) { Write-Host "     $($a.description)" -ForegroundColor DarkGray }
                $i++
            }
            Write-Host "[PASS] anchors list (file: $storePath)" -ForegroundColor Green
            exit 0
        }
        'get' {
            if (-not $App.Trim() -or -not $Name.Trim()) {
                Write-Host '[FAIL] get requires -App and -Name' -ForegroundColor Red
                exit 1
            }
            $doc = Read-AnchorsDoc $storePath
            $cond = if ($null -eq $Condition) { '' } else { $Condition.Trim() }
            $hit = $null
            foreach ($a in $doc.anchors) {
                if (MatchAnchor $a $App.Trim() $Name.Trim() $cond) {
                    $hit = $a
                    break
                }
            }
            if (-not $hit) {
                Write-Host '[FAIL] anchor not found' -ForegroundColor Red
                exit 1
            }
            ($hit | ConvertTo-Json -Depth 10)
            exit 0
        }
        'add' {
            if (-not $App.Trim() -or -not $Name.Trim()) {
                Write-Host '[FAIL] add requires -App -Name -X -Y' -ForegroundColor Red
                exit 1
            }
            if ($X -eq $omit -or $Y -eq $omit) {
                Write-Host '[FAIL] add requires -X and -Y' -ForegroundColor Red
                exit 1
            }
            $doc = Read-AnchorsDoc $storePath
            $cond = if ($null -eq $Condition) { '' } else { $Condition.Trim() }
            foreach ($a in $doc.anchors) {
                if (MatchAnchor $a $App.Trim() $Name.Trim() $cond) {
                    Write-Host '[FAIL] anchor already exists (use update)' -ForegroundColor Red
                    exit 1
                }
            }
            $tagList = @()
            if ($Tags.Trim()) {
                $tagList = @($Tags.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            }
            $w = $null
            $h = $null
            if ($Width -ne $omit -and $Height -ne $omit) {
                if ($Width -lt 1 -or $Height -lt 1) {
                    Write-Host '[FAIL] width/height must be positive if set' -ForegroundColor Red
                    exit 1
                }
                $w = $Width
                $h = $Height
            }
            $conf = $null
            if ($Confidence -ge 0.0) { $conf = $Confidence }
            $ts = NowUtcIso
            $rec = [ordered]@{
                app                     = $App.Trim()
                name                    = $Name.Trim()
                condition               = $cond
                x                       = $X
                y                       = $Y
                width                   = $w
                height                  = $h
                description             = $Description
                notes                   = $Notes
                expect_process_contains = $ExpectProcess
                expect_title_contains   = $ExpectTitle
                confidence              = $conf
                tags                    = $tagList
                created_at              = $ts
                updated_at              = $ts
            }
            [void]$doc.anchors.Add(([pscustomobject]$rec))
            Write-AnchorsDoc $doc $storePath
            Write-Host '[PASS] anchors add' -ForegroundColor Green
            exit 0
        }
        'update' {
            if (-not $App.Trim() -or -not $Name.Trim()) {
                Write-Host '[FAIL] update requires -App -Name' -ForegroundColor Red
                exit 1
            }
            $doc = Read-AnchorsDoc $storePath
            $cond = if ($null -eq $Condition) { '' } else { $Condition.Trim() }
            $idx = -1
            for ($i = 0; $i -lt $doc.anchors.Count; $i++) {
                if (MatchAnchor $doc.anchors[$i] $App.Trim() $Name.Trim() $cond) {
                    $idx = $i
                    break
                }
            }
            if ($idx -lt 0) {
                Write-Host '[FAIL] anchor not found' -ForegroundColor Red
                exit 1
            }
            $a = $doc.anchors[$idx]
            $ht = AnchorToHashtable $a
            if ($X -ne $omit) { $ht.x = $X }
            if ($Y -ne $omit) { $ht.y = $Y }
            if ($Width -ne $omit) {
                if ($Width -lt 1) {
                    $ht.width = $null
                    $ht.height = $null
                }
                else {
                    $ht.width = $Width
                }
            }
            if ($Height -ne $omit) {
                if ($Height -ge 1) { $ht.height = $Height }
            }
            if ($Description) { $ht.description = $Description }
            if ($Notes) { $ht.notes = $Notes }
            if ($ExpectProcess) { $ht.expect_process_contains = $ExpectProcess }
            if ($ExpectTitle) { $ht.expect_title_contains = $ExpectTitle }
            if ($Confidence -ge 0.0) { $ht.confidence = $Confidence }
            if ($Tags.Trim()) {
                $ht.tags = @($Tags.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            }
            $ht.updated_at = NowUtcIso
            $doc.anchors[$idx] = [pscustomobject]$ht
            Write-AnchorsDoc $doc $storePath
            Write-Host '[PASS] anchors update' -ForegroundColor Green
            exit 0
        }
        'remove' {
            if (-not $App.Trim() -or -not $Name.Trim()) {
                Write-Host '[FAIL] remove requires -App -Name' -ForegroundColor Red
                exit 1
            }
            $doc = Read-AnchorsDoc $storePath
            $cond = if ($null -eq $Condition) { '' } else { $Condition.Trim() }
            $next = New-Object System.Collections.ArrayList
            $removed = $false
            foreach ($a in $doc.anchors) {
                if (MatchAnchor $a $App.Trim() $Name.Trim() $cond) {
                    $removed = $true
                    continue
                }
                [void]$next.Add($a)
            }
            if (-not $removed) {
                Write-Host '[FAIL] anchor not found' -ForegroundColor Red
                exit 1
            }
            $doc.anchors = $next
            Write-AnchorsDoc $doc $storePath
            Write-Host '[PASS] anchors remove' -ForegroundColor Green
            exit 0
        }
        'export' {
            if (-not $ExportPath.Trim()) {
                Write-Host '[FAIL] export requires -ExportPath' -ForegroundColor Red
                exit 1
            }
            if (-not (Test-Path -LiteralPath $storePath)) {
                Write-Host '[FAIL] nothing to export (store missing)' -ForegroundColor Red
                exit 1
            }
            Copy-Item -LiteralPath $storePath -Destination $ExportPath.Trim() -Force
            Write-Host "[PASS] anchors exported to $ExportPath" -ForegroundColor Green
            exit 0
        }
    }
}
catch {
    Write-Host "[FAIL] anchors - $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
