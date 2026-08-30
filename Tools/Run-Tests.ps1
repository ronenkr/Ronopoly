<#
.SYNOPSIS
    Runs the Ronopoly test suite, one fresh PowerShell process per test file.

.DESCRIPTION
    The fresh process per file is NOT optional. A PowerShell 5.1 class cannot
    be redefined in a live session, so a long-lived test host silently keeps
    running the OLD definition of every class in Types.ps1 after an edit - and
    reports green while doing it.
#>
[CmdletBinding()]
param(
    [string]$Filter = '*',
    [switch]$Detailed
)

$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $PSScriptRoot
$files = @(Get-ChildItem -Path (Join-Path $root 'Tests') -Filter "$Filter.Tests.ps1" | Sort-Object Name)

if ($files.Count -eq 0) {
    Write-Host "No test files matched '$Filter' under $root\Tests" -ForegroundColor Yellow
    exit 1
}

$failed = 0
$started = Get-Date

foreach ($f in $files) {
    Write-Host ''
    Write-Host ('=' * 68) -ForegroundColor DarkGray
    Write-Host "  $($f.Name)" -ForegroundColor White
    Write-Host ('=' * 68) -ForegroundColor DarkGray

    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $f.FullName
    if ($LASTEXITCODE -ne 0) { $failed += $LASTEXITCODE }
}

$elapsed = (Get-Date) - $started
Write-Host ''
Write-Host ('=' * 68) -ForegroundColor DarkGray
if ($failed -eq 0) {
    Write-Host ("  ALL {0} FILES PASSED in {1:N1}s" -f $files.Count, $elapsed.TotalSeconds) -ForegroundColor Green
    exit 0
}
Write-Host ("  {0} TEST(S) FAILED across {1} files in {2:N1}s" -f $failed, $files.Count, $elapsed.TotalSeconds) -ForegroundColor Red
exit 1
