<#
.SYNOPSIS
    Pre-renders every Ronopoly vector drawing to PNG.

.DESCRIPTION
    Purely a CACHE WARMER. The app draws the identical vectors live when an
    asset is missing or stale (see Get-RonAssetImage), so this script can be
    skipped entirely, deleted, or run again at any time - the game looks the
    same either way, just with a slightly slower first paint.

    Must run STA: WPF's rendering stack requires it. The script relaunches
    itself if started in an MTA host.

.EXAMPLE
    powershell -STA -File .\Tools\Build-Assets.ps1
    .\Tools\Build-Assets.ps1 -Scale 3 -Force
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 4)][int]$Scale = 2,
    [switch]$Force,
    [switch]$Quiet
)

if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Write-Host 'Relaunching in an STA host (WPF rendering requires it)...' -ForegroundColor Yellow
    $argv = @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File', $PSCommandPath, '-Scale', $Scale)
    if ($Force) { $argv += '-Force' }
    & powershell.exe @argv
    exit $LASTEXITCODE
}

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\Bootstrap.ps1') -Scope Art

$root      = Split-Path -Parent $PSScriptRoot
$assetRoot = Join-Path $root 'Assets'
$manifestPath = Join-Path $assetRoot 'manifest.json'

$catalogue = Get-RonArtCatalogue
$started = Get-Date
$written = 0
$skipped = 0
$items = New-Object System.Collections.ArrayList

if (-not $Quiet) {
    Write-Host ''
    Write-Host "  Rendering $($catalogue.Count) assets at ${Scale}x into $assetRoot" -ForegroundColor Cyan
}

foreach ($item in $catalogue) {
    $target = Join-Path $assetRoot ($item.File -replace '/', '\')

    if (-not $Force -and (Test-Path -LiteralPath $target)) {
        # Nothing about a drawing changes without a code change, and a code
        # change is what -Force is for; an existing file is simply reused.
        $skipped++
    }
    else {
        $drawing = & $item.Make
        $bitmap  = ConvertTo-RonBitmap -Drawing $drawing -Width $item.W -Height $item.H -Scale $Scale
        [void](Save-RonBitmap -Bitmap $bitmap -Path $target)
        $written++
        if (-not $Quiet -and ($written % 20 -eq 0)) {
            Write-Host "    $written rendered..." -ForegroundColor DarkGray
        }
    }

    $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    [void]$items.Add([pscustomobject]@{
        Key    = $item.Key
        File   = $item.File
        W      = $item.W
        H      = $item.H
        Scale  = $Scale
        Sha256 = $hash
    })
}

# The sound bank caches on exactly the same terms, and for the same reason:
# synthesising it takes a couple of seconds, which is fine once and much too
# slow on every launch. Sound.ps1 touches no audio device, so this works on a
# machine with no speakers at all.
$soundsBuilt = Build-RonSoundCache -Force:$Force
if (-not $Quiet) {
    if ($soundsBuilt -gt 0) { Write-Host "    $soundsBuilt sounds synthesised..." -ForegroundColor DarkGray }
    else                    { Write-Host '    sounds already current' -ForegroundColor DarkGray }
}

$manifest = [pscustomobject]@{
    Version          = 1
    GeneratedUtc     = (Get-Date).ToUniversalTime().ToString('o')
    BoardLogicalSize = 1000
    Scale            = $Scale
    SoundVersion     = (Get-RonSoundBankVersion)
    Items            = $items.ToArray()
}
Set-Content -LiteralPath $manifestPath -Value (ConvertTo-RonJson $manifest -Pretty) -Encoding utf8

$elapsed = (Get-Date) - $started
if (-not $Quiet) {
    $bytes = (Get-ChildItem -LiteralPath $assetRoot -Recurse -File -Filter *.png | Measure-Object Length -Sum).Sum
    $wav = (Get-ChildItem -LiteralPath $assetRoot -Recurse -File -Filter *.wav | Measure-Object Length -Sum).Sum
    Write-Host ''
    Write-Host ("  {0} rendered, {1} reused, in {2:N1}s" -f $written, $skipped, $elapsed.TotalSeconds) -ForegroundColor Green
    Write-Host ("  {0:N1} MB of PNG and {1:N1} MB of WAV, manifest at {2}" -f ($bytes / 1MB), ($wav / 1MB), $manifestPath)
    Write-Host ''
}
exit 0
