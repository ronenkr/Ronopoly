#
# Ronopoly - overlay panels.
#
# Every dialog in the game is a LAYER in the main window, never a separate
# Window and never ShowDialog. ShowDialog pumps a nested dispatcher loop, which
# fights the turn state machine and behaves differently for a local player than
# for a remote one; a layer behaves identically for both and keeps exactly one
# dispatcher loop in the process.
#
# Panels are built programmatically rather than from XAML strings because they
# are data-shaped - one row per owned deed, one row per bidder - which XAML
# without data binding cannot express any more clearly.
#

function Show-RonOverlay {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][System.Windows.UIElement]$Content,
        # A modal panel is one the PLAYER opened and is working in - a trade
        # they are composing, the quit prompt. It stops the AI clock and stops
        # the phase watcher replacing it, so the game cannot move the board out
        # from under a half-finished decision.
        [switch]$Modal
    )
    # An auction panel is rebuilt on every refresh so the bid ladder stays
    # current, so only fade in when the layer was actually closed - otherwise
    # the whole overlay flickers once per bid.
    $wasClosed = ($Ui.OverlayLayer.Visibility -ne [System.Windows.Visibility]::Visible)
    $Ui.OverlayHost.Content = $Content
    $Ui.OverlayLayer.Visibility = [System.Windows.Visibility]::Visible
    if ($Modal) { $Ui.Modal = $true }

    if ($wasClosed) {
        $fade = New-Object System.Windows.Media.Animation.DoubleAnimation(0.0, 1.0, [TimeSpan]::FromMilliseconds(140))
        $Ui.OverlayLayer.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)
    }
}

function Hide-RonOverlay {
    param([Parameter(Mandatory)][hashtable]$Ui)
    $wasModal = [bool]$Ui.Modal
    $Ui.Modal = $false
    $Ui.OverlayLayer.Visibility = [System.Windows.Visibility]::Collapsed
    $Ui.OverlayHost.Content = $null

    # A modal panel parked the AI clock, so closing one has to start the game
    # moving again - otherwise the table sits there waiting for nobody.
    if ($wasModal) {
        $app = (Get-RonApp)
        if ($null -ne $app -and $null -ne $app.State) {
            Update-RonAllViews
            Start-RonAutoPlay
        }
    }
}

function Test-RonOverlayModal {
    param([Parameter(Mandatory)][hashtable]$Ui)
    return [bool]$Ui.Modal
}

function Test-RonOverlayOpen {
    param([Parameter(Mandatory)][hashtable]$Ui)
    return ($Ui.OverlayLayer.Visibility -eq [System.Windows.Visibility]::Visible)
}

# The shared frame: a titled card with a body and a button row.
function New-RonOverlayCard {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][string]$Title,
        [string]$Subtitle = '',
        [double]$Width = 600
    )
    $card = New-Object System.Windows.Controls.Border
    $card.Style = $Ui.Window.FindResource('Card')
    $card.Width = $Width
    $card.MaxHeight = Get-RonCardMaxHeight -Ui $Ui
    $card.Padding = New-Object System.Windows.Thickness 24
    $card.Effect = $Ui.Window.FindResource('Fx.Lift')

    $stack = New-Object System.Windows.Controls.StackPanel
    $head = New-Object System.Windows.Controls.TextBlock
    $head.Text = $Title
    $head.Style = $Ui.Window.FindResource('Text.Title')
    $head.Margin = New-Object System.Windows.Thickness(0, 0, 0, 4)
    [void]$stack.Children.Add($head)

    $sub = New-Object System.Windows.Controls.TextBlock
    $sub.Text = $Subtitle
    $sub.Style = $Ui.Window.FindResource('Text.Dim')
    $sub.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $sub.Margin = New-Object System.Windows.Thickness(0, 0, 0, 16)
    if (-not $Subtitle) { $sub.Visibility = [System.Windows.Visibility]::Collapsed }
    [void]$stack.Children.Add($sub)

    $body = New-Object System.Windows.Controls.StackPanel
    [void]$stack.Children.Add($body)

    $buttons = New-Object System.Windows.Controls.WrapPanel
    $buttons.Margin = New-Object System.Windows.Thickness(0, 16, 0, 0)
    [void]$stack.Children.Add($buttons)

    $card.Child = $stack
    return @{ Root = $card; Body = $body; Buttons = $buttons; Head = $head; Sub = $sub }
}

function Add-RonOverlayButton {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][hashtable]$Card,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][scriptblock]$OnClick,
        [string]$Style = '',
        [bool]$Enabled = $true
    )
    $btn = New-Object System.Windows.Controls.Button
    $btn.Content = $Label
    $btn.IsEnabled = $Enabled
    if ($Style) { $btn.Style = $Ui.Window.FindResource($Style) }
    $btn.Add_Click($OnClick)
    [void]$Card.Buttons.Children.Add($btn)
    return $btn
}

function New-RonScrollBody {
    param([double]$MaxHeight = 420)
    $scroll = New-Object System.Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
    $scroll.HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Disabled
    $scroll.MaxHeight = $MaxHeight
    $inner = New-Object System.Windows.Controls.StackPanel
    $scroll.Content = $inner
    return @{ Scroll = $scroll; Inner = $inner }
}

function New-RonRowGrid {
    param([string[]]$Widths)
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = New-Object System.Windows.Thickness(0, 3, 0, 3)
    foreach ($w in $Widths) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        if ($w -eq 'Auto') { $cd.Width = [System.Windows.GridLength]::Auto }
        elseif ($w -eq '*') { $cd.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star) }
        else { $cd.Width = New-Object System.Windows.GridLength([double]$w) }
        $grid.ColumnDefinitions.Add($cd)
    }
    return $grid
}

function New-RonLabel {
    param([string]$Text, [int]$Column = 0, [string]$Style = '', [double]$FontSize = 0, [hashtable]$Ui = $null)
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $Text
    $tb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
    if ($FontSize -gt 0) { $tb.FontSize = $FontSize }
    if ($Style -and $null -ne $Ui) { $tb.Style = $Ui.Window.FindResource($Style) }
    [System.Windows.Controls.Grid]::SetColumn($tb, $Column)
    return $tb
}

# How tall to draw a title deed.
#
# The card is half again the size it used to be, which is the size it should
# always have been: it is the one place in the game where a player sits and
# reads a rent table. But a FIXED height that looks right on a 1010-tall window
# clips its own buttons on the 760-tall minimum this window allows, so the
# wanted size is a ceiling rather than a promise. Reserve is everything else
# the panel has to fit - title, buttons, padding, and any rows above the card.
function Get-RonDeedFitHeight {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [double]$Wanted,
        [double]$Reserve
    )
    $room = (Get-RonCardMaxHeight -Ui $Ui) - $Reserve
    if ($room -ge $Wanted) { return $Wanted }
    return [math]::Max(180, $room)
}

# The tallest a panel may be: never past the window's edge, because a card
# clipped by the edge loses its buttons, and a panel with no way out of it is
# worse than a small one.
function Get-RonCardMaxHeight {
    param([Parameter(Mandatory)][hashtable]$Ui)
    $cap = 930.0
    $avail = $Ui.Window.ActualHeight
    if ($avail -le 0) { $avail = $Ui.Window.Height }
    if ($avail -gt 0 -and ($avail - 56) -lt $cap) { $cap = [math]::Max(320, $avail - 56) }
    return $cap
}

