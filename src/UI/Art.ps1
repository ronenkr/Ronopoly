#
# Ronopoly - all vector artwork.
#
# THE key structural decision of the UI layer: this file is dot-sourced by BOTH
# Tools\Build-Assets.ps1 (which renders each drawing to a PNG) and the running
# app (which falls back to drawing live when an asset is missing or stale).
# The pre-rendered PNGs are therefore a pure cache - a missing or corrupt
# Assets folder can never break the game, and the art has exactly one
# definition that cannot drift.
#
# Every routine returns a System.Windows.Media.DrawingGroup, which serves both
# consumers unchanged: wrap it in a DrawingImage for live WPF use, or
# DrawDrawing it into a DrawingVisual to rasterise.
#
# Board tiles are deliberately painted light-on-cream in BOTH themes, exactly
# as a printed board is. The dark/light theme changes the surround, the HUD and
# the chrome; that keeps a single set of tile assets instead of two.
#

# Logical drawing units. The board is authored at 1000x1000 and displayed
# inside a Viewbox, so these numbers never change with window size or DPI.
$script:RonArt = @{
    TileW    = 100.0
    TileH    = 162.0
    Corner   = 162.0
    BarH     = 34.0
    DeedW    = 320.0
    DeedH    = 470.0
    CardW    = 340.0
    CardH    = 220.0
    TokenPx  = 96.0
    DiePx    = 96.0
    HousePx  = 48.0
}

# The title deed's shape, so a panel can size itself around one without
# reaching into the drawing metrics.
function Get-RonDeedAspect { return ($script:RonArt.DeedW / $script:RonArt.DeedH) }

$script:RonPalette = @{
    TileFace   = '#FBF7EF'   # warm off-white, like printed card stock
    TileEdge   = '#2A2E35'
    TileInk    = '#1B1F26'
    TileInkDim = '#5C6470'
    BoardFelt  = '#CFE3D4'   # the classic pale green centre
    DeedFace   = '#FFFFFF'
    ChanceInk  = '#E8590C'
    ChestInk   = '#1971C2'
    HouseGreen = '#2F9E44'
    HouseDark  = '#1E7031'
    HotelRed   = '#E03131'
    HotelDark  = '#A32020'
    DieFace    = '#FFFFFF'
    DiePip     = '#1B1F26'
    Shadow     = '#33000000'
}

# --- primitives ------------------------------------------------------------

function New-RonBrush {
    param([string]$Hex)
    $c = [System.Windows.Media.ColorConverter]::ConvertFromString($Hex)
    $b = New-Object System.Windows.Media.SolidColorBrush $c
    $b.Freeze()
    return $b
}

function New-RonPen {
    param([string]$Hex, [double]$Thickness = 1.0)
    $p = New-Object System.Windows.Media.Pen((New-RonBrush $Hex), $Thickness)
    $p.Freeze()
    return $p
}

# PowerShell binds the comma operator TIGHTER than arithmetic, so the obvious
#     New-Object System.Windows.Point(8, $h * 0.3)
# actually parses as (8, $h) * 0.3 - an array multiplied by a double - and dies
# with a baffling "does not contain a method named op_Multiply". These wrappers
# take ordinary typed parameters, so arithmetic in an argument is always safe.
function New-RonPoint {
    param([double]$X, [double]$Y)
    return (New-Object System.Windows.Point -ArgumentList $X, $Y)
}

function New-RonRect {
    param([double]$X, [double]$Y, [double]$W, [double]$H)
    return (New-Object System.Windows.Rect -ArgumentList $X, $Y, $W, $H)
}

$script:RonTypefaceCache = @{}

function Get-RonTypeface {
    param([string]$Family = 'Segoe UI', [string]$Weight = 'Normal')
    $key = "$Family|$Weight"
    if ($script:RonTypefaceCache.ContainsKey($key)) { return $script:RonTypefaceCache[$key] }
    $w = [System.Windows.FontWeights]::Normal
    if ($Weight -eq 'Bold')     { $w = [System.Windows.FontWeights]::Bold }
    if ($Weight -eq 'SemiBold') { $w = [System.Windows.FontWeights]::SemiBold }
    $tf = New-Object System.Windows.Media.Typeface(
        (New-Object System.Windows.Media.FontFamily $Family),
        [System.Windows.FontStyles]::Normal, $w, [System.Windows.FontStretches]::Normal)
    $script:RonTypefaceCache[$key] = $tf
    return $tf
}

