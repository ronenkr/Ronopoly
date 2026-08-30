#
# Ronopoly - the board.
#
# Builds the 11x11 grid once and then only ever UPDATES the cells in place.
# Rebuilding the grid per turn is the classic way to leak WPF visuals in a
# PowerShell app, because every rebuilt element re-registers its handlers.
#
# Board coordinates are exact: 162 + 9*100 + 162 = 1224 units per side, which
# is what lets the token and building layers position themselves arithmetically
# instead of having to measure the visual tree.
#

$script:RonCellSide   = 100.0
$script:RonCellCorner = 162.0
$script:RonBoardSize  = 1224.0

# Pixel geometry of a space in board coordinates.
function Get-RonCellGeometry {
    param([Parameter(Mandatory)][int]$Index)
    $cell = Get-RonBoardCell $Index
    $side = $script:RonCellSide
    $corner = $script:RonCellCorner

    $edge = { param($n) if ($n -eq 0) { return 0.0 } ; return ($corner + ($n - 1) * $side) }
    $span = { param($n) if ($n -eq 0 -or $n -eq 10) { return $corner } ; return $side }

    $x = & $edge $cell.Col
    $y = & $edge $cell.Row
    $w = & $span $cell.Col
    $h = & $span $cell.Row

    return @{
        X = $x; Y = $y; W = $w; H = $h
        CX = $x + $w / 2.0
        CY = $y + $h / 2.0
        Side = $cell.Side
        Rotation = $cell.Rotation
        Row = $cell.Row
        Col = $cell.Col
    }
}

# Where a token should sit: pushed toward the OUTER half of the tile so it
# never covers the name or the price.
function Get-RonTokenAnchor {
    param([Parameter(Mandatory)][int]$Index)
    $g = Get-RonCellGeometry $Index
    if (Test-RonIsCorner $Index) { return @{ X = $g.CX; Y = $g.CY } }
    $push = 26.0
    switch ($g.Side) {
        'Bottom' { return @{ X = $g.CX; Y = $g.CY + $push } }
        'Top'    { return @{ X = $g.CX; Y = $g.CY - $push } }
        'Left'   { return @{ X = $g.CX - $push; Y = $g.CY } }
        default  { return @{ X = $g.CX + $push; Y = $g.CY } }
    }
}

function Initialize-RonBoardView {
    param([Parameter(Mandatory)][hashtable]$Ui)

    $grid = $Ui.BoardGrid
    $grid.Children.Clear()
    $grid.ColumnDefinitions.Clear()
    $grid.RowDefinitions.Clear()

    for ($i = 0; $i -le 10; $i++) {
        $w = $script:RonCellSide
        if ($i -eq 0 -or $i -eq 10) { $w = $script:RonCellCorner }
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = New-Object System.Windows.GridLength $w
        $grid.ColumnDefinitions.Add($cd)
        $rd = New-Object System.Windows.Controls.RowDefinition
        $rd.Height = New-Object System.Windows.GridLength $w
        $grid.RowDefinitions.Add($rd)
    }

    $tiles = @{}
    for ($index = 0; $index -le 39; $index++) {
        $tile = New-RonTileElement -Index $index
        [System.Windows.Controls.Grid]::SetRow($tile.Host, $tile.Row)
        [System.Windows.Controls.Grid]::SetColumn($tile.Host, $tile.Col)
        [void]$grid.Children.Add($tile.Host)
        $tiles[$index] = $tile
    }
    $Ui.Tiles = $tiles

    Add-RonBoardOrnament -Ui $Ui
    return $tiles
}