# Black text on a light colour, white on a dark one.
#
# sRGB luminance rather than a plain average of the channels: the eye weights
# green about ten times as heavily as blue, and averaging puts white text on
# the amber token, where it is barely readable.
function Get-RonContrastInk {
    param([Parameter(Mandatory)][string]$Hex)
    $h = $Hex.TrimStart('#')
    if ($h.Length -lt 6) { return '#FFFFFF' }
    $r = [Convert]::ToInt32($h.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($h.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($h.Substring(4, 2), 16)
    $lum = (0.2126 * $r + 0.7152 * $g + 0.0722 * $b) / 255.0
    if ($lum -gt 0.55) { return '#101418' }
    return '#FFFFFF'
}

# A player's name on their own token colour. Which pile of deeds belongs to
# whom is the thing a trade panel is actually about, and a name in the same
# grey as everything else makes you go and look at the board to find out.
function New-RonPlayerChip {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [double]$FontSize = 14
    )
    $colour = Get-RonPlayerColour -State $State -PlayerId $PlayerId
    $chip = New-Object System.Windows.Controls.Border
    $chip.Background = New-RonBrush $colour
    $chip.CornerRadius = New-Object System.Windows.CornerRadius 6
    $chip.Padding = New-Object System.Windows.Thickness(9, 2, 9, 3)
    $chip.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $State.Players[$PlayerId].Name
    $tb.FontSize = $FontSize
    $tb.FontWeight = [System.Windows.FontWeights]::SemiBold
    $tb.Foreground = New-RonBrush (Get-RonContrastInk $colour)
    $chip.Child = $tb
    return $chip
}

# What the trade-with box binds to. Brushes rather than colour strings so the
# template needs no conversion, and frozen so one brush can be shared by every
# copy the ComboBox makes.
function New-RonPlayerListItem {
    param([Parameter(Mandatory)][GameState]$State, [Parameter(Mandatory)][int]$PlayerId)
    $colour = Get-RonPlayerColour -State $State -PlayerId $PlayerId
    return [pscustomobject]@{
        Id     = $PlayerId
        Name   = $State.Players[$PlayerId].Name
        Swatch = (New-RonBrush $colour)
        Ink    = (New-RonBrush (Get-RonContrastInk $colour))
    }
}

# A heading with a player chip beside it: "YOU GIVE   [Ada]".
function New-RonPlayerHeading {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][int]$PlayerId
    )
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $row.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)

    $label = New-Object System.Windows.Controls.TextBlock
    $label.Text = $Text
    $label.Style = $Ui.Window.FindResource('Text.Head')
    $label.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $label.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    [void]$row.Children.Add($label)
    [void]$row.Children.Add((New-RonPlayerChip -Ui $Ui -State $State -PlayerId $PlayerId))
    return $row
}

# A section heading inside a panel body.
function New-RonHeading {
    param([Parameter(Mandatory)][hashtable]$Ui, [string]$Text, [double]$Top = 0)
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $Text
    $tb.Style = $Ui.Window.FindResource('Text.Head')
    $tb.Margin = New-Object System.Windows.Thickness(0, $Top, 0, 6)
    return $tb
}

# --- auction ---------------------------------------------------------------

