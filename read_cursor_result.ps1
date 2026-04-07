#Requires -Version 5.1
<#
.SYNOPSIS
  Print the latest Cursor completion handoff (cursor-handoff/cursor-last-result.json).

.PARAMETER Path
  Override path to the JSON file.

.PARAMETER Example
  Print the committed example template instead of the live file.
#>
param(
    [string]$Path = '',
    [switch]$Example
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$defaultPath = Join-Path $root 'cursor-handoff\cursor-last-result.json'
$examplePath = Join-Path $root 'cursor-handoff\cursor-last-result.example.json'

$file = if ($Path.Trim()) { $Path.Trim() } elseif ($Example) { $examplePath } else { $defaultPath }

if (-not (Test-Path -LiteralPath $file)) {
    Write-Host "[FAIL] read_cursor_result: file not found: $file" -ForegroundColor Red
    Write-Host "       Run a Cursor task that writes this path, or use -Example for the template." -ForegroundColor DarkYellow
    exit 1
}

$raw = Get-Content -LiteralPath $file -Raw -Encoding UTF8
try {
    $j = $raw | ConvertFrom-Json
}
catch {
    Write-Host '[FAIL] read_cursor_result: invalid JSON' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor DarkYellow
    exit 1
}

Write-Host '======== cursor-last-result ========' -ForegroundColor Cyan
Write-Host ('status:       {0}' -f $(if ($j.status) { $j.status } else { '(missing)' }))
Write-Host ('worked:       {0}' -f $(if ($null -ne $j.worked) { $j.worked } else { '(missing)' }))
Write-Host ('finished_at:  {0}' -f $(if ($j.finished_at) { $j.finished_at } else { '(missing)' }))
Write-Host ('commit_hash:  {0}' -f $(if ($j.commit_hash) { $j.commit_hash } else { '(none)' }))
Write-Host ''
Write-Host 'summary:'
Write-Host ('  {0}' -f $(if ($j.summary) { $j.summary } else { '(none)' }))
Write-Host ''
Write-Host 'changed_files:'
if ($j.changed_files -and @($j.changed_files).Count -gt 0) {
    foreach ($f in @($j.changed_files)) { Write-Host "  - $f" }
}
else {
    Write-Host '  (none)'
}
Write-Host ''
Write-Host 'commands_to_use:'
if ($j.commands_to_use -and @($j.commands_to_use).Count -gt 0) {
    foreach ($c in @($j.commands_to_use)) { Write-Host "  $c" }
}
else {
    Write-Host '  (none)'
}
Write-Host ''
Write-Host 'caveats:'
Write-Host ('  {0}' -f $(if ($j.caveats) { $j.caveats } else { '(none)' }))
Write-Host '====================================' -ForegroundColor Cyan
exit 0
