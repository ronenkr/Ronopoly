#
# Ronopoly - player tokens.
#
# Tokens live on a Canvas layered over the board grid, INSIDE the same Viewbox,
# so their coordinates are plain board units and the whole thing scales with
# the window for free.
#
# Movement is animated with a key-framed TranslateTransform, one frame per
# space passed. That is what makes a token walk AROUND the corners of the board
# instead of sliding diagonally across the middle of it.
#

$script:RonTokenSize = 46.0

function Initialize-RonTokenView {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][GameState]$State
    )
    $canvas = $Ui.TokenCanvas
    $canvas.Children.Clear()
    $tokens = @{}

    foreach ($p in $State.Players) {
        $img = New-Object System.Windows.Controls.Image
        $img.Source = Get-RonTokenImage $p.Token
        $img.Width  = $script:RonTokenSize
        $img.Height = $script:RonTokenSize
        [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, [System.Windows.Media.BitmapScalingMode]::HighQuality)

        $shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
        $shadow.BlurRadius = 10
        $shadow.ShadowDepth = 3
        $shadow.Opacity = 0.5
        $img.Effect = $shadow

        # Position is driven entirely by this transform; Canvas.Left/Top stay at
        # zero so an animation never fights the layout system.
        $tx = New-Object System.Windows.Media.TranslateTransform
        $img.RenderTransform = $tx
        [System.Windows.Controls.Canvas]::SetLeft($img, 0)
        [System.Windows.Controls.Canvas]::SetTop($img, 0)
        [void]$canvas.Children.Add($img)

        $tokens[$p.Id] = @{ Image = $img; Transform = $tx; Position = $p.Position }
    }

    $Ui.Tokens = $tokens
    Update-RonTokenPositions -Ui $Ui -State $State
    return $tokens
}

# Places every token instantly. Used on load, after a resync, and to settle
# the board once an animation has finished.
function Update-RonTokenPositions {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][GameState]$State
    )
    # Reset-RonEffects runs before Initialize-RonTokenView when a new game is
    # being set up, so there may be no token layer yet.
    if ($null -eq $Ui.Tokens) { return }
    foreach ($p in $State.Players) {
        $entry = $Ui.Tokens[$p.Id]
        if ($null -eq $entry) { continue }
        if ($p.IsBankrupt) {
            $entry.Image.Visibility = [System.Windows.Visibility]::Collapsed
            continue
        }
        $entry.Image.Visibility = [System.Windows.Visibility]::Visible
        $slot = Get-RonTokenSlot -State $State -PlayerId $p.Id
        $entry.Transform.X = $slot.X
        $entry.Transform.Y = $slot.Y
        $entry.Position = $p.Position
    }
}

# Several tokens can share a space, so they orbit its anchor point rather than
# stacking invisibly on top of each other.
function Get-RonTokenSlot {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [int]$OverridePosition = -1
    )
    $player = $State.Players[$PlayerId]
    $index = $player.Position
    if ($OverridePosition -ge 0) { $index = $OverridePosition }

    $sharing = New-Object System.Collections.ArrayList
    foreach ($other in $State.Players) {
        if ($other.IsBankrupt) { continue }
        if ($other.Position -eq $index) { [void]$sharing.Add($other.Id) }
    }
    $slot = $sharing.IndexOf($PlayerId)
    if ($slot -lt 0) { $slot = 0 }
    $count = [math]::Max(1, $sharing.Count)

    $anchor = Get-RonTokenAnchor $index
    $x = $anchor.X
    $y = $anchor.Y
    if ($count -gt 1) {
        $radius = 16.0
        $angle = ($slot * 2.0 * [math]::PI / $count) - ([math]::PI / 2.0)
        $x += $radius * [math]::Cos($angle)
        $y += $radius * [math]::Sin($angle)
    }
    return @{ X = ($x - $script:RonTokenSize / 2.0); Y = ($y - $script:RonTokenSize / 2.0) }
}

# Walks a token from one space to another, one key frame per space, and calls
# OnDone when the storyboard completes.
#
# The engine has ALREADY applied the move before this runs, so the animation is
# purely cosmetic and can be skipped, sped up or interrupted without any risk
# to game state.
function Start-RonTokenMove {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [Parameter(Mandatory)][int]$From,
        [Parameter(Mandatory)][int]$To,
        [double]$SecondsPerSpace = 0.11,
        [scriptblock]$OnDone = $null
    )
    $entry = $Ui.Tokens[$PlayerId]
    if ($null -eq $entry) {
        if ($null -ne $OnDone) { Invoke-RonGuarded -Category 'ui' -Body $OnDone }
        return
    }

    $size = Get-RonBoardSize
    $steps = New-Object System.Collections.ArrayList
    $forward = ((($To - $From) % $size) + $size) % $size
    if ($forward -eq 0) { $forward = 0 }

    # A short backwards hop ("go back three spaces") reverses rather than
    # walking 37 spaces the long way round.
    $backward = $size - $forward
    if ($forward -gt 0 -and $backward -le 3 -and $backward -lt $forward) {
        for ($n = 1; $n -le $backward; $n++) { [void]$steps.Add(((($From - $n) % $size) + $size) % $size) }
    }
    else {
        for ($n = 1; $n -le $forward; $n++) { [void]$steps.Add((($From + $n) % $size)) }
    }

    if ($steps.Count -eq 0) {
        Update-RonTokenPositions -Ui $Ui -State $State
        if ($null -ne $OnDone) { Invoke-RonGuarded -Category 'ui' -Body $OnDone }
        return
    }

    $target = Get-RonTokenSlot -State $State -PlayerId $PlayerId
    $animX = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $animY = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $t = 0.0
    for ($n = 0; $n -lt $steps.Count; $n++) {
        $t += $SecondsPerSpace
        $time = [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromSeconds($t))
        if ($n -eq $steps.Count - 1) {
            # Land on the real slot, which accounts for anyone already there.
            $px = $target.X
            $py = $target.Y
        }
        else {
            $anchor = Get-RonTokenAnchor ([int]$steps[$n])
            $px = $anchor.X - $script:RonTokenSize / 2.0
            $py = $anchor.Y - $script:RonTokenSize / 2.0
        }
        [void]$animX.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame($px, $time)))
        [void]$animY.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame($py, $time)))
    }

    # Guard in a hashtable for the same reason as the dice counter: assigning to
    # a captured variable inside a closure writes to the invocation's local
    # scope, so a plain $done flag would never actually latch.
    $guard = @{ Done = $false }
    $animX.Add_Completed({
        if ($guard.Done) { return }
        $guard.Done = $true
        # Hand the final values back to the transform, then clear the
        # animation: an un-cleared animation keeps the property read-only and
        # the next move would silently do nothing.
        $entry.Transform.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $null)
        $entry.Transform.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
        $entry.Transform.X = $target.X
        $entry.Transform.Y = $target.Y
        $entry.Position = $To
        if ($null -ne $OnDone) { Invoke-RonGuarded -Category 'ui' -Body $OnDone }
    }.GetNewClosure())

    $entry.Transform.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $animX)
    $entry.Transform.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $animY)
}
