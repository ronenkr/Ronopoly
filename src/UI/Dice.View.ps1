#
# Ronopoly - the dice.
#
# COMPUTE THEN ANIMATE. The engine resolves the roll first and the UI animates
# TOWARDS the value it already knows. Nothing about the game state depends on
# the animation finishing, so it can be skipped, sped up or interrupted at any
# moment without any risk of corruption - which is exactly what makes a fast
# "skip animations" mode safe to offer.
#

$script:RonDieSize = 58.0

function Initialize-RonDiceView {
    param([Parameter(Mandatory)][hashtable]$Ui)
    $panel = $Ui.DiceHost
    $panel.Children.Clear()

    $dice = @()
    for ($n = 0; $n -lt 2; $n++) {
        $img = New-Object System.Windows.Controls.Image
        $img.Source = Get-RonDieImage 1
        $img.Width  = $script:RonDieSize
        $img.Height = $script:RonDieSize
        $img.Margin = New-Object System.Windows.Thickness(0, 0, 10, 0)
        $img.Opacity = 0.25
        [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, [System.Windows.Media.BitmapScalingMode]::HighQuality)

        $rt = New-Object System.Windows.Media.RotateTransform
        $img.RenderTransform = $rt
        $img.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)
        [void]$panel.Children.Add($img)
        $dice += @{ Image = $img; Rotate = $rt }
    }

    $total = New-Object System.Windows.Controls.TextBlock
    $total.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $total.Margin = New-Object System.Windows.Thickness(6, 0, 0, 0)
    $total.FontSize = 17
    $total.FontWeight = [System.Windows.FontWeights]::SemiBold
    [void]$panel.Children.Add($total)

    $Ui.Dice = @{ Faces = $dice; Total = $total; Timer = $null }
    return $Ui.Dice
}

function Set-RonDiceFaces {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [int]$Die1 = 0,
        [int]$Die2 = 0
    )
    $dice = $Ui.Dice
    if ($null -eq $dice) { return }
    if ($Die1 -le 0) {
        foreach ($f in $dice.Faces) { $f.Image.Opacity = 0.25 }
        $dice.Total.Text = ''
        return
    }
    $dice.Faces[0].Image.Source = Get-RonDieImage $Die1
    $dice.Faces[1].Image.Source = Get-RonDieImage $Die2
    foreach ($f in $dice.Faces) { $f.Image.Opacity = 1.0 }
    $label = "= $($Die1 + $Die2)"
    if ($Die1 -eq $Die2) { $label += '  DOUBLE' }
    $dice.Total.Text = $label
}

# Tumbles the dice for a moment and settles on the values the engine already
# produced. OnDone fires once, from a DispatcherTimer tick on the UI thread -
# no background thread is involved anywhere in this file.
function Start-RonDiceRoll {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][int]$Die1,
        [Parameter(Mandatory)][int]$Die2,
        [double]$Seconds = 0.7,
        [scriptblock]$OnDone = $null
    )
    $dice = $Ui.Dice
    if ($null -eq $dice) {
        if ($null -ne $OnDone) { Invoke-RonGuarded -Category 'ui' -Body $OnDone }
        return
    }

    # A roll already in flight is abandoned rather than queued: the newer roll
    # is always the one the player is waiting to see.
    if ($null -ne $dice.Timer) { $dice.Timer.Stop(); $dice.Timer = $null }

    foreach ($f in $dice.Faces) { $f.Image.Opacity = 1.0 }
    $dice.Total.Text = ''

    # The tick counter lives in a hashtable, not a plain variable. A closure
    # gives READ access to captured variables, but an assignment inside the
    # handler writes to that invocation's own local scope - so a "$count++"
    # would reset to 1 on every tick and the animation would never end.
    # Mutating a property of a captured object works, because nothing is
    # being rebound.
    $box = @{ Count = 0; Ticks = [int]([math]::Max(4, $Seconds / 0.06)) }
    $rng = New-Object System.Random

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(60)
    $timer.Add_Tick({
        $box.Count = $box.Count + 1
        if ($box.Count -ge $box.Ticks) {
            $timer.Stop()
            $dice.Timer = $null
            foreach ($f in $dice.Faces) { $f.Rotate.Angle = 0 }
            Set-RonDiceFaces -Ui $Ui -Die1 $Die1 -Die2 $Die2
            if ($null -ne $OnDone) { Invoke-RonGuarded -Category 'ui' -Body $OnDone }
            return
        }
        foreach ($f in $dice.Faces) {
            $f.Image.Source = Get-RonDieImage ($rng.Next(1, 7))
            $f.Rotate.Angle = $rng.Next(-22, 23)
        }
    }.GetNewClosure())

    $dice.Timer = $timer
    $timer.Start()
}

function Stop-RonDiceRoll {
    param([Parameter(Mandatory)][hashtable]$Ui)
    if ($null -ne $Ui.Dice -and $null -ne $Ui.Dice.Timer) {
        $Ui.Dice.Timer.Stop()
        $Ui.Dice.Timer = $null
    }
}