function Show-RonAuctionOverlay {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][scriptblock]$OnAction
    )
    $a = $State.Turn.Auction
    if ($null -eq $a) { return }
    $bidder = $a.CurrentBidderId()
    $minBid = Get-RonMinimumBid -State $State

    $lead = 'No bids yet'
    if ($a.HighBidderId -ge 0) {
        $lead = "$($State.Players[$a.HighBidderId].Name) leads with $(Format-RonMoney $a.CurrentBid)"
    }
    $card = New-RonOverlayCard -Ui $Ui -Title ('Auction: ' + (Get-RonSpaceName $a.SpaceIndex)) -Subtitle $lead -Width 640

    $deedImg = New-Object System.Windows.Controls.Image
    $deedImg.Source = Get-RonDeedImage $a.SpaceIndex
    # 260 was already small for a rent table; 390 is the same half-again.
    # The bidder list grows with the table, so it is part of the reserve.
    $deedImg.Height = Get-RonDeedFitHeight -Ui $Ui -Wanted 390 `
        -Reserve (330 + 30 * @($a.ActiveBidders).Count)
    $deedImg.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    $deedImg.Margin = New-Object System.Windows.Thickness(0, 0, 0, 14)
    [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($deedImg, [System.Windows.Media.BitmapScalingMode]::HighQuality)
    [void]$card.Body.Children.Add($deedImg)

    [void]$card.Body.Children.Add((New-RonHeading -Ui $Ui -Text 'STILL BIDDING'))
    foreach ($id in $a.ActiveBidders) {
        $p = $State.Players[$id]
        $row = New-RonRowGrid -Widths @('*','Auto')
        $mark = ''
        if ($id -eq $bidder) { $mark = '> ' }
        $name = New-RonLabel -Text ($mark + $p.Name) -Column 0
        if ($id -eq $bidder) { $name.FontWeight = [System.Windows.FontWeights]::SemiBold }
        $row.Children.Add($name) | Out-Null
        $row.Children.Add((New-RonLabel -Text (Format-RonMoney $p.Cash) -Column 1)) | Out-Null
        if ($id -eq $bidder) { $row.Opacity = 1.0 } else { $row.Opacity = 0.55 }
        [void]$card.Body.Children.Add($row)
    }

    $player = $State.Players[$bidder]
    if ($player.IsAiControlled()) {
        $card.Sub.Text = "$lead   -   $($player.Name) is deciding..."
        $card.Sub.Visibility = [System.Windows.Visibility]::Visible
        Show-RonOverlay -Ui $Ui -Content $card.Root
        return
    }

    $ceiling = $player.Cash
    if ($State.RuleOn('AllowBidToRaiseFunds')) { $ceiling = Get-RonLiquidatableCash -State $State -PlayerId $bidder }

    [void]$card.Body.Children.Add((New-RonHeading -Ui $Ui -Text 'YOUR BID' -Top 16))
    $bidRow = New-RonRowGrid -Widths @('*','Auto','Auto','Auto')
    $box = New-Object System.Windows.Controls.TextBox
    $box.Text = [string]$minBid
    $box.FontSize = 18
    [System.Windows.Controls.Grid]::SetColumn($box, 0)
    [void]$bidRow.Children.Add($box)

    # Raise buttons: bidding is the one place in the game with a keypad's worth
    # of typing between the player and an obvious move.
    $col = 1
    foreach ($step in @(10, 50, 100)) {
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = '+' + (Format-RonMoney $step)
        $btn.Style = $Ui.Window.FindResource('Button.Row')
        [System.Windows.Controls.Grid]::SetColumn($btn, $col)
        $bump = $step
        $btn.Add_Click({
            $value = 0
            [void][int]::TryParse($box.Text.Trim(), [ref]$value)
            $box.Text = [string]($value + $bump)
        }.GetNewClosure())
        [void]$bidRow.Children.Add($btn)
        $col++
    }
    [void]$card.Body.Children.Add($bidRow)

    $limit = New-RonLabel -Text ("Minimum " + (Format-RonMoney $minBid) + "   -   you can go to " + (Format-RonMoney $ceiling))
    $limit.Style = $Ui.Window.FindResource('Text.Dim')
    $limit.Margin = New-Object System.Windows.Thickness(0, 8, 0, 0)
    [void]$card.Body.Children.Add($limit)

    Add-RonOverlayButton -Ui $Ui -Card $card -Label 'Bid' -Style 'Button.Primary' -Enabled ($ceiling -ge $minBid) -OnClick {
        $amount = 0
        if ([int]::TryParse($box.Text.Trim(), [ref]$amount)) {
            & $OnAction @{ Kind = 'Bid'; PlayerId = $bidder; Amount = $amount }
        }
    }.GetNewClosure() | Out-Null

    Add-RonOverlayButton -Ui $Ui -Card $card -Label 'Pass' -OnClick {
        & $OnAction @{ Kind = 'PassBid'; PlayerId = $bidder }
    }.GetNewClosure() | Out-Null

    Show-RonOverlay -Ui $Ui -Content $card.Root
}

# --- title deed ------------------------------------------------------------

function Show-RonDeedOverlay {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$SpaceIndex
    )
    if (-not (Test-RonIsDeed $SpaceIndex)) { return }
    $deed = $State.Properties[$SpaceIndex]
    $owner = 'Unowned'
    if ($deed.OwnerId -ge 0) { $owner = 'Owned by ' + $State.Players[$deed.OwnerId].Name }
    if ($deed.Mortgaged) { $owner += '  (mortgaged)' }

    # Half again the old 470, and the panel is sized from the card rather than
    # the other way round.
    $deedH = Get-RonDeedFitHeight -Ui $Ui -Wanted 705 -Reserve 215
    $deedW = [math]::Ceiling($deedH * (Get-RonDeedAspect))

    $card = New-RonOverlayCard -Ui $Ui -Title (Get-RonSpaceName $SpaceIndex) -Subtitle $owner -Width ($deedW + 60)
    $img = New-Object System.Windows.Controls.Image
    $img.Source = Get-RonDeedImage $SpaceIndex
    $img.Height = $deedH
    [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, [System.Windows.Media.BitmapScalingMode]::HighQuality)
    [void]$card.Body.Children.Add($img)

    Add-RonOverlayButton -Ui $Ui -Card $card -Label 'Close' -Style 'Button.Primary' -OnClick {
        Hide-RonOverlay -Ui $Ui
    }.GetNewClosure() | Out-Null

    Show-RonOverlay -Ui $Ui -Content $card.Root
}

# --- game over -------------------------------------------------------------

function Show-RonGameOverOverlay {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][scriptblock]$OnNewGame
    )
    $title = 'Game over'
    $sub = 'Nobody is left standing.'
    if ($State.WinnerId -ge 0) {
        $title = $State.Players[$State.WinnerId].Name + ' wins'
        $sub = "After $($State.Turn.TurnNumber) turns."
    }
    $card = New-RonOverlayCard -Ui $Ui -Title $title -Subtitle $sub -Width 540

    $standings = New-Object System.Collections.ArrayList
    foreach ($p in $State.Players) {
        [void]$standings.Add([pscustomobject]@{
            Name = $p.Name
            Worth = (Get-RonNetWorth -State $State -PlayerId $p.Id)
            Bankrupt = $p.IsBankrupt
        })
    }
    foreach ($row in ($standings | Sort-Object -Property @{ Expression = 'Bankrupt' }, @{ Expression = 'Worth'; Descending = $true })) {
        $g = New-RonRowGrid -Widths @('*','Auto')
        $g.Children.Add((New-RonLabel -Text $row.Name -Column 0)) | Out-Null
        $text = Format-RonMoney $row.Worth
        if ($row.Bankrupt) { $text = 'bankrupt' }
        $g.Children.Add((New-RonLabel -Text $text -Column 1)) | Out-Null
        if ($row.Bankrupt) { $g.Opacity = 0.5 }
        [void]$card.Body.Children.Add($g)
    }

    Add-RonOverlayButton -Ui $Ui -Card $card -Label 'New game' -Style 'Button.Primary' -OnClick $OnNewGame | Out-Null
    Add-RonOverlayButton -Ui $Ui -Card $card -Label 'Close' -OnClick {
        Hide-RonOverlay -Ui $Ui
    }.GetNewClosure() | Out-Null

    Show-RonOverlay -Ui $Ui -Content $card.Root
}

# --- card reveal (a toast, not a blocking dialog) -------------------------

function Show-RonCardToast {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][ValidateSet('Chance','Chest')][string]$Deck,
        [Parameter(Mandatory)][string]$Text,
        [double]$Seconds = 2.6,
        [scriptblock]$OnDone = $null
    )
    $drawing = New-RonCardFaceDrawing -Deck $Deck -Text $Text
    $source = New-Object System.Windows.Media.DrawingImage $drawing
    $source.Freeze()

    $img = New-Object System.Windows.Controls.Image
    $img.Source = $source
    $img.Width = 460
    $shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
    $shadow.BlurRadius = 34
    $shadow.ShadowDepth = 10
    $shadow.Opacity = 0.5
    $img.Effect = $shadow

    # Flip in on the X axis, which reads as a card being turned over.
    $scale = New-Object System.Windows.Media.ScaleTransform(0.0, 1.0)
    $img.RenderTransform = $scale
    $img.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)
    $Ui.ToastHost.Content = $img

    $flip = New-Object System.Windows.Media.Animation.DoubleAnimation(0.0, 1.0, [TimeSpan]::FromMilliseconds(220))
    $flip.EasingFunction = New-Object System.Windows.Media.Animation.CubicEase
    $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $flip)

    if ($null -ne $Ui.ToastTimer) { $Ui.ToastTimer.Stop() }
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds($Seconds)
    $timer.Add_Tick({
        $timer.Stop()
        $Ui.ToastTimer = $null
        $Ui.ToastHost.Content = $null
        if ($null -ne $OnDone) { & $OnDone }
    }.GetNewClosure())
    $Ui.ToastTimer = $timer
    $timer.Start()
}

function Clear-RonToast {
    param([Parameter(Mandatory)][hashtable]$Ui)
    if ($null -ne $Ui.ToastTimer) { $Ui.ToastTimer.Stop(); $Ui.ToastTimer = $null }
    $Ui.ToastHost.Content = $null
}

# --- plain message ---------------------------------------------------------

function Show-RonMessageOverlay {
    param(
        [Parameter(Mandatory)][string]$Title,
        # AllowEmptyString is essential, not decoration: a mandatory [string[]]
        # rejects an array containing an empty ELEMENT, and every message here
        # uses '' as a blank line. Without it the error reporter is itself the
        # thing that throws - which is how the AI-seed overflow surfaced as
        # "Cannot bind argument to parameter 'Body'" instead of its real cause.
        [Parameter(Mandatory)][AllowEmptyString()][string[]]$Body,
        [string]$Button = 'Close'
    )
    $Ui = (Get-RonApp).Ui
    $card = New-RonOverlayCard -Ui $Ui -Title $Title -Width 580
    foreach ($line in $Body) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = $line
        $tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $tb.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)
        if (-not $line) { $tb.Height = 6 }
        [void]$card.Body.Children.Add($tb)
    }
    Add-RonOverlayButton -Ui $Ui -Card $card -Label $Button -Style 'Button.Primary' -OnClick {
        Hide-RonOverlay -Ui (Get-RonApp).Ui
    } | Out-Null
    # Modal: a message worth interrupting the game for is worth not having the
    # next phase change wipe off the screen before it has been read.
    Show-RonOverlay -Ui $Ui -Content $card.Root -Modal
}

# --- quitting --------------------------------------------------------------
#
# Closing the window is the one irreversible click in the app: an unsaved
# position is gone. Window.Closing cancels the close and shows this instead,
# and only the Quit button here sets the flag that lets a close through.

function Show-RonQuitOverlay {
    $App = (Get-RonApp)
    $Ui = $App.Ui
    $canSave = ($null -ne $App.State -and $null -ne $App.Session -and $App.Session.Kind -eq 'Local')

    $sub = 'The game will be lost.'
    if ($null -ne $App.State -and $App.State.IsOver) { $sub = 'The game is over.' }
    elseif ($canSave) { $sub = 'This position has not been saved. You can keep it and pick it up later.' }

    $card = New-RonOverlayCard -Ui $Ui -Title 'Leave the game?' -Subtitle $sub -Width 560

    if ($null -ne $App.State) {
        $turn = New-RonLabel -Text ("Turn $($App.State.Turn.TurnNumber)   -   " +
            (@($App.State.ActivePlayers() | ForEach-Object { $_.Name + ' ' + (Format-RonMoney $_.Cash) }) -join '   '))
        $turn.Style = $Ui.Window.FindResource('Text.Dim')
        [void]$card.Body.Children.Add($turn)
    }

    if ($canSave) {
        Add-RonOverlayButton -Ui $Ui -Card $card -Label 'Save and quit' -Style 'Button.Primary' -OnClick {
            $a = (Get-RonApp)
            $path = Get-RonPath (Join-Path 'Saves' ('ronopoly-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json'))
            Invoke-RonGuarded -Category 'ui' -Body { [void](Save-RonGame -State $a.State -Path $path) }
            $a.ConfirmedClose = $true
            $a.Window.Close()
        } | Out-Null
    }

    Add-RonOverlayButton -Ui $Ui -Card $card -Label 'Quit' -Style 'Button.Danger' -OnClick {
        $a = (Get-RonApp)
        $a.ConfirmedClose = $true
        $a.Window.Close()
    } | Out-Null

    Add-RonOverlayButton -Ui $Ui -Card $card -Label 'Keep playing' -OnClick {
        Hide-RonOverlay -Ui (Get-RonApp).Ui
    } | Out-Null

    Show-RonOverlay -Ui $Ui -Content $card.Root -Modal
}

# --- manage properties -----------------------------------------------------
#
# The rules engine already knows exactly what is legal, so this panel simply
# asks it and greys out the rest. An illegal option is shown with its REASON
# rather than hidden, which is what stops the even-build rule feeling arbitrary.

function Show-RonManageOverlay {
    param([int]$PlayerId = -1)
    $App = (Get-RonApp)
    $Ui = $App.Ui
    $State = $App.State
    if ($PlayerId -lt 0) { $PlayerId = Get-RonActingPlayerId -State $State }
    $player = $State.Players[$PlayerId]

    $card = New-RonOverlayCard -Ui $Ui -Title 'Your property' `
        -Subtitle ("$($player.Name)  -  " + (Format-RonMoney $player.Cash) + ' in hand') -Width 760
    $scroll = New-RonScrollBody -MaxHeight 480
    [void]$card.Body.Children.Add($scroll.Scroll)

    $owned = @(Get-RonOwnedIndices -State $State -PlayerId $PlayerId)
    if ($owned.Count -eq 0) {
        [void]$scroll.Inner.Children.Add((New-RonLabel -Text 'You do not own anything yet.'))
    }

    foreach ($index in $owned) {
        $deed = $State.Properties[$index]
        $row = New-RonRowGrid -Widths @('12','*','Auto','Auto','Auto')
        $row.Margin = New-Object System.Windows.Thickness(0, 2, 0, 2)

        $swatch = New-Object System.Windows.Controls.Border
        $swatch.Width = 9
        $swatch.CornerRadius = New-Object System.Windows.CornerRadius 2
        $group = Get-RonSpaceGroup $index
        $colours = (Get-RonBoard).GroupColours
        if ($colours.ContainsKey($group)) { $swatch.Background = New-RonBrush ([string]$colours[$group]) }
        [System.Windows.Controls.Grid]::SetColumn($swatch, 0)
        [void]$row.Children.Add($swatch)

        $label = Get-RonSpaceName $index
        $bits = New-Object System.Collections.ArrayList
        if ($deed.Houses -eq 5)    { [void]$bits.Add('hotel') }
        elseif ($deed.Houses -gt 0) { [void]$bits.Add("$($deed.Houses) house(s)") }
        if ($deed.Mortgaged)       { [void]$bits.Add('mortgaged') }
        if ($bits.Count -gt 0)     { $label += '   (' + ($bits.ToArray() -join ', ') + ')' }
        $name = New-RonLabel -Text $label -Column 1
        $name.Margin = New-Object System.Windows.Thickness(10, 0, 10, 0)
        [void]$row.Children.Add($name)

        # Only streets can carry buildings; a "Build 0" button on a station or a
        # utility is just noise.
        if (Test-RonIsStreet $index) {
            [void]$row.Children.Add((New-RonManageButton -Index $index -PlayerId $PlayerId -Kind 'BuildHouse'   -Column 2))
            [void]$row.Children.Add((New-RonManageButton -Index $index -PlayerId $PlayerId -Kind 'SellBuilding' -Column 3))
        }
        if ($deed.Mortgaged) {
            [void]$row.Children.Add((New-RonManageButton -Index $index -PlayerId $PlayerId -Kind 'Unmortgage' -Column 4))
        }
        else {
            [void]$row.Children.Add((New-RonManageButton -Index $index -PlayerId $PlayerId -Kind 'Mortgage' -Column 4))
        }
        [void]$scroll.Inner.Children.Add($row)
    }

    Add-RonOverlayButton -Ui $Ui -Card $card -Label 'Done' -Style 'Button.Primary' -OnClick {
        Hide-RonOverlay -Ui (Get-RonApp).Ui
    } | Out-Null

    Show-RonOverlay -Ui $Ui -Content $card.Root -Modal
}