# The 6-argument FormattedText constructor is [Obsolete] on .NET 4.6+ and
# renders at the wrong size on a scaled display. The 7-argument overload takes
# pixelsPerDip explicitly; 1.0 is correct here because everything is authored
# in logical units and scaled once at rasterise time.
function New-RonText {
    param(
        [string]$Text,
        [double]$Size = 12.0,
        [string]$Colour = '#1B1F26',
        [string]$Weight = 'Normal',
        [string]$Family = 'Segoe UI',
        [double]$MaxWidth = 0.0,
        [string]$Align = 'Center'
    )
    $ft = New-Object System.Windows.Media.FormattedText(
        $Text,
        [System.Globalization.CultureInfo]::GetCultureInfo('en-GB'),
        [System.Windows.FlowDirection]::LeftToRight,
        (Get-RonTypeface -Family $Family -Weight $Weight),
        $Size,
        (New-RonBrush $Colour),
        1.0)
    if ($MaxWidth -gt 0) {
        $ft.MaxTextWidth = $MaxWidth
        $ft.Trimming = [System.Windows.TextTrimming]::None
    }
    if ($Align -eq 'Center') { $ft.TextAlignment = [System.Windows.TextAlignment]::Center }
    elseif ($Align -eq 'Right') { $ft.TextAlignment = [System.Windows.TextAlignment]::Right }
    else { $ft.TextAlignment = [System.Windows.TextAlignment]::Left }
    return $ft
}

# Opens a DrawingGroup for painting and returns both it and a DrawingContext.
# Callers MUST call $dc.Close() before using the group.
function Start-RonDrawing {
    $group = New-Object System.Windows.Media.DrawingGroup
    $dc = $group.Open()
    return @{ Group = $group; Dc = $dc }
}

function Complete-RonDrawing {
    param([hashtable]$Handle)
    $Handle.Dc.Close()
    $Handle.Group.Freeze()
    return $Handle.Group
}

# --- board tiles -----------------------------------------------------------
#
# Authored upright: colour bar at the top, name below, price at the bottom.
# Board.View rotates the whole tile per side so every bar faces the centre.