# One tile: the printed art, an owner stripe along its outer edge, a row of
# buildings on the colour bar, and a highlight ring. All four are created once
# and only ever have their properties changed.
function New-RonTileElement {
    param([Parameter(Mandatory)][int]$Index)
    $g = Get-RonCellGeometry $Index
    $isCorner = Test-RonIsCorner $Index

    # A tile is authored 100x162 upright. Rotating it 90 or 270 swaps those,
    # which is exactly what the left and right columns need.
    $w = 100.0
    $h = 162.0
    if ($isCorner) { $w = 162.0; $h = 162.0 }

    $tileHost = New-Object System.Windows.Controls.Grid
    $tileHost.Width  = $w
    $tileHost.Height = $h

    $img = New-Object System.Windows.Controls.Image
    $img.Source = Get-RonTileImage $Index
    $img.Stretch = [System.Windows.Media.Stretch]::Fill
    [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, [System.Windows.Media.BitmapScalingMode]::HighQuality)
    [void]$tileHost.Children.Add($img)

    # Owner stripe: local BOTTOM is the tile's outer edge once rotated, so the
    # stripe always ends up on the rim of the board where it is easy to scan.
    $stripe = New-Object System.Windows.Controls.Border
    $stripe.Height = 9
    $stripe.VerticalAlignment = [System.Windows.VerticalAlignment]::Bottom
    $stripe.Visibility = [System.Windows.Visibility]::Collapsed
    [void]$tileHost.Children.Add($stripe)

    # Buildings sit on the colour bar at local TOP, which faces the centre.
    $buildings = New-Object System.Windows.Controls.StackPanel
    $buildings.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $buildings.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    $buildings.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
    $buildings.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
    [void]$tileHost.Children.Add($buildings)

    $ring = New-Object System.Windows.Controls.Border
    $ring.BorderThickness = New-Object System.Windows.Thickness 4
    $ring.BorderBrush = New-RonBrush '#3D8BFD'
    $ring.Visibility = [System.Windows.Visibility]::Collapsed
    [void]$tileHost.Children.Add($ring)

    $mortgaged = New-Object System.Windows.Controls.Border
    $mortgaged.Background = New-RonBrush '#66000000'
    $mortgaged.Visibility = [System.Windows.Visibility]::Collapsed
    [void]$tileHost.Children.Add($mortgaged)

    # Corners stay upright: rotating them 90 or 180 like their side would make
    # the label unreadable, and a square tile does not need it to fit.
    $rotation = $g.Rotation
    if ($isCorner) { $rotation = 0 }
    if ($rotation -ne 0) {
        $tileHost.LayoutTransform = New-Object System.Windows.Media.RotateTransform $rotation
    }

    return @{
        Index     = $Index
        Host      = $tileHost
        Image     = $img
        Stripe    = $stripe
        Buildings = $buildings
        Ring      = $ring
        Mortgaged = $mortgaged
        Row       = $g.Row
        Col       = $g.Col
    }
}

# The centre of the board: title, and the two card decks.
function Add-RonBoardOrnament {
    param([Parameter(Mandatory)][hashtable]$Ui)
    $canvas = $Ui.OrnamentCanvas
    $canvas.Children.Clear()
    $mid = $script:RonBoardSize / 2.0

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = 'RONOPOLY'
    $title.FontSize = 64
    $title.FontWeight = [System.Windows.FontWeights]::Bold
    # Follows the theme rather than being a fixed colour: the felt is dark in
    # one theme and pale in the other, and a fixed light watermark vanishes on
    # the pale one.
    $title.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'Brush.Text')
    $title.Opacity = 0.14
    $title.RenderTransform = New-Object System.Windows.Media.RotateTransform(-45)
    $title.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)
    # Measured unrotated, then centred and spun about its own middle - which
    # leaves it centred whatever the angle.
    $title.Measure((New-Object System.Windows.Size([double]::PositiveInfinity, [double]::PositiveInfinity)))
    [System.Windows.Controls.Canvas]::SetLeft($title, $mid - $title.DesiredSize.Width / 2)
    [System.Windows.Controls.Canvas]::SetTop($title, $mid - $title.DesiredSize.Height / 2)
    [void]$canvas.Children.Add($title)

    # The two decks sit in opposite quadrants of the open middle, clear of the
    # tiles and clear of each other. Card art is 340x220, drawn at 210 wide.
    $cardW = 210.0
    $cardH = $cardW * 220.0 / 340.0
    $offset = 210.0

    $chance = New-RonDeckPile -Deck 'Chance' -Angle -13 -Width $cardW
    [System.Windows.Controls.Canvas]::SetLeft($chance, $mid - $offset - $cardW / 2)
    [System.Windows.Controls.Canvas]::SetTop($chance, $mid + $offset - $cardH / 2)
    [void]$canvas.Children.Add($chance)

    $chest = New-RonDeckPile -Deck 'Chest' -Angle 11 -Width $cardW
    [System.Windows.Controls.Canvas]::SetLeft($chest, $mid + $offset - $cardW / 2)
    [System.Windows.Controls.Canvas]::SetTop($chest, $mid - $offset - $cardH / 2)
    [void]$canvas.Children.Add($chest)

    $Ui.DeckPiles = @{ Chance = $chance; Chest = $chest }
}