# A management button that asks the engine whether it is legal, and if not says
# why in its tooltip.
function New-RonManageButton {
    param([int]$Index, [int]$PlayerId, [string]$Kind, [int]$Column)
    $App = (Get-RonApp)
    $State = $App.State
    $reason = ''
    $legal = $false
    $label = ''

    switch ($Kind) {
        'BuildHouse' {
            $legal = Test-RonCanBuildHouse -State $State -PlayerId $PlayerId -SpaceIndex $Index -Reason ([ref]$reason)
            $cost = Get-RonHouseCost $Index
            $label = 'Build ' + (Format-RonMoney $cost)
            if ($State.Properties[$Index].Houses -eq 4) { $label = 'Hotel ' + (Format-RonMoney $cost) }
        }
        'SellBuilding' {
            $legal = Test-RonCanSellBuilding -State $State -PlayerId $PlayerId -SpaceIndex $Index -Reason ([ref]$reason)
            $label = 'Sell ' + (Format-RonMoney ([int]((Get-RonHouseCost $Index) / 2)))
        }
        'Mortgage' {
            $legal = Test-RonCanMortgage -State $State -PlayerId $PlayerId -SpaceIndex $Index -Reason ([ref]$reason)
            $label = 'Mortgage ' + (Format-RonMoney (Get-RonMortgageValue $Index))
        }
        'Unmortgage' {
            $legal = Test-RonCanUnmortgage -State $State -PlayerId $PlayerId -SpaceIndex $Index -Reason ([ref]$reason)
            $label = 'Redeem ' + (Format-RonMoney (Get-RonUnmortgageCost -Index $Index -Rules $State.Rules))
        }
    }

    $btn = New-Object System.Windows.Controls.Button
    $btn.Content = $label
    $btn.Style = $App.Ui.Window.FindResource('Button.Row')
    $btn.IsEnabled = [bool]$legal
    if (-not $legal -and $reason) { $btn.ToolTip = $reason }
    [System.Windows.Controls.Grid]::SetColumn($btn, $Column)

    $action = @{ Kind = $Kind; PlayerId = $PlayerId; SpaceIndex = $Index }
    $btn.Add_Click({
        Submit-RonUiAction -Action $action
        # Rebuild the panel so every row reflects the new legality - the even
        # build rule means one purchase changes what is allowed elsewhere.
        Show-RonManageOverlay -PlayerId $action.PlayerId
    }.GetNewClosure())
    return $btn
}

# --- trade -----------------------------------------------------------------
#
# Two columns, one per side, with a live legality line underneath. That line is
# driven by the engine's own Test-RonTradeLegal, so what the panel says is
# legal and what the host will accept can never disagree.
#
# The same panel builds a COUNTER-OFFER: answering an offer opens it seeded
# with that offer reversed, so haggling is editing the deal in front of you
# rather than starting again from an empty table.