function New-RonTileDrawing {
    param([int]$Index)
    $a = $script:RonArt
    $p = $script:RonPalette
    $bi = Get-RonBoardIndex
    $space = $bi.ByIndex[$Index]
    $isCorner = ($Index -eq 0 -or $Index -eq 10 -or $Index -eq 20 -or $Index -eq 30)

    $w = $a.TileW
    $h = $a.TileH
    if ($isCorner) { $w = $a.Corner; $h = $a.Corner }

    $d = Start-RonDrawing
    $dc = $d.Dc
    $dc.DrawRectangle((New-RonBrush $p.TileFace), (New-RonPen $p.TileEdge 1.5),
        (New-RonRect (0) (0) ($w) ($h)))

    if ($isCorner) {
        Add-RonCornerContent -Dc $dc -Index $Index -Size $w
        return (Complete-RonDrawing $d)
    }

    $textTop = 6.0
    $group = $bi.Group[$Index]

    # Colour bar for streets; stations and utilities get an icon band instead.
    if ($bi.Type[$Index] -eq 'Street') {
        $colour = (Get-RonBoard).GroupColours[$group]
        $dc.DrawRectangle((New-RonBrush $colour), (New-RonPen $p.TileEdge 1.5),
            (New-RonRect (0) (0) ($w) ($a.BarH)))
        $textTop = $a.BarH + 8.0
    }

    # Names wrap at spaces quite happily - NORTHUMB AVE over two lines is how a
    # real board prints it. What looks broken is a single word snapping in half,
    # which is what MARLBOROUGH does the moment the type gets big enough to
    # read. So: measure the longest WORD, and shrink only far enough that it
    # fits. Every name that already fits keeps the full size.
    $name = ([string]$space.Short).ToUpper()
    $maxw = $w - 10
    $size = 12.0
    $widest = 0.0
    foreach ($word in ($name -split '\s+')) {
        $probe = New-RonText -Text $word -Size $size -Weight 'SemiBold'
        if ($probe.Width -gt $widest) { $widest = $probe.Width }
    }
    if ($widest -gt $maxw) { $size = [math]::Max(8.5, $size * ($maxw / $widest)) }

    $nameText = New-RonText -Text $name -Size $size -Weight 'SemiBold' `
        -Colour $p.TileInk -MaxWidth $maxw -Align 'Center'
    $dc.DrawText($nameText, (New-RonPoint (5) ($textTop)))

    # Station and utility glyphs sit under the name, where the colour bar would be.
    if ($bi.Type[$Index] -eq 'Station') {
        Add-RonStationGlyph -Dc $dc -CX ($w / 2) -CY ($h * 0.52) -Scale ($w / 100.0)
    }
    elseif ($bi.Type[$Index] -eq 'Utility') {
        if ($Index -eq 12) { Add-RonBulbGlyph  -Dc $dc -CX ($w / 2) -CY ($h * 0.52) -Scale ($w / 100.0) }
        else               { Add-RonTapGlyph   -Dc $dc -CX ($w / 2) -CY ($h * 0.52) -Scale ($w / 100.0) }
    }
    elseif ($bi.Type[$Index] -eq 'Chance') {
        $q = New-RonText -Text '?' -Size 46 -Weight 'Bold' -Colour $p.ChanceInk -MaxWidth ($w - 12)
        $dc.DrawText($q, (New-RonPoint (6) ($h * 0.32)))
    }
    elseif ($bi.Type[$Index] -eq 'Chest') {
        Add-RonChestGlyph -Dc $dc -CX ($w / 2) -CY ($h * 0.52) -Scale ($w / 100.0)
    }
    elseif ($bi.Type[$Index] -eq 'Tax') {
        Add-RonTaxGlyph -Dc $dc -CX ($w / 2) -CY ($h * 0.52) -Scale ($w / 100.0)
    }

    # Price, or the tax amount, along the bottom edge.
    $footer = ''
    if ($bi.Price[$Index] -gt 0)          { $footer = (Format-RonMoney $bi.Price[$Index]) }
    elseif ($space.ContainsKey('Amount')) { $footer = 'PAY ' + (Format-RonMoney ([int]$space.Amount)) }
    if ($footer) {
        $ft = New-RonText -Text $footer -Size 12.5 -Weight 'Bold' -Colour $p.TileInk -MaxWidth ($w - 12)
        $dc.DrawText($ft, (New-RonPoint (6) ($h - 24)))
    }

    return (Complete-RonDrawing $d)
}

function Add-RonCornerContent {
    param($Dc, [int]$Index, [double]$Size)
    $p = $script:RonPalette
    $mid = $Size / 2

    if ($Index -eq 0) {
        $t = New-RonText -Text 'GO' -Size 40 -Weight 'Bold' -Colour $p.TileInk -MaxWidth ($Size - 16)
        $Dc.DrawText($t, (New-RonPoint (8) ($Size * 0.30)))
        $s = New-RonText -Text ('COLLECT ' + (Format-RonMoney 200)) -Size 11.5 -Weight 'SemiBold' -Colour $p.TileInkDim -MaxWidth ($Size - 16)
        $Dc.DrawText($s, (New-RonPoint (8) ($Size * 0.62)))
        Add-RonArrowGlyph -Dc $Dc -CX $mid -CY ($Size * 0.82) -Scale ($Size / 162.0)
        return
    }
    if ($Index -eq 10) {
        Add-RonJailGlyph -Dc $Dc -Size $Size
        return
    }
    if ($Index -eq 20) {
        $t = New-RonText -Text "FREE`nPARKING" -Size 17 -Weight 'Bold' -Colour $p.TileInk -MaxWidth ($Size - 16)
        $Dc.DrawText($t, (New-RonPoint (8) ($Size * 0.14)))
        Add-RonCarGlyph -Dc $Dc -CX $mid -CY ($Size * 0.62) -Scale ($Size / 162.0)
        return
    }
    $t = New-RonText -Text "GO TO`nJAIL" -Size 18 -Weight 'Bold' -Colour $p.TileInk -MaxWidth ($Size - 16)
    $Dc.DrawText($t, (New-RonPoint (8) ($Size * 0.14)))
    Add-RonCuffGlyph -Dc $Dc -CX $mid -CY ($Size * 0.62) -Scale ($Size / 162.0)
}

# --- glyphs ----------------------------------------------------------------
#
# Small vector marks drawn straight into a DrawingContext. Each is authored
# around (CX, CY) at Scale 1.0 = a 100-unit-wide tile, so the same code serves
# a tile, a title deed and a legend chip.

