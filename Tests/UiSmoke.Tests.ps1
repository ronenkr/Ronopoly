. (Join-Path (Split-Path -Parent $PSCommandPath) '_Harness.ps1')

# The UI test the project was missing.
#
# "Does it launch?" is not a test: an exception inside a DispatcherTimer tick is
# swallowed, so the game silently stops moving and the process still exits 0.
# That is exactly how an Int32 overflow in the AI's per-seat seed reached a real
# player. These tests open the real window, run a real dispatcher loop with real
# timers, and then assert on what actually HAPPENED - turns played, and no
# errors logged.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'src\Bootstrap.ps1') -Scope App

function Invoke-TestUiRun {
    param([int]$Seconds = 8, [int]$Seed = 0, [switch]$Fast)
    Initialize-RonLog -Level Warn
    Reset-RonErrors
    $seats = @(
        (New-RonSeat -Name 'Ada'   -Kind 'AI' -AiProfile 'Hard'   -Token 'hat'),
        (New-RonSeat -Name 'Blake' -Kind 'AI' -AiProfile 'Expert' -Token 'car'),
        (New-RonSeat -Name 'Cleo'  -Kind 'AI' -AiProfile 'Normal' -Token 'ship')
    )
    Start-RonApp -Seats $seats -Seed $Seed -Theme Dark -Mute -FastMode:$Fast -AutoCloseSeconds $Seconds
    return @{
        State  = (Get-RonLastGame)
        Errors = (Get-RonErrorCount)
        Last   = (Get-RonLastError)
    }
}

# Finds a button by its caption anywhere under an element. Overlays are built
# programmatically, so there is no x:Name to look one up by - and a test that
# reaches for the button a person would click is testing the thing a person
# actually does.
function Find-TestButton {
    param([System.Windows.DependencyObject]$Root, [string]$Caption)
    if ($null -eq $Root) { return $null }
    if ($Root -is [System.Windows.Controls.Button] -and [string]$Root.Content -eq $Caption) { return $Root }
    $n = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Root)
    for ($i = 0; $i -lt $n; $i++) {
        $hit = Find-TestButton -Root ([System.Windows.Media.VisualTreeHelper]::GetChild($Root, $i)) -Caption $Caption
        if ($null -ne $hit) { return $hit }
    }
    return $null
}

# The same walk, by type rather than by caption - for the controls a panel has
# only one of.
function Find-TestElement {
    param([System.Windows.DependencyObject]$Root, [Type]$Type, [string]$Contains = '')
    if ($null -eq $Root) { return $null }
    if ($Type.IsInstanceOfType($Root)) {
        if (-not $Contains) { return $Root }
        if ([string]$Root.Text -like "*$Contains*") { return $Root }
    }
    $n = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Root)
    for ($i = 0; $i -lt $n; $i++) {
        $hit = Find-TestElement -Root ([System.Windows.Media.VisualTreeHelper]::GetChild($Root, $i)) -Type $Type -Contains $Contains
        if ($null -ne $hit) { return $hit }
    }
    return $null
}

function Invoke-TestClick {
    param([System.Windows.Controls.Button]$Button)
    $Button.RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
}

Describe 'Player colours' {

    It 'picks readable ink for every token colour' {
        # The trade panels put a player's name on their own token colour, so
        # every one of those colours has to end up with legible text on it.
        # Contrast ratio per WCAG, which is a real threshold rather than a
        # guess: 4.5:1 is the readable-body-text line.
        $luminance = {
            param([string]$hex)
            $h = $hex.TrimStart('#')
            $parts = @(0, 2, 4) | ForEach-Object {
                $c = [Convert]::ToInt32($h.Substring($_, 2), 16) / 255.0
                if ($c -le 0.03928) { $c / 12.92 } else { [math]::Pow((($c + 0.055) / 1.055), 2.4) }
            }
            return (0.2126 * $parts[0] + 0.7152 * $parts[1] + 0.0722 * $parts[2])
        }

        $tokens = Get-RonTokens
        foreach ($id in $tokens.Order) {
            $colour = [string]$tokens.Tokens[$id].Colour
            $ink = Get-RonContrastInk $colour
            $a = & $luminance $colour
            $b = & $luminance $ink
            $hi = [math]::Max($a, $b)
            $lo = [math]::Min($a, $b)
            $ratio = ($hi + 0.05) / ($lo + 0.05)
            Assert-True ($ratio -ge 4.5) ("$id ($colour) got ink $ink at only {0:N1}:1" -f $ratio)
        }
    }
}