function Show-RonTradeOverlay {
    param(
        [int]$FromId = -1,
        # Present = counter mode. The seed is the offer being answered, stated
        # from the ORIGINAL proposer's point of view; it is flipped below.
        [object]$Seed = $null
    )
    $App = (Get-RonApp)
    $Ui = $App.Ui
    $State = $App.State
    $isCounter = ($null -ne $Seed)
    if ($isCounter) { $FromId = [int]$Seed.ToId }
    if ($FromId -lt 0) { $FromId = Get-RonActingPlayerId -State $State }

    $others = @()
    foreach ($p in $State.ActivePlayers()) { if ($p.Id -ne $FromId) { $others += $p.Id } }
    if ($others.Count -eq 0) { return }

    $ctx = @{
        FromId   = $FromId
        ToId     = $others[0]
        Give     = New-Object System.Collections.ArrayList
        Get      = New-Object System.Collections.ArrayList
        GiveCash = 0
        GetCash  = 0
        GiveJail = 0
        GetJail  = 0
    }

    # Seeding a counter is a straight swap of sides: what they asked me for is
    # what I am now offering to give, and vice versa. Their terms stay on the
    # table until the player edits them, which is the whole point - most
    # haggling is one number away from a deal.
    if ($isCounter) {
        $ctx.ToId = [int]$Seed.FromId
        foreach ($i in @($Seed.GetProperties))  { [void]$ctx.Give.Add([int]$i) }
        foreach ($i in @($Seed.GiveProperties)) { [void]$ctx.Get.Add([int]$i) }
        $ctx.GiveCash = [int]$Seed.GetCash
        $ctx.GetCash  = [int]$Seed.GiveCash
        $ctx.GiveJail = [int]$Seed.GetJailCards
        $ctx.GetJail  = [int]$Seed.GiveJailCards
    }

    $title = 'Propose a trade'
    $subtitle = 'Tick what changes hands, add cash on either side, and the panel says whether it is legal.'
    if ($isCounter) {
        $title = 'Counter-offer to ' + $State.Players[$ctx.ToId].Name
        $subtitle = 'Their offer, seen from your side of the table. Change anything and send it back.'
    }
    $card = New-RonOverlayCard -Ui $Ui -Title $title -Subtitle $subtitle -Width 900

    $picker = New-RonRowGrid -Widths @('Auto','*')
    $picker.Children.Add((New-RonLabel -Text 'Trade with' -Column 0)) | Out-Null
    $combo = New-Object System.Windows.Controls.ComboBox
    $combo.Margin = New-Object System.Windows.Thickness(12, 0, 0, 0)
    $combo.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
    $combo.MinWidth = 220
    # A DATA template rather than chips built here, and that is not a style
    # choice: a ComboBox shows the selected item twice - once in the list and
    # once in the closed box - and a single visual cannot have two parents.
    # Handing WPF a template lets it build one for each place.
    $combo.ItemTemplate = ConvertFrom-RonXaml @"
<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
  <Border CornerRadius="6" Padding="9,2,9,3" Background="{Binding Swatch}">
    <TextBlock Text="{Binding Name}" Foreground="{Binding Ink}" FontWeight="SemiBold" FontSize="14" />
  </Border>
</DataTemplate>
"@
    foreach ($id in $others) { [void]$combo.Items.Add((New-RonPlayerListItem -State $State -PlayerId $id)) }
    $combo.SelectedIndex = [array]::IndexOf($others, $ctx.ToId)
    if ($combo.SelectedIndex -lt 0) { $combo.SelectedIndex = 0 }
    # A counter answers ONE player; letting the box change who it goes to would
    # silently turn it back into an ordinary proposal.
    if ($isCounter) { $combo.IsEnabled = $false }
    [System.Windows.Controls.Grid]::SetColumn($combo, 1)
    [void]$picker.Children.Add($combo)
    [void]$card.Body.Children.Add($picker)

    $columns = New-RonRowGrid -Widths @('*','*')
    $columns.Margin = New-Object System.Windows.Thickness(0, 16, 0, 0)
    $leftBox  = New-Object System.Windows.Controls.StackPanel
    $rightBox = New-Object System.Windows.Controls.StackPanel
    $leftBox.Margin  = New-Object System.Windows.Thickness(0, 0, 10, 0)
    $rightBox.Margin = New-Object System.Windows.Thickness(10, 0, 0, 0)
    [System.Windows.Controls.Grid]::SetColumn($leftBox, 0)
    [System.Windows.Controls.Grid]::SetColumn($rightBox, 1)
    [void]$columns.Children.Add($leftBox)
    [void]$columns.Children.Add($rightBox)
    [void]$card.Body.Children.Add($columns)

    $verdict = New-Object System.Windows.Controls.TextBlock
    $verdict.Margin = New-Object System.Windows.Thickness(0, 16, 0, 0)
    $verdict.TextWrapping = [System.Windows.TextWrapping]::Wrap
    [void]$card.Body.Children.Add($verdict)

    $good = $Ui.Window.FindResource('Brush.Good')
    $bad  = $Ui.Window.FindResource('Brush.Danger')
    $dim  = $Ui.Window.FindResource('Brush.TextDim')
    $state = @{ Button = $null }

    # Three different things the line can say, and they are not the same thing:
    # nothing offered yet, offered but against the rules, and legal but a deal
    # the other side has no reason to take. The last one is the whole skill of
    # trading, so it gets said out loud rather than left to be discovered by
    # being refused.
    $refresh = {
        $st = (Get-RonApp).State
        $offer = New-RonTradeOfferFromContext -Context $ctx
        if ($offer.IsEmpty()) {
            $verdict.Text = 'Tick something on either side, or add cash, to make an offer.'
            $verdict.Foreground = $dim
            if ($null -ne $state.Button) { $state.Button.IsEnabled = $false }
            return
        }
        $why = ''
        $ok = Test-RonTradeLegal -State $st -Offer $offer -Reason ([ref]$why)
        if (-not $ok) {
            $verdict.Text = $why
            $verdict.Foreground = $bad
        }
        else {
            $mine   = Get-RonTradeGain -State $st -Offer $offer -ForPlayerId $offer.FromId
            $theirs = Get-RonTradeGain -State $st -Offer $offer -ForPlayerId $offer.ToId
            $verdict.Text = ('Worth about {0} to you, {1} to them.' -f (Format-RonMoney $mine), (Format-RonMoney $theirs))
            if ($theirs -le 0) {
                $verdict.Text = $verdict.Text + '   They will almost certainly refuse.'
                $verdict.Foreground = $dim
            }
            else { $verdict.Foreground = $good }
        }
        if ($null -ne $state.Button) { $state.Button.IsEnabled = $ok }
    }.GetNewClosure()

    $rebuild = {
        $st = (Get-RonApp).State
        $leftBox.Children.Clear()
        $rightBox.Children.Clear()
        $mine  = $st.Players[$ctx.FromId]
        $yours = $st.Players[$ctx.ToId]

        [void]$leftBox.Children.Add((New-RonPlayerHeading -Ui $Ui -State $st -Text 'YOU GIVE' -PlayerId $ctx.FromId))
        foreach ($i in (Get-RonOwnedIndices -State $st -PlayerId $ctx.FromId)) {
            [void]$leftBox.Children.Add((New-RonTradeCheck -Ui $Ui -State $st -Index $i -Bag $ctx.Give -OnChange $refresh))
        }
        [void]$leftBox.Children.Add((New-RonCashBox -Ui $Ui -Label 'Cash you add' -Context $ctx -Field 'GiveCash' -Cap $mine.Cash -OnChange $refresh))
        if ($mine.JailCards -gt 0 -or $ctx.GiveJail -gt 0) {
            [void]$leftBox.Children.Add((New-RonJailCardBox -Ui $Ui -Label 'Jail cards you add' -Context $ctx -Field 'GiveJail' -Cap $mine.JailCards -OnChange $refresh))
        }

        [void]$rightBox.Children.Add((New-RonPlayerHeading -Ui $Ui -State $st -Text 'YOU GET' -PlayerId $ctx.ToId))
        foreach ($i in (Get-RonOwnedIndices -State $st -PlayerId $ctx.ToId)) {
            [void]$rightBox.Children.Add((New-RonTradeCheck -Ui $Ui -State $st -Index $i -Bag $ctx.Get -OnChange $refresh))
        }
        [void]$rightBox.Children.Add((New-RonCashBox -Ui $Ui -Label 'Cash you want' -Context $ctx -Field 'GetCash' -Cap $yours.Cash -OnChange $refresh))
        if ($yours.JailCards -gt 0 -or $ctx.GetJail -gt 0) {
            [void]$rightBox.Children.Add((New-RonJailCardBox -Ui $Ui -Label 'Jail cards you want' -Context $ctx -Field 'GetJail' -Cap $yours.JailCards -OnChange $refresh))
        }
        & $refresh
    }.GetNewClosure()

    $combo.Add_SelectionChanged({
        if ($combo.SelectedIndex -lt 0) { return }
        $ctx.ToId = $others[$combo.SelectedIndex]
        $ctx.Get.Clear()
        $ctx.GetCash = 0
        $ctx.GetJail = 0
        & $rebuild
    }.GetNewClosure())

    $sendLabel = 'Offer trade'
    if ($isCounter) { $sendLabel = 'Send counter-offer' }
    $state.Button = Add-RonOverlayButton -Ui $Ui -Card $card -Label $sendLabel -Style 'Button.Primary' -OnClick {
        $offer = New-RonTradeOfferFromContext -Context $ctx
        $kind = 'ProposeTrade'
        if ($isCounter) { $kind = 'CounterTrade' }
        Hide-RonOverlay -Ui (Get-RonApp).Ui
        Submit-RonUiAction -Action @{ Kind = $kind; PlayerId = $ctx.FromId; Offer = $offer.ToData() }
    }.GetNewClosure()

    # Backing out of a counter is not the same as backing out of a proposal:
    # there is still an offer on the table waiting for a yes or a no.
    if ($isCounter) {
        $toId = $ctx.FromId
        Add-RonOverlayButton -Ui $Ui -Card $card -Label 'Back' -OnClick {
            Hide-RonOverlay -Ui (Get-RonApp).Ui
        }.GetNewClosure() | Out-Null
        Add-RonOverlayButton -Ui $Ui -Card $card -Label 'Just reject it' -OnClick {
            Hide-RonOverlay -Ui (Get-RonApp).Ui
            Submit-RonUiAction -Action @{ Kind = 'RespondTrade'; PlayerId = $toId; Accept = $false }
        }.GetNewClosure() | Out-Null
    }
    else {
        Add-RonOverlayButton -Ui $Ui -Card $card -Label 'Cancel' -OnClick {
            Hide-RonOverlay -Ui (Get-RonApp).Ui
        } | Out-Null
    }

    & $rebuild
    Show-RonOverlay -Ui $Ui -Content $card.Root -Modal
}