function Add-RonPathGlyph {
    param($Dc, [string]$Data, [double]$CX, [double]$CY, [double]$Scale,
          [string]$Fill = '#2A2E35', [string]$Stroke = '', [double]$Thickness = 0.0,
          [double]$Box = 100.0)
    # Geometry.Parse hands back a FROZEN StreamGeometry, so it has to be cloned
    # before a transform can be attached.
    $geo = [System.Windows.Media.Geometry]::Parse($Data)
    if ($geo.IsFrozen) { $geo = $geo.Clone() }
    $tg = New-Object System.Windows.Media.TransformGroup
    # Path data is authored in a 0..Box square; centre it on (CX, CY).
    $tg.Children.Add((New-Object System.Windows.Media.TranslateTransform -ArgumentList (-$Box / 2), (-$Box / 2)))
    $tg.Children.Add((New-Object System.Windows.Media.ScaleTransform -ArgumentList $Scale, $Scale))
    $tg.Children.Add((New-Object System.Windows.Media.TranslateTransform -ArgumentList $CX, $CY))
    $geo.Transform = $tg
    $pen = $null
    if ($Stroke -and $Thickness -gt 0) { $pen = New-RonPen $Stroke $Thickness }
    $brush = $null
    if ($Fill) { $brush = New-RonBrush $Fill }
    $Dc.DrawGeometry($brush, $pen, $geo)
}

function Add-RonStationGlyph {
    param($Dc, [double]$CX, [double]$CY, [double]$Scale = 1.0)
    # A locomotive silhouette: cab, boiler, funnel, wheels.
    $data = 'M 14,62 L 14,40 L 34,40 L 34,26 L 56,26 L 56,40 L 74,40 L 78,62 Z ' +
            'M 60,26 L 60,14 L 72,14 L 72,26 Z ' +
            'M 24,62 A 8,8 0 1 0 24,78 A 8,8 0 1 0 24,62 Z ' +
            'M 66,62 A 8,8 0 1 0 66,78 A 8,8 0 1 0 66,62 Z'
    Add-RonPathGlyph -Dc $Dc -Data $data -CX $CX -CY $CY -Scale ($Scale * 0.62) -Fill '#2A2E35'
}

function Add-RonBulbGlyph {
    param($Dc, [double]$CX, [double]$CY, [double]$Scale = 1.0)
    $data = 'M 50,10 C 68,10 80,24 80,40 C 80,54 70,60 66,70 L 34,70 C 30,60 20,54 20,40 C 20,24 32,10 50,10 Z ' +
            'M 36,76 L 64,76 L 64,82 L 36,82 Z M 40,88 L 60,88 L 60,92 L 40,92 Z'
    Add-RonPathGlyph -Dc $Dc -Data $data -CX $CX -CY $CY -Scale ($Scale * 0.58) -Fill '#F0B429' -Stroke '#2A2E35' -Thickness 3
}

function Add-RonTapGlyph {
    param($Dc, [double]$CX, [double]$CY, [double]$Scale = 1.0)
    $data = 'M 30,30 L 70,30 L 70,44 L 58,44 L 58,58 L 70,58 L 70,72 L 30,72 L 30,58 L 42,58 L 42,44 L 30,44 Z ' +
            'M 50,74 C 62,84 62,96 50,96 C 38,96 38,84 50,74 Z'
    Add-RonPathGlyph -Dc $Dc -Data $data -CX $CX -CY $CY -Scale ($Scale * 0.56) -Fill '#4DABF7' -Stroke '#2A2E35' -Thickness 3
}

function Add-RonChestGlyph {
    param($Dc, [double]$CX, [double]$CY, [double]$Scale = 1.0)
    $data = 'M 16,44 C 16,28 84,28 84,44 L 84,76 L 16,76 Z M 16,52 L 84,52 ' +
            'M 44,52 L 44,66 L 56,66 L 56,52 Z'
    Add-RonPathGlyph -Dc $Dc -Data $data -CX $CX -CY $CY -Scale ($Scale * 0.60) -Fill '#1971C2' -Stroke '#2A2E35' -Thickness 3
}

function Add-RonTaxGlyph {
    param($Dc, [double]$CX, [double]$CY, [double]$Scale = 1.0)
    # A ring of coins.
    $data = 'M 50,16 A 26,26 0 1 0 50,68 A 26,26 0 1 0 50,16 Z'
    Add-RonPathGlyph -Dc $Dc -Data $data -CX $CX -CY ($CY - 4) -Scale ($Scale * 0.72) -Fill '#F0B429' -Stroke '#2A2E35' -Thickness 3
    $t = New-RonText -Text (Get-RonCurrencySymbol) -Size (22 * $Scale) -Weight 'Bold' -Colour '#2A2E35' -MaxWidth (40 * $Scale)
    $Dc.DrawText($t, (New-RonPoint (($CX - 20 * $Scale)) (($CY - 18 * $Scale))))
}

function Add-RonArrowGlyph {
    param($Dc, [double]$CX, [double]$CY, [double]$Scale = 1.0)
    $data = 'M 10,42 L 62,42 L 62,26 L 92,50 L 62,74 L 62,58 L 10,58 Z'
    Add-RonPathGlyph -Dc $Dc -Data $data -CX $CX -CY $CY -Scale ($Scale * 0.55) -Fill '#E03131'
}

