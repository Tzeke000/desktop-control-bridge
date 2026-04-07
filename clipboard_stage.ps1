#Requires -Version 5.1
<#
.SYNOPSIS
  Place exact text on the Windows clipboard without typing into Notepad (avoids OCR/encoding contamination).

.DESCRIPTION
  Uses an STA PowerShell child with System.Windows.Forms.Clipboard for reliable Unicode and line breaks.
  Does not print payload text unless -ShowPayload is explicitly set.

.PARAMETER LiteralPath
  UTF-8 file to read (recommended for large or secret prompts).

.PARAMETER Text
  Inline string (short payloads only; shell quoting may be awkward for special characters).

.PARAMETER Stdin
  Read all of stdin as UTF-8 text (use: Get-Content -Raw -Encoding UTF8 p.txt | .\clipboard_stage.ps1 -Stdin).

.PARAMETER ShowPayload
  UNSAFE: echo full text to the host. Default is stats only.

.EXAMPLE
  .\clipboard_stage.ps1 -LiteralPath D:\prompts\draft.txt

.EXAMPLE
  Get-Content -Raw -Encoding UTF8 .\note.txt | .\clipboard_stage.ps1 -Stdin
#>
param(
    [string]$LiteralPath = '',
    [Alias('Path')]
    [string]$File = '',
    [string]$Text = '',
    [switch]$Stdin,
    [switch]$ShowPayload
)

$ErrorActionPreference = 'Stop'
$common = Join-Path $PSScriptRoot 'bridge_ps_common.ps1'
if (-not (Test-Path -LiteralPath $common)) {
    Write-Host '[FAIL] clipboard_stage bridge_ps_common.ps1 not found' -ForegroundColor Red
    exit 1
}
. $common

$path = if ($LiteralPath.Trim()) { $LiteralPath.Trim() } elseif ($File.Trim()) { $File.Trim() } else { '' }

$srcCount = 0
if ($path) { $srcCount++ }
if ($Text) { $srcCount++ }
if ($Stdin) { $srcCount++ }
if ($srcCount -ne 1) {
    Write-Host '[FAIL] clipboard_stage specify exactly one of -LiteralPath, -Text, or -Stdin' -ForegroundColor Red
    exit 1
}

try {
    if ($path) {
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Host '[FAIL] clipboard_stage file not found' -ForegroundColor Red
            exit 1
        }
        Set-BridgeClipboardFromUtf8File -LiteralPath $path
        $encUtf8 = New-Object System.Text.UTF8Encoding $false
        $fileText = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $path).Path, $encUtf8)
        $bytes = $encUtf8.GetByteCount($fileText)
        $lineCount = if ($fileText.Length -eq 0) { 0 } else { @($fileText -split "`r?`n").Count }
        Write-Host "[PASS] clipboard_stage source=file bytes=$bytes lines=$lineCount" -ForegroundColor Green
    }
    elseif ($Stdin) {
        $raw = [Console]::In.ReadToEnd()
        Set-BridgeClipboardTextUtf8 -Text $raw
        $enc = New-Object System.Text.UTF8Encoding $false
        $bn = $enc.GetByteCount($raw)
        $lines = if ($raw) { 1 + ($raw.ToCharArray() | Where-Object { $_ -eq [char]10 }).Count } else { 0 }
        Write-Host "[PASS] clipboard_stage source=stdin bytes=$bn lines~=$lines" -ForegroundColor Green
    }
    else {
        Set-BridgeClipboardTextUtf8 -Text $Text
        $enc = New-Object System.Text.UTF8Encoding $false
        $bn = $enc.GetByteCount($Text)
        $lines = if ($Text) { 1 + ($Text.ToCharArray() | Where-Object { $_ -eq [char]10 }).Count } else { 0 }
        Write-Host "[PASS] clipboard_stage source=inline bytes=$bn lines~=$lines" -ForegroundColor Green
    }
    if ($ShowPayload) {
        Add-Type -AssemblyName System.Windows.Forms
        $clip = [System.Windows.Forms.Clipboard]::GetText()
        Write-Host '--- payload begin (unsafe) ---'
        Write-Host $clip
        Write-Host '--- payload end ---'
    }
    exit 0
}
catch {
    Write-Host "[FAIL] clipboard_stage $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
