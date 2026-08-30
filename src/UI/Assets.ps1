#
# Ronopoly - asset loading.
#
# Get-RonAssetImage returns an ImageSource for any key in the art catalogue.
# It prefers the pre-rendered PNG, and falls back to drawing the SAME vector
# live when the file is missing, stale, or the whole Assets folder has been
# deleted. That is what makes the build step a pure optimisation rather than a
# dependency: the game always looks identical, just slower to first paint.
#

$script:RonAssetManifest = $null
$script:RonAssetIndex    = @{}   # key -> manifest entry
$script:RonImageCache    = @{}   # key -> frozen ImageSource
$script:RonMakeIndex     = $null # key -> the scriptblock that draws it

function Initialize-RonAssets {
    param([switch]$IgnoreManifest)

    $script:RonImageCache = @{}
    $script:RonAssetIndex = @{}
    $script:RonAssetManifest = $null

    $script:RonMakeIndex = @{}
    foreach ($item in (Get-RonArtCatalogue)) { $script:RonMakeIndex[$item.Key] = $item }

    if ($IgnoreManifest) { return }

    $path = Get-RonPath 'Assets\manifest.json'
    if (-not (Test-Path -LiteralPath $path)) {
        Write-RonLog 'No asset manifest; drawing everything from vectors.' -Level Info -Category assets
        return
    }
    try {
        $script:RonAssetManifest = ConvertFrom-RonJson (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
        foreach ($entry in @($script:RonAssetManifest.Items)) { $script:RonAssetIndex[$entry.Key] = $entry }
        Write-RonLog "Loaded $($script:RonAssetIndex.Count) asset entries." -Level Info -Category assets
    }
    catch {
        # A corrupt manifest must not stop the game starting.
        Write-RonLog "Asset manifest unreadable ($($_.Exception.Message)); using vectors." -Level Warn -Category assets
        $script:RonAssetManifest = $null
        $script:RonAssetIndex = @{}
    }
}

function Get-RonAssetImage {
    param([Parameter(Mandatory)][string]$Key)

    if ($script:RonImageCache.ContainsKey($Key)) { return $script:RonImageCache[$Key] }
    if ($null -eq $script:RonMakeIndex) { Initialize-RonAssets }

    $image = $null

    if ($script:RonAssetIndex.ContainsKey($Key)) {
        $entry = $script:RonAssetIndex[$Key]
        $file  = Get-RonPath (Join-Path 'Assets' ([string]$entry.File -replace '/', '\'))
        if (Test-Path -LiteralPath $file) {
            try { $image = Import-RonBitmap -Path $file } catch { $image = $null }
        }
    }

    if ($null -eq $image) {
        $item = $script:RonMakeIndex[$Key]
        if ($null -eq $item) { throw "Get-RonAssetImage: no art registered for key '$Key'" }
        $drawing = & $item.Make
        $image = New-Object System.Windows.Media.DrawingImage $drawing
        $image.Freeze()
    }

    $script:RonImageCache[$Key] = $image
    return $image
}

# The default BitmapImage constructor loads LAZILY and keeps a lock on the file
# for the life of the process, which would stop Build-Assets.ps1 ever
# overwriting it. OnLoad reads it fully and immediately, then Freeze makes it
# cheap to share across every Image element on the board.
function Import-RonBitmap {
    param([Parameter(Mandatory)][string]$Path)
    $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
    $bmp.BeginInit()
    $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bmp.CreateOptions = [System.Windows.Media.Imaging.BitmapCreateOptions]::IgnoreImageCache
    $bmp.UriSource = New-Object System.Uri($Path)
    $bmp.EndInit()
    $bmp.Freeze()
    return $bmp
}

# Convenience wrappers so view code never builds key strings by hand.
function Get-RonTileImage   { param([int]$Index)     return (Get-RonAssetImage "tile.$Index") }
function Get-RonDeedImage   { param([int]$Index)     return (Get-RonAssetImage "deed.$Index") }
function Get-RonTokenImage  { param([string]$Token)  return (Get-RonAssetImage "token.$Token") }
function Get-RonDieImage    { param([int]$Value)     return (Get-RonAssetImage "die.$Value") }
function Get-RonHouseImage  { return (Get-RonAssetImage 'house') }
function Get-RonHotelImage  { return (Get-RonAssetImage 'hotel') }

# Builds a ready-to-place Image element with the scaling mode that keeps
# pre-rendered PNGs crisp when the Viewbox scales the board.
function New-RonImageElement {
    param(
        [Parameter(Mandatory)][string]$Key,
        [double]$Width = 0,
        [double]$Height = 0
    )
    $img = New-Object System.Windows.Controls.Image
    $img.Source = Get-RonAssetImage $Key
    $img.Stretch = [System.Windows.Media.Stretch]::Uniform
    [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, [System.Windows.Media.BitmapScalingMode]::HighQuality)
    if ($Width  -gt 0) { $img.Width  = $Width }
    if ($Height -gt 0) { $img.Height = $Height }
    return $img
}