function Add-RonCarGlyph {
    param($Dc, [double]$CX, [double]$CY, [double]$Scale = 1.0)
    $tokens = Get-RonTokens
    Add-RonPathGlyph -Dc $Dc -Data ([string]$tokens.Tokens.car.Glyph) -CX $CX -CY $CY -Scale ($Scale * 0.80) -Fill '#E03131' -Stroke '#2A2E35' -Thickness 2
}

function Add-RonCuffGlyph {
    param($Dc, [double]$CX, [double]$CY, [double]$Scale = 1.0)
    $data = 'M 12,50 A 20,20 0 1 0 52,50 A 20,20 0 1 0 12,50 Z ' +
            'M 48,50 A 20,20 0 1 0 88,50 A 20,20 0 1 0 48,50 Z'
    Add-RonPathGlyph -Dc $Dc -Data $data -CX $CX -CY $CY -Scale ($Scale * 0.78) -Fill '' -Stroke '#2A2E35' -Thickness 7
}

function Add-RonJailGlyph {
    param($Dc, [double]$Size)
    $p = $script:RonPalette
    # The corner splits diagonally: a barred cell, with the "just visiting"
    # walkway wrapping the outer two edges.
    $inset = $Size * 0.26
    $cell = New-RonRect ($inset) ($inset) ($Size - $inset * 2) ($Size - $inset * 2)
    $Dc.DrawRectangle((New-RonBrush '#F08C00'), (New-RonPen $p.TileEdge 2.0), $cell)

    $barPen = New-RonPen '#2A2E35' 3.5
    for ($i = 1; $i -le 4; $i++) {
        $x = $cell.Left + ($cell.Width * $i / 5.0)
        $Dc.DrawLine($barPen, (New-RonPoint ($x) ($cell.Top)),
                              (New-RonPoint ($x) ($cell.Bottom)))
    }
    $jt = New-RonText -Text 'JAIL' -Size 17 -Weight 'Bold' -Colour $p.TileInk -MaxWidth $cell.Width
    $Dc.DrawText($jt, (New-RonPoint ($cell.Left) ($cell.Bottom + 4)))
    $vt = New-RonText -Text 'JUST VISITING' -Size 9.5 -Weight 'SemiBold' -Colour $p.TileInkDim -MaxWidth ($Size - 12)
    $Dc.DrawText($vt, (New-RonPoint (6) ($Size - 18)))
}

# --- tokens, dice, buildings ----------------------------------------------

function New-RonTokenDrawing {
    param([string]$TokenId, [switch]$NoDisc)
    $tokens = Get-RonTokens
    if (-not $tokens.Tokens.ContainsKey($TokenId)) { $TokenId = $tokens.Order[0] }
    $t = $tokens.Tokens[$TokenId]
    $size = $script:RonArt.TokenPx

    $d = Start-RonDrawing
    $dc = $d.Dc
    if (-not $NoDisc) {
        # A filled disc in the player's colour, so tokens stay identifiable at
        # board scale where the silhouette alone is only a few pixels.
        $dc.DrawEllipse((New-RonBrush ([string]$t.Colour)), (New-RonPen '#FFFFFF' 4.0),
            (New-RonPoint ($size / 2) ($size / 2)), ($size / 2 - 3), ($size / 2 - 3))
        Add-RonPathGlyph -Dc $dc -Data ([string]$t.Glyph) -CX ($size / 2) -CY ($size / 2) `
            -Scale ($size / 100.0 * 0.62) -Fill '#FFFFFF'
    }
    else {
        Add-RonPathGlyph -Dc $dc -Data ([string]$t.Glyph) -CX ($size / 2) -CY ($size / 2) `
            -Scale ($size / 100.0 * 0.92) -Fill ([string]$t.Colour) -Stroke '#2A2E35' -Thickness 2
    }
    return (Complete-RonDrawing $d)
}

# Standard western die faces; 1/3/5 carry the centre pip.
$script:RonDiePips = @{
    1 = @(@(1,1))
    2 = @(@(0,0), @(2,2))
    3 = @(@(0,0), @(1,1), @(2,2))
    4 = @(@(0,0), @(2,0), @(0,2), @(2,2))
    5 = @(@(0,0), @(2,0), @(1,1), @(0,2), @(2,2))
    6 = @(@(0,0), @(2,0), @(0,1), @(2,1), @(0,2), @(2,2))
}