function New-RonTradeOfferFromContext {
    param([Parameter(Mandatory)][hashtable]$Context)
    $offer = [TradeOffer]::new()
    $offer.FromId = $Context.FromId
    $offer.ToId = $Context.ToId
    $offer.GiveProperties = [int[]]$Context.Give.ToArray()
    $offer.GetProperties  = [int[]]$Context.Get.ToArray()
    $offer.GiveCash = [int]$Context.GiveCash
    $offer.GetCash  = [int]$Context.GetCash
    $offer.GiveJailCards = [int]$Context.GiveJail
    $offer.GetJailCards  = [int]$Context.GetJail
    return $offer
}

# One deed, with its group colour, and greyed out with the reason when the
# rules will not let it move - the same treatment Manage property gives an
# illegal build, for the same reason: a rule you can see is not arbitrary.
function New-RonTradeCheck {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][GameState]$State,
        [int]$Index,
        [System.Collections.ArrayList]$Bag,
        [scriptblock]$OnChange
    )
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = [System.Windows.Controls.Orientation]::Horizontal

    $swatch = New-Object System.Windows.Controls.Border
    $swatch.Width = 9
    $swatch.Height = 18
    $swatch.CornerRadius = New-Object System.Windows.CornerRadius 2
    $swatch.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $group = Get-RonSpaceGroup $Index
    $colours = (Get-RonBoard).GroupColours
    if ($group -and $colours.ContainsKey($group)) { $swatch.Background = New-RonBrush ([string]$colours[$group]) }
    else { $swatch.Background = $Ui.Window.FindResource('Brush.Line') }
    [void]$row.Children.Add($swatch)

    $label = Get-RonSpaceName $Index
    if ($State.Properties[$Index].Mortgaged) { $label += '   (mortgaged)' }
    $text = New-Object System.Windows.Controls.TextBlock
    $text.Text = $label
    $text.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0)
    $text.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [void]$row.Children.Add($text)

    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Content = $row
    $cb.Margin = New-Object System.Windows.Thickness(0, 4, 0, 4)
    $cb.IsChecked = ($Bag -contains $Index)

    if ($group -and (Test-RonGroupHasBuildings -State $State -Group $group)) {
        $cb.IsEnabled = $false
        $cb.ToolTip = Get-RonString 'Error.HasBuildings'
    }

    $cb.Add_Checked({   if (-not ($Bag -contains $Index)) { [void]$Bag.Add($Index) } ; & $OnChange }.GetNewClosure())
    $cb.Add_Unchecked({ [void]$Bag.Remove($Index) ; & $OnChange }.GetNewClosure())
    return $cb
}

# A cash field with the two or three amounts anybody actually types.
function New-RonCashBox {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [string]$Label,
        [hashtable]$Context,
        [string]$Field,
        [int]$Cap = 0,
        [scriptblock]$OnChange
    )
    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = New-Object System.Windows.Thickness(0, 14, 0, 0)
    [void]$panel.Children.Add((New-RonHeading -Ui $Ui -Text $Label.ToUpper()))

    $row = New-RonRowGrid -Widths @('*','Auto','Auto','Auto')
    $box = New-Object System.Windows.Controls.TextBox
    $box.Text = [string]$Context[$Field]
    [System.Windows.Controls.Grid]::SetColumn($box, 0)
    $box.Add_TextChanged({
        $value = 0
        [void][int]::TryParse($box.Text.Trim(), [ref]$value)
        if ($value -lt 0) { $value = 0 }
        $Context[$Field] = $value
        & $OnChange
    }.GetNewClosure())
    [void]$row.Children.Add($box)

    $col = 1
    foreach ($step in @(50, 100)) {
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = '+' + (Format-RonMoney $step)
        $btn.Style = $Ui.Window.FindResource('Button.Row')
        [System.Windows.Controls.Grid]::SetColumn($btn, $col)
        $bump = $step
        $btn.Add_Click({
            $value = 0
            [void][int]::TryParse($box.Text.Trim(), [ref]$value)
            $box.Text = [string]($value + $bump)
        }.GetNewClosure())
        [void]$row.Children.Add($btn)
        $col++
    }
    $zero = New-Object System.Windows.Controls.Button
    $zero.Content = 'Clear'
    $zero.Style = $Ui.Window.FindResource('Button.Row')
    [System.Windows.Controls.Grid]::SetColumn($zero, 3)
    $zero.Add_Click({ $box.Text = '0' }.GetNewClosure())
    [void]$row.Children.Add($zero)
    [void]$panel.Children.Add($row)

    if ($Cap -gt 0) {
        $note = New-RonLabel -Text ('Up to ' + (Format-RonMoney $Cap))
        $note.Style = $Ui.Window.FindResource('Text.Dim')
        $note.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
        [void]$panel.Children.Add($note)
    }
    return $panel
}

# Get Out Of Jail Free cards are tradeable property under the printed rules,
# and worth real money late on - a stepper is the whole interface they need.
function New-RonJailCardBox {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [string]$Label,
        [hashtable]$Context,
        [string]$Field,
        [int]$Cap = 0,
        [scriptblock]$OnChange
    )
    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = New-Object System.Windows.Thickness(0, 14, 0, 0)
    [void]$panel.Children.Add((New-RonHeading -Ui $Ui -Text $Label.ToUpper()))

    $row = New-RonRowGrid -Widths @('Auto','Auto','*')
    $minus = New-Object System.Windows.Controls.Button
    $minus.Content = '-'
    $minus.Style = $Ui.Window.FindResource('Button.Row')
    $minus.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0)
    [System.Windows.Controls.Grid]::SetColumn($minus, 0)
    $plus = New-Object System.Windows.Controls.Button
    $plus.Content = '+'
    $plus.Style = $Ui.Window.FindResource('Button.Row')
    [System.Windows.Controls.Grid]::SetColumn($plus, 1)
    $count = New-RonLabel -Text ([string]$Context[$Field] + ' of ' + $Cap) -Column 2
    $count.Margin = New-Object System.Windows.Thickness(12, 0, 0, 0)

    $minus.Add_Click({
        if ($Context[$Field] -gt 0) { $Context[$Field] = $Context[$Field] - 1 }
        $count.Text = [string]$Context[$Field] + ' of ' + $Cap
        & $OnChange
    }.GetNewClosure())
    $plus.Add_Click({
        if ($Context[$Field] -lt $Cap) { $Context[$Field] = $Context[$Field] + 1 }
        $count.Text = [string]$Context[$Field] + ' of ' + $Cap
        & $OnChange
    }.GetNewClosure())

    [void]$row.Children.Add($minus)
    [void]$row.Children.Add($plus)
    [void]$row.Children.Add($count)
    [void]$panel.Children.Add($row)
    return $panel
}

function Get-RonTradeSummary {
    param([Parameter(Mandatory)][GameState]$State, [Parameter(Mandatory)][TradeOffer]$Offer)
    $mine = Get-RonTradeGain -State $State -Offer $Offer -ForPlayerId $Offer.FromId
    $theirs = Get-RonTradeGain -State $State -Offer $Offer -ForPlayerId $Offer.ToId
    return ('Worth about {0} to you, {1} to them.' -f (Format-RonMoney $mine), (Format-RonMoney $theirs))
}

# Lists one side of an offer, in the order a person reads a deal.
function Add-RonOfferColumn {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][System.Windows.Controls.Panel]$Panel,
        [Parameter(Mandatory)][GameState]$State,
        [string]$Heading,
        [int]$FromPlayerId = -1,
        [int[]]$Properties,
        [int]$Cash,
        [int]$JailCards
    )
    if ($FromPlayerId -ge 0) {
        [void]$Panel.Children.Add((New-RonPlayerHeading -Ui $Ui -State $State -Text $Heading -PlayerId $FromPlayerId))
    }
    else {
        [void]$Panel.Children.Add((New-RonHeading -Ui $Ui -Text $Heading))
    }
    $empty = $true
    foreach ($i in @($Properties)) {
        [void]$Panel.Children.Add((New-RonLabel -Text (Get-RonSpaceName $i)))
        $empty = $false
    }
    if ($Cash -gt 0) {
        [void]$Panel.Children.Add((New-RonLabel -Text (Format-RonMoney $Cash)))
        $empty = $false
    }
    if ($JailCards -gt 0) {
        $word = 'jail cards'
        if ($JailCards -eq 1) { $word = 'jail card' }
        [void]$Panel.Children.Add((New-RonLabel -Text ("$JailCards $word")))
        $empty = $false
    }
    if ($empty) {
        $none = New-RonLabel -Text 'nothing'
        $none.Style = $Ui.Window.FindResource('Text.Dim')
        [void]$Panel.Children.Add($none)
    }
}