Describe 'UI smoke' {

    It 'plays real turns in a real window with no logged errors' {
        $run = Invoke-TestUiRun -Seconds 10 -Seed 4242
        Assert-NotNull $run.State 'the game state survived the window closing'
        Assert-Equal 0 $run.Errors "an error was logged: $($run.Last)"
        # The point of the test: it must have MOVED, not merely opened.
        Assert-True ($run.State.Turn.TurnNumber -gt 1) "only reached turn $($run.State.Turn.TurnNumber)"
        Assert-True ($run.State.Version -gt 3) "only applied $($run.State.Version) actions"
        Assert-RonInvariant -State $run.State
    }

    It 'plays real turns from a seed the game chose itself' {
        # Seed 0 means New-RonGame picks one, anywhere up to 2^31 - the path a
        # real launch takes, and the one every earlier test skipped.
        $run = Invoke-TestUiRun -Seconds 10 -Seed 0 -Fast
        Assert-Equal 0 $run.Errors "an error was logged: $($run.Last)"
        Assert-True ($run.State.Seed -gt 0) 'a seed was chosen'
        Assert-True ($run.State.Turn.TurnNumber -gt 1) "seed $($run.State.Seed) only reached turn $($run.State.Turn.TurnNumber)"
        Assert-RonInvariant -State $run.State
    }

    It 'counters an offer through the panel a player would click' {
        Initialize-RonLog -Level Warn
        Reset-RonErrors
        $probe = @{}
        $seats = @(
            (New-RonSeat -Name 'You' -Kind 'Human' -Token 'hat'),
            (New-RonSeat -Name 'Ada' -Kind 'AI' -AiProfile 'Normal' -Token 'car')
        )
        Start-RonApp -Seats $seats -Seed 31337 -Theme Dark -Mute -FastMode -AutoCloseSeconds 20 -OnReady {
            $App = (Get-RonApp)
            # Put an offer on the table from the bot. Reaching into the state
            # directly is the point: this test is about the PANEL, and the
            # engine's own path through it is already covered headlessly.
            $App.State.Properties[1].OwnerId = 0
            $App.State.Properties[3].OwnerId = 1
            $offer = [TradeOffer]::new()
            $offer.FromId = 1
            $offer.ToId = 0
            $offer.GiveProperties = @(3)
            $offer.GetProperties = @(1)
            Start-RonTradeOffer -State $App.State -Offer $offer
            Update-RonAllViews
            $App.Window.UpdateLayout()
            $probe.ResponseShown = (Test-RonOverlayOpen -Ui $App.Ui)

            $counter = Find-TestButton -Root $App.Ui.OverlayHost -Caption 'Counter-offer'
            $probe.FoundCounter = ($null -ne $counter)
            if ($null -ne $counter) { Invoke-TestClick -Button $counter }
            $App.Window.UpdateLayout()
            $probe.BuilderIsModal = (Test-RonOverlayModal -Ui $App.Ui)

            $send = Find-TestButton -Root $App.Ui.OverlayHost -Caption 'Send counter-offer'
            $probe.FoundSend = ($null -ne $send)
            # Seeded straight from their offer, so it is legal and sendable
            # without touching a single control.
            if ($null -ne $send) { $probe.SendEnabled = $send.IsEnabled; Invoke-TestClick -Button $send }
            $App.Window.UpdateLayout()

            $now = (Get-RonApp).State
            $probe.PendingFrom = $now.Turn.Trade.FromId
            $probe.PendingTo = $now.Turn.Trade.ToId
            $probe.Chain = $now.Turn.TradesProposed
            $probe.NoLongerModal = (-not (Test-RonOverlayModal -Ui (Get-RonApp).Ui))

            (Get-RonApp).ConfirmedClose = $true
            (Get-RonApp).Window.Close()
        }.GetNewClosure()

        Assert-Equal 0 (Get-RonErrorCount) "an error was logged: $(Get-RonLastError)"
        Assert-True $probe.ResponseShown  'the offer never appeared'
        Assert-True $probe.FoundCounter   'the offer could not be countered'
        Assert-True $probe.BuilderIsModal 'the counter panel did not hold the game'
        Assert-True $probe.FoundSend      'the counter panel had no send button'
        Assert-True $probe.SendEnabled    'the seeded counter was judged illegal'
        # The offer on the table is now the player's version of it, aimed back
        # at the bot, and the negotiation is two exchanges deep.
        Assert-Equal 0 $probe.PendingFrom
        Assert-Equal 1 $probe.PendingTo
        Assert-Equal 2 $probe.Chain
        Assert-True $probe.NoLongerModal 'the panel stayed modal after sending'
    }

    It 'opens a running game to the network from the status strip' {
        # The status strip is the ONLY way in to network play from inside the
        # game, so this drives it exactly as a player does: press the strip,
        # tick loopback, press the button. Loopback keeps the firewall out of
        # it - a Defender prompt in a test would hang the run.
        Initialize-RonLog -Level Warn
        Reset-RonErrors
        $probe = @{}
        $seats = @(
            (New-RonSeat -Name 'You'   -Kind 'Human' -Token 'hat'),
            (New-RonSeat -Name 'Ada'   -Kind 'AI' -AiProfile 'Normal' -Token 'car'),
            (New-RonSeat -Name 'Blake' -Kind 'AI' -AiProfile 'Hard'   -Token 'ship')
        )
        Start-RonApp -Seats $seats -Seed 5150 -Theme Dark -Mute -FastMode -AutoCloseSeconds 25 -OnReady {
            $App = (Get-RonApp)
            $probe.StartedLocal = ($App.Session.Kind -eq 'Local')
            # The caption has to carry the invitation. "Local game" on its own
            # is a button nobody presses.
            $probe.Caption = [string]$App.Ui.BtnNet.Content

            Invoke-TestClick -Button $App.Ui.BtnNet
            $App.Window.UpdateLayout()
            $probe.PanelIsModal = (Test-RonOverlayModal -Ui $App.Ui)

            # Choosing the seats, which is the whole point of the panel and the
            # one thing a default selection would let a test skip. These chips
            # are rebuilt on every click, so each has to be found again.
            $blake = Find-TestButton -Root $App.Ui.OverlayHost -Caption 'Blake'
            $probe.FoundChip = ($null -ne $blake)
            if ($null -ne $blake) { Invoke-TestClick -Button $blake }
            $App.Window.UpdateLayout()
            $probe.BlakeOn = ((Find-TestButton -Root $App.Ui.OverlayHost -Caption 'Blake').Opacity -eq 1.0)
            # And off again: Ada was chosen by default, so this un-chooses her.
            $ada = Find-TestButton -Root $App.Ui.OverlayHost -Caption 'Ada'
            if ($null -ne $ada) { Invoke-TestClick -Button $ada }
            $App.Window.UpdateLayout()
            $probe.AdaOff = ((Find-TestButton -Root $App.Ui.OverlayHost -Caption 'Ada').Opacity -lt 1.0)

            $port = Find-TestElement -Root $App.Ui.OverlayHost -Type ([System.Windows.Controls.TextBox])
            $probe.FoundPort = ($null -ne $port)
            # A port of its own, so a stray listener on the default cannot make
            # this test fail for a reason that has nothing to do with it.
            if ($null -ne $port) { $port.Text = '27110' }

            $loop = Find-TestElement -Root $App.Ui.OverlayHost -Type ([System.Windows.Controls.CheckBox])
            $probe.FoundLoopback = ($null -ne $loop)
            if ($null -ne $loop) { $loop.IsChecked = $true }

            $open = Find-TestButton -Root $App.Ui.OverlayHost -Caption 'Open to the network'
            $probe.FoundOpen = ($null -ne $open)
            if ($null -ne $open) { Invoke-TestClick -Button $open }
            $App.Window.UpdateLayout()

            $now = (Get-RonApp)
            $probe.Kind = [string]$now.Session.Kind
            $probe.Address = [string]$now.Session.Address
            $probe.Port = [int]$now.Session.Port
            # Seat 1 was the bot; it is now the chair a joiner claims, with the
            # bot holding it so the table does not stop.
            # Blake was chosen and Ada was un-chosen, so it is seat 2 that went
            # and seat 1 that stayed - not whatever the panel happened to
            # suggest when it opened.
            $probe.SeatOpened = ($now.State.Players[2].Kind -eq 'Remote')
            $probe.AdaKept = ($now.State.Players[1].Kind -eq 'AI')
            $probe.BotHoldsIt = $now.State.Players[2].IsAiControlled()
            $probe.HostDrivesIt = (Test-RonSessionControls -Session $now.Session -PlayerId 2)
            $probe.Strip = [string]$now.Ui.BtnNet.Content
            # And the panel now shows what the other player actually needs.
            $cmd = Find-TestElement -Root $now.Ui.OverlayHost -Type ([System.Windows.Controls.TextBox]) -Contains '-Mode Join'
            $probe.ShowsCommand = ($null -ne $cmd)
            if ($null -ne $cmd) { $probe.Command = [string]$cmd.Text }

            # Stop hosting again, so the test leaves no socket behind and the
            # round trip is covered rather than only the way in.
            $stop = Find-TestButton -Root $now.Ui.OverlayHost -Caption 'Stop hosting'
            $probe.FoundStop = ($null -ne $stop)
            if ($null -ne $stop) { Invoke-TestClick -Button $stop }
            $probe.BackToLocal = ((Get-RonApp).Session.Kind -eq 'Local')
            $probe.SeatRestored = ((Get-RonApp).State.Players[2].Kind -eq 'AI')

            (Get-RonApp).ConfirmedClose = $true
            (Get-RonApp).Window.Close()
        }.GetNewClosure()

        Assert-Equal 0 (Get-RonErrorCount) "an error was logged: $(Get-RonLastError)"
        Assert-True $probe.StartedLocal   'the game did not start local'
        Assert-True ($probe.Caption -like '*Invite*') "the strip only said '$($probe.Caption)'"
        Assert-True $probe.PanelIsModal   'pressing the strip opened nothing'
        Assert-True $probe.FoundChip      'the panel had no seat to choose'
        Assert-True $probe.BlakeOn         'clicking a seat did not choose it'
        Assert-True $probe.AdaOff          'clicking a chosen seat did not un-choose it'
        Assert-True $probe.FoundPort      'the panel had no port box'
        Assert-True $probe.FoundLoopback  'the panel had no this-computer-only option'
        Assert-True $probe.FoundOpen      'the panel had no button to open the game'
        Assert-Equal 'Host' $probe.Kind   'the game never opened to the network'
        Assert-Equal '127.0.0.1' $probe.Address 'a loopback listener advertised a LAN address'
        Assert-Equal 27110 $probe.Port    'the port typed into the panel was ignored'
        Assert-True $probe.SeatOpened     'the seat that was clicked is not the one that opened'
        Assert-True $probe.AdaKept        'a seat that was un-chosen was handed over anyway'
        Assert-True $probe.BotHoldsIt     'the open seat would stop the game dead'
        Assert-True $probe.HostDrivesIt   'nobody was left able to move the open seat'
        Assert-True ($probe.Strip -like '*27110*') "the strip still said '$($probe.Strip)'"
        Assert-True $probe.ShowsCommand   'the panel never showed the joining command'
        Assert-True ($probe.Command -like '*127.0.0.1*') "the command read '$($probe.Command)'"
        Assert-True $probe.FoundStop      'a game with nobody connected could not stop hosting'
        Assert-True $probe.BackToLocal    'stopping hosting left the session hosted'
        Assert-True $probe.SeatRestored   'the bot never got its seat back'
    }

    It 'aims a trade at the player whose chip was clicked' {
        # The picker is built by a redraw closure that builds click handlers,
        # and a handler built that way captures only what its own invocation
        # made local. Get that wrong and the chips throw the instant they are
        # pressed while the panel still looks perfectly correct - which is how
        # this shipped broken. Pressing one is the only thing that proves it.
        Initialize-RonLog -Level Warn
        Reset-RonErrors
        $probe = @{}
        $seats = @(
            (New-RonSeat -Name 'You'   -Kind 'Human' -Token 'hat'),
            (New-RonSeat -Name 'Ada'   -Kind 'AI' -AiProfile 'Normal' -Token 'car'),
            (New-RonSeat -Name 'Blake' -Kind 'AI' -AiProfile 'Hard'   -Token 'ship')
        )
        Start-RonApp -Seats $seats -Seed 8080 -Theme Dark -Mute -FastMode -AutoCloseSeconds 20 -OnReady {
            $App = (Get-RonApp)
            $App.State.Properties[1].OwnerId = 0
            $App.State.Properties[13].OwnerId = 1
            $App.State.Properties[15].OwnerId = 2

            Show-RonTradeOverlay -FromId 0
            $App.Window.UpdateLayout()
            # Ada is offered first, so Blake is the one that has to be chosen.
            $chip = Find-TestButton -Root $App.Ui.OverlayHost -Caption 'Blake'
            $probe.FoundChip = ($null -ne $chip)
            if ($null -ne $chip) { Invoke-TestClick -Button $chip }
            $App.Window.UpdateLayout()

            $probe.BlakeChosen = ((Find-TestButton -Root $App.Ui.OverlayHost -Caption 'Blake').Opacity -eq 1.0)
            $probe.AdaDropped = ((Find-TestButton -Root $App.Ui.OverlayHost -Caption 'Ada').Opacity -lt 1.0)
            # The other side of the table is Blake's now, so his deed is what is
            # on offer - the panel really rebuilt rather than only re-shading.
            $probe.ShowsTheirDeed = ($null -ne (Find-TestButton -Root $App.Ui.OverlayHost -Caption 'Blake'))
            $probe.Column = ($null -ne (Find-TestElement -Root $App.Ui.OverlayHost -Type ([System.Windows.Controls.CheckBox])))

            (Get-RonApp).ConfirmedClose = $true
            (Get-RonApp).Window.Close()
        }.GetNewClosure()

        Assert-Equal 0 (Get-RonErrorCount) "an error was logged: $(Get-RonLastError)"
        Assert-True $probe.FoundChip   'the trade panel had no player to pick'
        Assert-True $probe.BlakeChosen 'clicking a player did not aim the trade at them'
        Assert-True $probe.AdaDropped  'the trade was still aimed at the first player as well'
        Assert-True $probe.Column      'the other side of the table did not redraw'
    }

    It 'asks before closing, and closes when told to' {
        Initialize-RonLog -Level Warn
        Reset-RonErrors
        $probe = @{}
        $seats = @(
            (New-RonSeat -Name 'Ada'   -Kind 'AI' -AiProfile 'Normal' -Token 'hat'),
            (New-RonSeat -Name 'Blake' -Kind 'AI' -AiProfile 'Normal' -Token 'car')
        )
        # AutoCloseSeconds is only the safety net here: if the quit button fails
        # to close the window the test must still end, and the assertions below
        # can tell the two endings apart.
        Start-RonApp -Seats $seats -Seed 77 -Theme Dark -Mute -FastMode -AutoCloseSeconds 20 -OnReady {
            $App = (Get-RonApp)
            # A plain close, exactly as the window's X does.
            $App.Window.Close()
            $probe.SurvivedTheClose = $App.Window.IsVisible
            $probe.PromptShown = (Test-RonOverlayOpen -Ui $App.Ui)
            $probe.PromptIsModal = (Test-RonOverlayModal -Ui $App.Ui)

            # The panel was built a moment ago; without a layout pass it has no
            # visual children yet and nothing can be found in it.
            $App.Window.UpdateLayout()
            $quit = Find-TestButton -Root $App.Ui.OverlayHost -Caption 'Quit'
            $probe.FoundQuit = ($null -ne $quit)
            if ($null -ne $quit) { Invoke-TestClick -Button $quit }
            # The click handler runs synchronously, so by here the window has
            # gone and the app state has been torn down.
            $probe.ClosedOnQuit = ($null -eq (Get-RonApp))
        }.GetNewClosure()

        Assert-Equal 0 (Get-RonErrorCount) "an error was logged: $(Get-RonLastError)"
        Assert-True $probe.SurvivedTheClose 'the window closed without asking'
        Assert-True $probe.PromptShown      'no prompt appeared when closing'
        Assert-True $probe.PromptIsModal    'the prompt did not stop the game underneath it'
        Assert-True $probe.FoundQuit        'the prompt had no Quit button'
        Assert-True $probe.ClosedOnQuit     'Quit did not close the window'
    }
}

exit (Complete-RonTests)