function New-RonDieDrawing {
    param([int]$Value)
    if ($Value -lt 1 -or $Value -gt 6) { $Value = 1 }
    $p = $script:RonPalette
    $s = $script:RonArt.DiePx

    $d = Start-RonDrawing
    $dc = $d.Dc
    $dc.DrawRoundedRectangle((New-RonBrush $p.DieFace), (New-RonPen '#C8C4BA' 2.0),
        (New-RonRect (0) (0) ($s) ($s)), ($s * 0.18), ($s * 0.18))

    $pip = New-RonBrush $p.DiePip
    $r = $s * 0.085
    $margin = $s * 0.26
    $step = ($s - $margin * 2) / 2.0
    foreach ($cell in $script:RonDiePips[$Value]) {
        $cx = $margin + ($cell[0] * $step)
        $cy = $margin + ($cell[1] * $step)
        $dc.DrawEllipse($pip, $null, (New-RonPoint ($cx) ($cy)), $r, $r)
    }
    return (Complete-RonDrawing $d)
}

function New-RonHouseDrawing {
    $p = $script:RonPalette
    $s = $script:RonArt.HousePx
    $d = Start-RonDrawing
    $dc = $d.Dc
    $body = 'M 18,44 L 18,86 L 82,86 L 82,44 Z'
    $roof = 'M 8,46 L 50,12 L 92,46 Z'
    Add-RonPathGlyph -Dc $dc -Data $body -CX ($s / 2) -CY ($s / 2) -Scale ($s / 100.0) -Fill $p.HouseGreen -Stroke '#14532A' -Thickness 4
    Add-RonPathGlyph -Dc $dc -Data $roof -CX ($s / 2) -CY ($s / 2) -Scale ($s / 100.0) -Fill $p.HouseDark -Stroke '#14532A' -Thickness 4
    return (Complete-RonDrawing $d)
}

function New-RonHotelDrawing {
    $p = $script:RonPalette
    $s = $script:RonArt.HousePx
    $d = Start-RonDrawing
    $dc = $d.Dc
    # Wider and taller than a house, with a low annexe, so the two read as
    # clearly different at board scale.
    $body   = 'M 22,34 L 22,86 L 78,86 L 78,34 Z'
    $roof   = 'M 14,36 L 50,10 L 86,36 Z'
    $annexe = 'M 4,60 L 4,86 L 22,86 L 22,60 Z'
    Add-RonPathGlyph -Dc $dc -Data $annexe -CX ($s / 2) -CY ($s / 2) -Scale ($s / 100.0) -Fill $p.HotelRed -Stroke '#6E1414' -Thickness 4
    Add-RonPathGlyph -Dc $dc -Data $body   -CX ($s / 2) -CY ($s / 2) -Scale ($s / 100.0) -Fill $p.HotelRed -Stroke '#6E1414' -Thickness 4
    Add-RonPathGlyph -Dc $dc -Data $roof   -CX ($s / 2) -CY ($s / 2) -Scale ($s / 100.0) -Fill $p.HotelDark -Stroke '#6E1414' -Thickness 4
    return (Complete-RonDrawing $d)
}

# --- title deeds and card faces -------------------------------------------