# The answering side of a trade.
function Show-RonTradeResponseOverlay {
    $App = (Get-RonApp)
    $Ui = $App.Ui
    $State = $App.State
    $offer = $State.Turn.Trade
    if ($null -eq $offer) { return }

    $from = $State.Players[$offer.FromId].Name
    $title = "$from proposes a trade"
    if ($State.Turn.TradesProposed -gt 1) { $title = "$from counters" }
    $card = New-RonOverlayCard -Ui $Ui -Title $title `
        -Subtitle (Get-RonTradeSummary -State $State -Offer $offer) -Width 700

    $columns = New-RonRowGrid -Widths @('*','*')
    $left  = New-Object System.Windows.Controls.StackPanel
    $right = New-Object System.Windows.Controls.StackPanel
    $left.Margin  = New-Object System.Windows.Thickness(0, 0, 10, 0)
    $right.Margin = New-Object System.Windows.Thickness(10, 0, 0, 0)
    [System.Windows.Controls.Grid]::SetColumn($left, 0)
    [System.Windows.Controls.Grid]::SetColumn($right, 1)
    [void]$columns.Children.Add($left)
    [void]$columns.Children.Add($right)
    [void]$card.Body.Children.Add($columns)

    Add-RonOfferColumn -Ui $Ui -Panel $left -State $State -Heading 'YOU RECEIVE' -FromPlayerId $offer.FromId `
        -Properties @($offer.GiveProperties) -Cash $offer.GiveCash -JailCards $offer.GiveJailCards
    Add-RonOfferColumn -Ui $Ui -Panel $right -State $State -Heading 'YOU GIVE' -FromPlayerId $offer.ToId `
        -Properties @($offer.GetProperties) -Cash $offer.GetCash -JailCards $offer.GetJailCards

    $toId = $offer.ToId
    Add-RonOverlayButton -Ui $Ui -Card $card -Label 'Accept' -Style 'Button.Primary' -OnClick {
        Hide-RonOverlay -Ui (Get-RonApp).Ui
        Submit-RonUiAction -Action @{ Kind = 'RespondTrade'; PlayerId = $toId; Accept = $true }
    }.GetNewClosure() | Out-Null

    # Haggling. The engine caps how many times one offer may be volleyed in a
    # turn, so the button goes dead at the same point the rule does - and says
    # why, instead of silently rejecting the click.
    $chainDone = ($State.Turn.TradesProposed -ge (Get-RonMaxTradeChain))
    Add-RonOverlayButton -Ui $Ui -Card $card -Label 'Counter-offer' -Enabled (-not $chainDone) -OnClick {
        Show-RonTradeOverlay -Seed (Get-RonApp).State.Turn.Trade
    } | Out-Null
    if ($chainDone) {
        $note = New-RonLabel -Text 'This has been round enough times - take it or leave it.'
        $note.Style = $Ui.Window.FindResource('Text.Dim')
        $note.Margin = New-Object System.Windows.Thickness(0, 10, 0, 0)
        [void]$card.Body.Children.Add($note)
    }

    Add-RonOverlayButton -Ui $Ui -Card $card -Label 'Reject' -OnClick {
        Hide-RonOverlay -Ui (Get-RonApp).Ui
        Submit-RonUiAction -Action @{ Kind = 'RespondTrade'; PlayerId = $toId; Accept = $false }
    }.GetNewClosure() | Out-Null

    Show-RonOverlay -Ui $Ui -Content $card.Root
}

# --- new game --------------------------------------------------------------

function Show-RonNewGameOverlay {
    $App = (Get-RonApp)
    $Ui = $App.Ui
    $tokens = (Get-RonTokens).Order
    $names = @('You','Ada','Blake','Cleo','Dax','Esme','Fox','Gwen')
    $kinds = @('Human','AI','Off')
    $profiles = Get-RonAiProfileNames

    $card = New-RonOverlayCard -Ui $Ui -Title 'New game' `
        -Subtitle 'Set up the table. Any mix of people and bots, two to eight seats.' -Width 760

    $rows = @()
    for ($i = 0; $i -lt 8; $i++) {
        $seatKind = 'Off'
        if ($i -eq 0) { $seatKind = 'Human' }
        elseif ($i -lt 4) { $seatKind = 'AI' }
        $seatProfile = 'Normal'
        if ($i -eq 2) { $seatProfile = 'Hard' }
        if ($i -eq 3) { $seatProfile = 'Expert' }

        $row = New-RonRowGrid -Widths @('38','*','130','140')
        $tokenImg = New-Object System.Windows.Controls.Image
        $tokenImg.Source = Get-RonTokenImage $tokens[$i]
        $tokenImg.Width = 30
        $tokenImg.Height = 30
        [System.Windows.Controls.Grid]::SetColumn($tokenImg, 0)
        [void]$row.Children.Add($tokenImg)

        $nameBox = New-Object System.Windows.Controls.TextBox
        $nameBox.Text = $names[$i]
        $nameBox.Margin = New-Object System.Windows.Thickness(6, 0, 8, 0)
        $nameBox.Padding = New-Object System.Windows.Thickness(6, 4, 6, 4)
        [System.Windows.Controls.Grid]::SetColumn($nameBox, 1)
        [void]$row.Children.Add($nameBox)

        $kindBox = New-Object System.Windows.Controls.ComboBox
        foreach ($k in $kinds) { [void]$kindBox.Items.Add($k) }
        $kindBox.SelectedItem = $seatKind
        $kindBox.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
        [System.Windows.Controls.Grid]::SetColumn($kindBox, 2)
        [void]$row.Children.Add($kindBox)

        $profileBox = New-Object System.Windows.Controls.ComboBox
        foreach ($p in $profiles) { [void]$profileBox.Items.Add($p) }
        $profileBox.SelectedItem = $seatProfile
        [System.Windows.Controls.Grid]::SetColumn($profileBox, 3)
        [void]$row.Children.Add($profileBox)

        [void]$card.Body.Children.Add($row)
        $rows += @{ Name = $nameBox; Kind = $kindBox; Profile = $profileBox; Token = $tokens[$i] }
    }

    $note = New-Object System.Windows.Controls.TextBlock
    $note.Margin = New-Object System.Windows.Thickness(0, 10, 0, 0)
    $note.TextWrapping = [System.Windows.TextWrapping]::Wrap
    [void]$card.Body.Children.Add($note)

    Add-RonOverlayButton -Ui $Ui -Card $card -Label 'Start' -Style 'Button.Primary' -OnClick {
        $seats = New-Object System.Collections.ArrayList
        foreach ($r in $rows) {
            if ([string]$r.Kind.SelectedItem -eq 'Off') { continue }
            [void]$seats.Add((New-RonSeat -Name $r.Name.Text.Trim() -Kind ([string]$r.Kind.SelectedItem) `
                -AiProfile ([string]$r.Profile.SelectedItem) -Token $r.Token))
        }
        $why = ''
        if (-not (Test-RonSeatsValid -Seats $seats.ToArray() -Reason ([ref]$why))) {
            $note.Text = $why
            $note.Foreground = $Ui.Window.FindResource('Brush.Danger')
            return
        }
        Hide-RonOverlay -Ui (Get-RonApp).Ui
        Start-RonNewGame -Seats $seats.ToArray() -Rules (Get-RonApp).Rules
    }.GetNewClosure() | Out-Null

    Add-RonOverlayButton -Ui $Ui -Card $card -Label 'Cancel' -OnClick {
        Hide-RonOverlay -Ui (Get-RonApp).Ui
    } | Out-Null

    Show-RonOverlay -Ui $Ui -Content $card.Root -Modal
}

# --- house rules -----------------------------------------------------------
#
# Every flag here is read by the engine through GameState.RuleOn / RuleInt and
# nowhere else, so a toggle genuinely changes how the game plays rather than
# just how it is described.

$script:RonRuleBlurbs = @(
    @{ Key = 'FreeParkingJackpot';    Label = 'Free Parking jackpot';        Note = 'Fines and taxes pile up on Free Parking and go to whoever lands there. The most common house rule, and the one that lengthens games the most.' }
    @{ Key = 'TaxesToFreeParking';    Label = 'Taxes feed the jackpot';      Note = 'Income Tax and Super Tax go to the pot rather than the bank. Only does anything with the jackpot on.' }
    @{ Key = 'DisableAuctions';       Label = 'No auctions';                 Note = 'Declining a property leaves it with the bank instead of putting it under the hammer.' }
    @{ Key = 'UnlimitedBuildings';    Label = 'Unlimited houses and hotels'; Note = 'Ignores the 32 house / 12 hotel supply, removing the building shortage as a weapon.' }
    @{ Key = 'DoubleSalaryOnExactGo'; Label = 'Double salary on exact Go';   Note = 'Landing exactly on Go pays 400 instead of 200.' }
    @{ Key = 'NoRentInJail';          Label = 'No rent while in jail';       Note = 'A jailed owner collects nothing.' }
    @{ Key = 'SnakeEyesBonus';        Label = 'Snake eyes bonus';            Note = 'Rolling double one pays a bonus from the bank.' }
    @{ Key = 'MortgageInterestFree';  Label = 'No mortgage interest';        Note = 'Redeeming a mortgage costs the mortgage value with no 10% on top.' }
    @{ Key = 'AllowBidToRaiseFunds';  Label = 'Bid beyond your cash';        Note = 'A bidder may mortgage and sell buildings mid-auction to cover a bid.' }
    @{ Key = 'AuctionBankruptEstate'; Label = 'Auction a bankrupt estate';   Note = 'A printed rule most clones skip: when a player goes bankrupt to the BANK, their property is auctioned to the survivors. On by default.' }
)

function Show-RonRulesOverlay {
    $App = (Get-RonApp)
    $Ui = $App.Ui
    $rules = $App.Rules

    $card = New-RonOverlayCard -Ui $Ui -Title 'House rules' `
        -Subtitle 'Official rules by default. Changes apply to the NEXT game.' -Width 780
    $scroll = New-RonScrollBody -MaxHeight 440
    [void]$card.Body.Children.Add($scroll.Scroll)

    $boxes = @{}
    foreach ($rule in $script:RonRuleBlurbs) {
        $panel = New-Object System.Windows.Controls.StackPanel
        $panel.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)

        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = $rule.Label
        $cb.FontWeight = [System.Windows.FontWeights]::SemiBold
        $cb.IsChecked = [bool]$rules[$rule.Key]
        [void]$panel.Children.Add($cb)

        $note = New-Object System.Windows.Controls.TextBlock
        $note.Text = $rule.Note
        $note.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $note.Style = $Ui.Window.FindResource('Text.Dim')
        $note.Margin = New-Object System.Windows.Thickness(24, 2, 0, 0)
        [void]$panel.Children.Add($note)

        [void]$scroll.Inner.Children.Add($panel)
        $boxes[$rule.Key] = $cb
    }

    $limitRow = New-RonRowGrid -Widths @('*','140')
    $limitRow.Children.Add((New-RonLabel -Text 'Turn limit (0 = no limit)' -Column 0)) | Out-Null
    $limitBox = New-Object System.Windows.Controls.TextBox
    $limitBox.Text = [string]$rules['TurnLimit']
    $limitBox.Padding = New-Object System.Windows.Thickness(6, 4, 6, 4)
    [System.Windows.Controls.Grid]::SetColumn($limitBox, 1)
    [void]$limitRow.Children.Add($limitBox)
    [void]$scroll.Inner.Children.Add($limitRow)

    Add-RonOverlayButton -Ui $Ui -Card $card -Label 'Save' -Style 'Button.Primary' -OnClick {
        $target = (Get-RonApp).Rules
        foreach ($key in $boxes.Keys) { $target[$key] = [bool]$boxes[$key].IsChecked }
        $limit = 0
        [void][int]::TryParse($limitBox.Text.Trim(), [ref]$limit)
        $target['TurnLimit'] = [math]::Max(0, $limit)
        Hide-RonOverlay -Ui (Get-RonApp).Ui
        Add-RonLogLine -Ui (Get-RonApp).Ui -Text 'House rules saved - they take effect next game.'
    }.GetNewClosure() | Out-Null

    Add-RonOverlayButton -Ui $Ui -Card $card -Label 'Cancel' -OnClick {
        Hide-RonOverlay -Ui (Get-RonApp).Ui
    } | Out-Null

    Show-RonOverlay -Ui $Ui -Content $card.Root -Modal
}

# --- save and load ---------------------------------------------------------

function Show-RonSaveOverlay {
    $App = Get-RonApp
    $Ui = $App.Ui
    $state = $App.State

    $card = New-RonOverlayCard -Ui $Ui -Title 'Saved games' `
        -Subtitle 'A save restores the dice stream too, so a reloaded game plays out exactly as it would have.' -Width 700

    $nameRow = New-RonRowGrid -Widths @('Auto','*')
    $nameRow.Children.Add((New-RonLabel -Text 'Save as' -Column 0)) | Out-Null
    $nameBox = New-Object System.Windows.Controls.TextBox
    $nameBox.Text = 'ronopoly-' + (Get-Date -Format 'yyyyMMdd-HHmm')
    $nameBox.Margin = New-Object System.Windows.Thickness(10, 0, 0, 0)
    $nameBox.Padding = New-Object System.Windows.Thickness(6, 4, 6, 4)
    [System.Windows.Controls.Grid]::SetColumn($nameBox, 1)
    [void]$nameRow.Children.Add($nameBox)
    [void]$card.Body.Children.Add($nameRow)

    $note = New-Object System.Windows.Controls.TextBlock
    $note.Margin = New-Object System.Windows.Thickness(0, 10, 0, 6)
    $note.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $note.Style = $Ui.Window.FindResource('Text.Dim')
    [void]$card.Body.Children.Add($note)

    $scroll = New-RonScrollBody -MaxHeight 300
    [void]$card.Body.Children.Add($scroll.Scroll)

    $saves = @(Get-RonSavedGames)
    if ($saves.Count -eq 0) {
        [void]$scroll.Inner.Children.Add((New-RonLabel -Text 'No saved games yet.'))
    }
    foreach ($save in $saves) {
        $row = New-RonRowGrid -Widths @('*','Auto')
        $label = '{0}   -   turn {1}   -   {2}' -f $save.Name, $save.Turn, $save.Players
        $row.Children.Add((New-RonLabel -Text $label -Column 0)) | Out-Null

        $load = New-Object System.Windows.Controls.Button
        $load.Content = 'Load'
        $load.Style = $Ui.Window.FindResource('Button.Row')
        # Loading replaces the whole position, which only makes sense for a
        # local game - a LAN client's state belongs to its host.
        $load.IsEnabled = ((Get-RonApp).Session.Kind -eq 'Local')
        if (-not $load.IsEnabled) { $load.ToolTip = 'Only a local game can be loaded.' }
        [System.Windows.Controls.Grid]::SetColumn($load, 1)
        $path = $save.Path
        $load.Add_Click({
            $loaded = Import-RonSavedGame -Path $path
            Hide-RonOverlay -Ui (Get-RonApp).Ui
            Resume-RonSavedGame -State $loaded
        }.GetNewClosure())
        [void]$row.Children.Add($load)
        [void]$scroll.Inner.Children.Add($row)
    }

    Add-RonOverlayButton -Ui $Ui -Card $card -Label 'Save now' -Style 'Button.Primary' -OnClick {
        $safe = ($nameBox.Text.Trim() -replace '[^\w\-\. ]', '_')
        if (-not $safe) { $safe = 'ronopoly' }
        $path = Get-RonPath (Join-Path 'Saves' ($safe + '.json'))
        [void](Save-RonGame -State $state -Path $path)
        $note.Text = "Saved to $path"
        Add-RonLogLine -Ui (Get-RonApp).Ui -Text "Game saved as $safe" -Colour '#2FBF71'
    }.GetNewClosure() | Out-Null

    Add-RonOverlayButton -Ui $Ui -Card $card -Label 'Close' -OnClick {
        Hide-RonOverlay -Ui (Get-RonApp).Ui
    } | Out-Null

    Show-RonOverlay -Ui $Ui -Content $card.Root -Modal
}