function New-RonDeckPile {
    param([ValidateSet('Chance','Chest')][string]$Deck, [double]$Angle = 0, [double]$Width = 210)
    $img = New-Object System.Windows.Controls.Image
    $img.Source = Get-RonAssetImage "cardback.$Deck"
    $img.Width = $Width
    $img.Stretch = [System.Windows.Media.Stretch]::Uniform
    [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, [System.Windows.Media.BitmapScalingMode]::HighQuality)
    $img.RenderTransform = New-Object System.Windows.Media.RotateTransform $Angle
    $img.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)
    $shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
    $shadow.BlurRadius = 26
    $shadow.ShadowDepth = 8
    $shadow.Opacity = 0.35
    $img.Effect = $shadow
    return $img
}

# --- in-place updates ------------------------------------------------------

function Update-RonBoardView {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][GameState]$State
    )
    $houseImg = Get-RonHouseImage
    $hotelImg = Get-RonHotelImage

    foreach ($index in (Get-RonDeedIndices)) {
        $tile = $Ui.Tiles[$index]
        $deed = $State.Properties[$index]

        if ($deed.OwnerId -ge 0) {
            $colour = Get-RonPlayerColour -State $State -PlayerId $deed.OwnerId
            $tile.Stripe.Background = New-RonBrush $colour
            $tile.Stripe.Visibility = [System.Windows.Visibility]::Visible
        }
        else {
            $tile.Stripe.Visibility = [System.Windows.Visibility]::Collapsed
        }

        if ($deed.Mortgaged) { $tile.Mortgaged.Visibility = [System.Windows.Visibility]::Visible }
        else                 { $tile.Mortgaged.Visibility = [System.Windows.Visibility]::Collapsed }

        # Only touch the building row when the count actually changed, so a
        # normal turn does no visual-tree work at all.
        $want = $deed.Houses
        $have = -1
        if ($null -ne $tile.HouseCount) { $have = $tile.HouseCount }
        if ($want -ne $have) {
            $tile.Buildings.Children.Clear()
            if ($want -eq 5) {
                [void]$tile.Buildings.Children.Add((New-RonBuildingPip -Source $hotelImg -Size 32))
            }
            else {
                for ($n = 0; $n -lt $want; $n++) {
                    [void]$tile.Buildings.Children.Add((New-RonBuildingPip -Source $houseImg -Size 24))
                }
            }
            $tile.HouseCount = $want
        }
    }
}

function New-RonBuildingPip {
    param([Parameter(Mandatory)]$Source, [double]$Size = 20)
    $img = New-Object System.Windows.Controls.Image
    $img.Source = $Source
    $img.Width = $Size
    $img.Height = $Size
    $img.Margin = New-Object System.Windows.Thickness(1, 0, 1, 0)
    [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, [System.Windows.Media.BitmapScalingMode]::HighQuality)
    return $img
}

# Ring one space (the current player's landing spot, or an auction lot).
function Set-RonTileHighlight {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [int]$Index = -1
    )
    if ($null -ne $Ui.HighlightIndex -and $Ui.HighlightIndex -ge 0) {
        $Ui.Tiles[$Ui.HighlightIndex].Ring.Visibility = [System.Windows.Visibility]::Collapsed
    }
    $Ui.HighlightIndex = $Index
    if ($Index -ge 0) {
        $Ui.Tiles[$Index].Ring.Visibility = [System.Windows.Visibility]::Visible
    }
}

function Get-RonPlayerColour {
    param([Parameter(Mandatory)][GameState]$State, [Parameter(Mandatory)][int]$PlayerId)
    $tokens = Get-RonTokens
    $id = $State.Players[$PlayerId].Token
    if ($tokens.Tokens.ContainsKey($id)) { return [string]$tokens.Tokens[$id].Colour }
    return '#888888'
}