function New-RonDeedDrawing {
    param([int]$Index)
    $a = $script:RonArt
    $p = $script:RonPalette
    $bi = Get-RonBoardIndex
    $space = $bi.ByIndex[$Index]
    $w = $a.DeedW
    $h = $a.DeedH

    $d = Start-RonDrawing
    $dc = $d.Dc
    $dc.DrawRoundedRectangle((New-RonBrush $p.DeedFace), (New-RonPen '#3B3F46' 2.5),
        (New-RonRect (0) (0) ($w) ($h)), 14, 14)

    $group = $bi.Group[$Index]
    $headerH = 96.0
    $headerColour = '#2A2E35'
    if ($bi.Type[$Index] -eq 'Street') { $headerColour = (Get-RonBoard).GroupColours[$group] }

    $header = New-Object System.Windows.Media.RectangleGeometry(
        (New-RonRect (6) (6) ($w - 12) ($headerH)), 10, 10)
    $dc.DrawGeometry((New-RonBrush $headerColour), (New-RonPen '#3B3F46' 2.0), $header)

    $ink = '#1B1F26'
    if ($bi.Type[$Index] -ne 'Street') { $ink = '#FFFFFF' }
    $kind = New-RonText -Text 'TITLE DEED' -Size 11 -Weight 'SemiBold' -Colour $ink -MaxWidth ($w - 40)
    $dc.DrawText($kind, (New-RonPoint (20) (20)))
    $name = New-RonText -Text ([string]$space.Name).ToUpper() -Size 20 -Weight 'Bold' -Colour $ink -MaxWidth ($w - 40)
    $dc.DrawText($name, (New-RonPoint (20) (42)))

    $y = $headerH + 26.0
    $rows = New-Object System.Collections.ArrayList

    if ($bi.Type[$Index] -eq 'Street') {
        $rent = $bi.Rent[$Index]
        [void]$rows.Add(@{ L = 'Rent'; R = (Format-RonMoney $rent[0]) })
        for ($n = 1; $n -le 4; $n++) {
            [void]$rows.Add(@{ L = "With $n house$(if ($n -gt 1) { 's' })"; R = (Format-RonMoney $rent[$n]) })
        }
        [void]$rows.Add(@{ L = 'With hotel'; R = (Format-RonMoney $rent[5]) })
        [void]$rows.Add(@{ L = ''; R = '' })
        [void]$rows.Add(@{ L = 'Houses cost'; R = (Format-RonMoney $bi.HouseCost[$Index]) + ' each' })
        [void]$rows.Add(@{ L = 'Hotels cost'; R = (Format-RonMoney $bi.HouseCost[$Index]) + ' + 4 houses' })
    }
    elseif ($bi.Type[$Index] -eq 'Station') {
        $base = $bi.StationBaseRent
        [void]$rows.Add(@{ L = 'Rent'; R = (Format-RonMoney $base) })
        [void]$rows.Add(@{ L = 'If 2 stations owned'; R = (Format-RonMoney ($base * 2)) })
        [void]$rows.Add(@{ L = 'If 3 stations owned'; R = (Format-RonMoney ($base * 4)) })
        [void]$rows.Add(@{ L = 'If 4 stations owned'; R = (Format-RonMoney ($base * 8)) })
    }
    else {
        [void]$rows.Add(@{ L = 'If one utility owned'; R = "$($bi.UtilityOne)x dice" })
        [void]$rows.Add(@{ L = 'If both owned'; R = "$($bi.UtilityBoth)x dice" })
    }

    foreach ($row in $rows) {
        if ($row.L) {
            $lt = New-RonText -Text ([string]$row.L) -Size 13 -Colour '#3B3F46' -MaxWidth ($w * 0.62) -Align 'Left'
            $dc.DrawText($lt, (New-RonPoint (22) ($y)))
            $rt = New-RonText -Text ([string]$row.R) -Size 13 -Weight 'SemiBold' -Colour '#1B1F26' -MaxWidth ($w * 0.52) -Align 'Right'
            $dc.DrawText($rt, (New-RonPoint (($w - 22 - $w * 0.52)) ($y)))
        }
        $y += 26
    }

    $y += 6
    $dc.DrawLine((New-RonPen '#D5D2CB' 1.5), (New-RonPoint (22) ($y)),
                                             (New-RonPoint ($w - 22) ($y)))
    $y += 12
    $mv = New-RonText -Text ('Mortgage value ' + (Format-RonMoney $bi.Mortgage[$Index])) `
        -Size 12 -Colour '#5C6470' -MaxWidth ($w - 44) -Align 'Left'
    $dc.DrawText($mv, (New-RonPoint (22) ($y)))

    return (Complete-RonDrawing $d)
}

function New-RonCardFaceDrawing {
    param([ValidateSet('Chance','Chest')][string]$Deck, [string]$Text = '')
    $a = $script:RonArt
    $p = $script:RonPalette
    $w = $a.CardW
    $h = $a.CardH
    $accent = $p.ChanceInk
    $title = 'CHANCE'
    if ($Deck -eq 'Chest') { $accent = $p.ChestInk; $title = 'COMMUNITY CHEST' }

    $d = Start-RonDrawing
    $dc = $d.Dc
    $dc.DrawRoundedRectangle((New-RonBrush '#FFFDF7'), (New-RonPen $accent 3.0),
        (New-RonRect (0) (0) ($w) ($h)), 14, 14)
    $dc.DrawRoundedRectangle((New-RonBrush $accent), $null,
        (New-RonRect (0) (0) ($w) (40)), 14, 14)
    $dc.DrawRectangle((New-RonBrush $accent), $null, (New-RonRect (0) (24) ($w) (16)))

    $tt = New-RonText -Text $title -Size 15 -Weight 'Bold' -Colour '#FFFFFF' -MaxWidth ($w - 24)
    $dc.DrawText($tt, (New-RonPoint (12) (10)))

    if ($Text) {
        $bt = New-RonText -Text (Expand-RonCurrency $Text) -Size 13 -Colour '#1B1F26' -MaxWidth ($w - 44)
        $dc.DrawText($bt, (New-RonPoint (22) (62)))
    }
    else {
        $q = '?'
        if ($Deck -eq 'Chest') { $q = '' }
        if ($q) {
            $qt = New-RonText -Text $q -Size 90 -Weight 'Bold' -Colour $accent -MaxWidth ($w - 24)
            $dc.DrawText($qt, (New-RonPoint (12) (58)))
        }
        else {
            Add-RonChestGlyph -Dc $dc -CX ($w / 2) -CY ($h * 0.62) -Scale 1.4
        }
    }
    return (Complete-RonDrawing $d)
}

# --- rasterising -----------------------------------------------------------
#
# Used by Tools\Build-Assets.ps1. Lives here rather than in the build script so
# the runtime can also rasterise on demand if it ever needs a bitmap.

function ConvertTo-RonBitmap {
    param(
        [Parameter(Mandatory)][System.Windows.Media.Drawing]$Drawing,
        [Parameter(Mandatory)][double]$Width,
        [Parameter(Mandatory)][double]$Height,
        [int]$Scale = 2
    )
    $visual = New-Object System.Windows.Media.DrawingVisual
    $dc = $visual.RenderOpen()
    $dc.DrawDrawing($Drawing)
    $dc.Close()

    # Rendering at 96*Scale DPI keeps the drawing in logical units while
    # producing a bitmap Scale times larger - which is how the @2x variants are
    # made without touching a single coordinate.
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap(
        [int][math]::Ceiling($Width * $Scale), [int][math]::Ceiling($Height * $Scale),
        (96.0 * $Scale), (96.0 * $Scale),
        [System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($visual)
    $rtb.Freeze()
    return $rtb
}

function Save-RonBitmap {
    param(
        [Parameter(Mandatory)][System.Windows.Media.Imaging.BitmapSource]$Bitmap,
        [Parameter(Mandatory)][string]$Path
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($Bitmap))
    $stream = [System.IO.File]::Create($Path)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
    return $Path
}

# The single catalogue of everything that can be drawn: the build script walks
# it to produce PNGs, and the runtime loader uses the same keys and the same
# Make scriptblocks for its fallback. One list, so the two can never disagree.
function Get-RonArtCatalogue {
    $a = $script:RonArt
    $items = New-Object System.Collections.ArrayList

    foreach ($i in 0..39) {
        $isCorner = ($i -eq 0 -or $i -eq 10 -or $i -eq 20 -or $i -eq 30)
        $w = $a.TileW
        $h = $a.TileH
        if ($isCorner) { $w = $a.Corner; $h = $a.Corner }
        [void]$items.Add(@{
            Key = "tile.$i"; File = "tiles/tile-$i.png"; W = $w; H = $h
            Make = [scriptblock]::Create("New-RonTileDrawing -Index $i")
        })
        if (Test-RonIsDeed $i) {
            [void]$items.Add(@{
                Key = "deed.$i"; File = "deeds/deed-$i.png"; W = $a.DeedW; H = $a.DeedH
                Make = [scriptblock]::Create("New-RonDeedDrawing -Index $i")
            })
        }
    }

    foreach ($t in (Get-RonTokens).Order) {
        [void]$items.Add(@{
            Key = "token.$t"; File = "tokens/token-$t.png"; W = $a.TokenPx; H = $a.TokenPx
            Make = [scriptblock]::Create("New-RonTokenDrawing -TokenId '$t'")
        })
        [void]$items.Add(@{
            Key = "token.$t.plain"; File = "tokens/token-$t-plain.png"; W = $a.TokenPx; H = $a.TokenPx
            Make = [scriptblock]::Create("New-RonTokenDrawing -TokenId '$t' -NoDisc")
        })
    }

    foreach ($v in 1..6) {
        [void]$items.Add(@{
            Key = "die.$v"; File = "dice/die-$v.png"; W = $a.DiePx; H = $a.DiePx
            Make = [scriptblock]::Create("New-RonDieDrawing -Value $v")
        })
    }

    [void]$items.Add(@{ Key = 'house'; File = 'ui/house.png'; W = $a.HousePx; H = $a.HousePx; Make = { New-RonHouseDrawing } })
    [void]$items.Add(@{ Key = 'hotel'; File = 'ui/hotel.png'; W = $a.HousePx; H = $a.HousePx; Make = { New-RonHotelDrawing } })

    foreach ($deck in @('Chance','Chest')) {
        [void]$items.Add(@{
            Key = "cardback.$deck"; File = "cards/back-$deck.png"; W = $a.CardW; H = $a.CardH
            Make = [scriptblock]::Create("New-RonCardFaceDrawing -Deck '$deck'")
        })
    }

    return $items.ToArray()
}
