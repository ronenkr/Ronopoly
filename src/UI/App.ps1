#
# Ronopoly - the application controller.
#
# The ONLY file in the project that holds ambient state, in the single
# $script:RonApp hashtable. Everything else - the whole engine, the AI, the
# rules - is pure functions over an explicit GameState, which is what makes
# them testable, replayable, and safe to run twice in one process.
#
# There is no game loop here either. The window opens, and from then on the
# game is driven entirely by events: a click, a DispatcherTimer tick asking the
# AI, or a network frame arriving. All three funnel into the same action queue.
#

$script:RonApp = $null

function Start-RonApp {
    param(
        [object[]]$Seats = $null,
        [hashtable]$Rules = $null,
        [int]$Seed = 0,
        [ValidateSet('Dark','Light')][string]$Theme = 'Dark',
        [ValidateSet('Solo','Host','Join')][string]$Mode = 'Solo',
        [string]$HostAddress = '127.0.0.1',
        [int]$Port = 0,
        [string]$PlayerName = 'Player',
        [switch]$LoopbackOnly,
        # How many seats to leave open for people joining over the network.
        # Without at least one, a hosted game answers every joiner with "this
        # game is full" - there is nowhere for them to sit.
        [int]$RemoteSeats = 0,
        [switch]$FastMode,
        [switch]$Mute,
        # Close the window automatically after N seconds. Used by the UI
        # integration test to drive a real dispatcher loop, real timers and a
        # real AI game without a person at the keyboard.
        [int]$AutoCloseSeconds = 0,
        # Run once on the UI thread just after the window opens. The only way a
        # test can reach INTO a live window - ShowDialog does not return until
        # it closes - so it is what lets the close prompt and the panels be
        # tested by clicking them rather than by reasoning about them.
        [scriptblock]$OnReady = $null
    )

    Initialize-RonAssets
    Initialize-RonAudio -Muted:$Mute
    if ($null -eq $Seats) { $Seats = New-RonDefaultSeats -Remote $RemoteSeats }
    if ($null -eq $Rules) { $Rules = Get-RonDefaultRules }

    $window = ConvertFrom-RonXaml (Get-RonMainWindowXaml)
    $ui = New-RonUiIndex -Window $window
    [void](Set-RonTheme -Window $window -Theme $Theme)

    $script:RonApp = @{
        Window   = $window
        Ui       = $ui
        State    = $null
        Session  = $null
        Seats    = $Seats
        Rules    = $Rules
        Theme    = $Theme
        FastMode = [bool]$FastMode
        AiTimer  = $null
        NetTimer = $null
        Mode     = $Mode
        # What a seat looked like before it was opened to the network, so it
        # can be handed back to the bot it was taken from.
        OpenedSeats = @{}
        # Set only by the quit panel. Window.Closing cancels every close that
        # does not carry it, which is what turns the X into a question.
        ConfirmedClose = $false
    }
    $ui.Window = $window
    Initialize-RonAnimator -App (Get-RonApp)

    # The AI clock and the network pump are both plain DispatcherTimers on the
    # UI thread. Nothing in this application marshals across threads.
    $aiTimer = New-Object System.Windows.Threading.DispatcherTimer
    # Guarded: an exception inside a DispatcherTimer tick is otherwise swallowed
    # and the game just stops moving, with the process still exiting cleanly.
    $aiTimer.Add_Tick({
        Invoke-RonGuarded -Category 'ai' -Body { Invoke-RonAiTick } -OnError {
            param($err)
            Show-RonMessageOverlay -Title 'Something went wrong' -Body @(
                'The game hit an error while the AI was taking its turn.',
                $err.Exception.Message,
                '',
                'The position is intact - you can save it and carry on, or start a new game.'
            )
        }
    })
    $script:RonApp.AiTimer = $aiTimer

    $netTimer = New-Object System.Windows.Threading.DispatcherTimer
    $netTimer.Interval = [TimeSpan]::FromMilliseconds(33)   # ~30 Hz
    $netTimer.Add_Tick({ Invoke-RonGuarded -Category 'net' -Body { Invoke-RonNetTick } })
    $script:RonApp.NetTimer = $netTimer

    Register-RonUiHandlers

    switch ($Mode) {
        'Host' { Start-RonHostedGame -Seats $Seats -Rules $Rules -Seed $Seed -Port $Port -LoopbackOnly:$LoopbackOnly }
        'Join' { Start-RonJoinedGame -HostAddress $HostAddress -Port $Port -PlayerName $PlayerName }
        default { Start-RonNewGame -Seats $Seats -Rules $Rules -Seed $Seed }
    }

    # Closing is the one click in the app that cannot be undone - an unsaved
    # position is simply gone. Cancel it and ask, using the same overlay layer
    # as everything else rather than a system message box, which would pump a
    # nested dispatcher loop underneath the turn state machine.
    $window.Add_Closing({
        param($sender, $e)
        $App = (Get-RonApp)
        if ($null -eq $App -or $App.ConfirmedClose) { return }
        $e.Cancel = $true
        Invoke-RonGuarded -Category 'ui' -Body { Show-RonQuitOverlay } -OnError {
            # If the prompt itself cannot be drawn, do not trap the player in a
            # window they are unable to close.
            $a = (Get-RonApp)
            if ($null -ne $a) { $a.ConfirmedClose = $true; $a.Window.Close() }
        }
    })

    # Stop every timer and drop every socket on close. A DispatcherTimer that
    # outlives its window keeps the whole visual tree alive.
    $window.Add_Closed({
        $App = (Get-RonApp)
        if ($null -eq $App) { return }
        if ($null -ne $App.AiTimer)  { $App.AiTimer.Stop() }
        if ($null -ne $App.NetTimer) { $App.NetTimer.Stop() }
        Stop-RonDiceRoll -Ui $App.Ui
        Clear-RonToast -Ui $App.Ui
        if ($null -ne $App.Session) { Close-RonSession -Session $App.Session }
        # Kept for post-mortem: the integration test and any crash report want
        # the final position after the window has gone.
        $script:RonLastGame = $App.State
        $script:RonApp = $null
    })

    $netTimer.Start()

    if ($null -ne $OnReady) {
        $ready = New-Object System.Windows.Threading.DispatcherTimer
        $ready.Interval = [TimeSpan]::FromMilliseconds(120)
        $ready.Add_Tick({
            $ready.Stop()
            Invoke-RonGuarded -Category 'ui' -Body $OnReady
        }.GetNewClosure())
        $ready.Start()
    }

    if ($AutoCloseSeconds -gt 0) {
        $closer = New-Object System.Windows.Threading.DispatcherTimer
        $closer.Interval = [TimeSpan]::FromSeconds($AutoCloseSeconds)
        $closer.Add_Tick({
            $closer.Stop()
            # The test driver is the player here, and it has already decided.
            $App = (Get-RonApp)
            $App.ConfirmedClose = $true
            $App.Window.Close()
        }.GetNewClosure())
        $closer.Start()
    }

    [void]$window.ShowDialog()
}

# One lookup of every named element, so no view code calls FindName at runtime.
function New-RonUiIndex {
    param([Parameter(Mandatory)][System.Windows.Window]$Window)
    $names = @(
        'RootGrid','BoardRoot','BoardGrid','OrnamentCanvas','TokenCanvas',
        'TurnText','PhaseText','PromptText','BankText','BtnNet',
        'DiceHost','ActionPanel','PlayerList','LogList','LogScroll',
        'OverlayLayer','OverlayScrim','OverlayHost','ToastLayer','ToastHost',
        'BtnSave','BtnRules','BtnSound','BtnTheme','BtnNewGame'
    )
    $ui = @{ Window = $Window }
    foreach ($n in $names) { $ui[$n] = $Window.FindName($n) }
    $ui.HighlightIndex = -1
    $ui.Modal = $false
    $ui.NetPanelOpen = $false
    return $ui
}

function Register-RonUiHandlers {
    $ui = (Get-RonApp).Ui

    $ui.BtnTheme.Add_Click({
        $App = (Get-RonApp)
        if ($App.Theme -eq 'Dark') { $App.Theme = 'Light' } else { $App.Theme = 'Dark' }
        [void](Set-RonTheme -Window $App.Window -Theme $App.Theme)
        Update-RonAllViews
    })

    $ui.BtnNewGame.Add_Click({ Show-RonNewGameOverlay })
    $ui.BtnNet.Add_Click({ Show-RonNetworkOverlay })
    $ui.BtnRules.Add_Click({ Show-RonRulesOverlay })
    $ui.BtnSave.Add_Click({ Show-RonSaveOverlay })

    $ui.BtnSound.Add_Click({
        [void](Step-RonAudioLevel)
        (Get-RonApp).Ui.BtnSound.Content = Get-RonAudioLabel
    })
    $ui.BtnSound.Content = Get-RonAudioLabel

    # Click a space to read its title deed.
    $ui.BoardGrid.Add_MouseLeftButtonUp({
        param($sender, $e)
        $App = (Get-RonApp)
        if ($null -eq $App -or $null -eq $App.State) { return }
        if (Test-RonOverlayOpen -Ui $App.Ui) { return }
        $index = Find-RonClickedSpace -Position $e.GetPosition($App.Ui.BoardGrid)
        if ($index -ge 0 -and (Test-RonIsDeed $index)) {
            Show-RonDeedOverlay -Ui $App.Ui -State $App.State -SpaceIndex $index
        }
    })

    # Escape closes whatever is open; space rolls or ends the turn.
    $script:RonApp.Window.Add_KeyDown({
        param($sender, $e)
        $App = (Get-RonApp)
        if ($null -eq $App) { return }
        if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
            if (Test-RonOverlayOpen -Ui $App.Ui) { Hide-RonOverlay -Ui $App.Ui }
            return
        }
        if ($e.Key -eq [System.Windows.Input.Key]::Space -and -not (Test-RonOverlayOpen -Ui $App.Ui)) {
            Invoke-RonDefaultAction
            $e.Handled = $true
        }
    })
}

# Maps a click on the board grid back to a space index, using the same exact
# geometry the tiles were laid out with.
function Find-RonClickedSpace {
    param([Parameter(Mandatory)][System.Windows.Point]$Position)
    for ($i = 0; $i -le 39; $i++) {
        $g = Get-RonCellGeometry $i
        if ($Position.X -ge $g.X -and $Position.X -lt ($g.X + $g.W) -and
            $Position.Y -ge $g.Y -and $Position.Y -lt ($g.Y + $g.H)) { return $i }
    }
    return -1
}

# Space bar: whatever the obvious next move is.
function Invoke-RonDefaultAction {
    $App = (Get-RonApp)
    if ($null -eq $App -or $null -eq $App.State -or $App.State.IsOver) { return }
    if ($App.ActionInFlight) { return }
    $acting = Get-RonActingPlayerId -State $App.State
    if ($App.State.Players[$acting].IsAiControlled()) { return }
    if (-not (Test-RonSessionControls -Session $App.Session -PlayerId $acting)) { return }

    # The first action that can actually be taken. The panel can now carry a
    # deliberately dead button - a Buy you cannot yet afford - and the space
    # bar must skip it rather than submit nothing.
    foreach ($p in @(Get-RonPrimaryActions -State $App.State)) {
        if ($null -eq $p.Action) { continue }
        if ($p.ContainsKey('Enabled') -and -not $p.Enabled) { continue }
        Submit-RonUiAction -Action $p.Action
        return
    }
}

# --- starting a game -------------------------------------------------------

function Start-RonNewGame {
    param([object[]]$Seats, [hashtable]$Rules, [int]$Seed = 0)
    $App = (Get-RonApp)
    if ($null -ne $App.Session) { Close-RonSession -Session $App.Session }

    $state = New-RonGameFromSeats -Seats $Seats -Rules $Rules -Seed $Seed
    $App.Seats = $Seats
    $App.Rules = $Rules
    $App.State = $state
    $App.Session = New-RonLocalSession -State $state
    $App.OpenedSeats = @{}
    Set-RonNetStatus

    Reset-RonGameView
    Add-RonLogLine -Ui $App.Ui -Text ("New game - " + (@($Seats | ForEach-Object { $_.Name }) -join ', '))
    Start-RonAutoPlay
}

function Start-RonHostedGame {
    param([object[]]$Seats, [hashtable]$Rules, [int]$Seed = 0, [int]$Port = 0, [switch]$LoopbackOnly)
    $App = (Get-RonApp)
    $state = New-RonGameFromSeats -Seats $Seats -Rules $Rules -Seed $Seed
    $session = New-RonHostSession -State $state -LocalIds (Get-RonLocalSeatIds -Seats $Seats) -Port $Port -LoopbackOnly:$LoopbackOnly

    if ($session.Kind -eq 'Failed') {
        # Nearly always the firewall or a port already in use - both worth
        # saying plainly rather than showing a stack trace.
        Show-RonMessageOverlay -Title 'Could not host' -Body @(
            "The game could not listen for other players.",
            $session.Error,
            "",
            "If Windows Defender asked about powershell.exe, allow it and try again.",
            "Tools\Add-FirewallRule.ps1 can add the rule permanently (run as administrator)."
        )
        Start-RonNewGame -Seats $Seats -Rules $Rules -Seed $Seed
        return
    }

    $App.Seats = $Seats
    $App.Rules = $Rules
    $App.State = $state
    $App.Session = $session
    Set-RonNetStatus

    Reset-RonGameView
    Add-RonLogLine -Ui $App.Ui -Text (Get-RonHostSummary -Session $session) -Colour '#2FBF71'
    Start-RonAutoPlay
}

function Start-RonJoinedGame {
    param([string]$HostAddress, [int]$Port = 0, [string]$PlayerName = 'Player')
    $App = (Get-RonApp)
    $session = New-RonClientSession -HostAddress $HostAddress -Port $Port -Name $PlayerName

    if ($session.Kind -eq 'Failed') {
        Show-RonMessageOverlay -Title 'Could not join' -Body @(
            "No game answered at ${HostAddress}:$(if ($Port -gt 0) { $Port } else { Get-RonDefaultPort }).",
            $session.Error,
            "",
            "Check the address the host read out, and that they have allowed powershell.exe through their firewall."
        )
        return
    }
    $App.Session = $session
    Set-RonNetStatus -Text "Joining ${HostAddress}..."
    Add-RonLogLine -Ui $App.Ui -Text "Connecting to $HostAddress..."
}

# Rebuilds the board, tokens, dice and HUD for a brand new state. The only
# place in the app that rebuilds visuals; everything else updates in place.
function Reset-RonGameView {
    $App = (Get-RonApp)
    if ($null -eq $App.State) { return }
    Reset-RonEffects
    # A modal panel here is a message the player has not answered yet - most
    # often "could not host", which is followed immediately by starting a local
    # game. Wiping it off the screen would take the explanation with it.
    if (-not (Test-RonOverlayModal -Ui $App.Ui)) { Hide-RonOverlay -Ui $App.Ui }
    $App.Ui.LogList.Items.Clear()
    [void](Initialize-RonBoardView -Ui $App.Ui)
    [void](Initialize-RonTokenView -Ui $App.Ui -State $App.State)
    [void](Initialize-RonDiceView -Ui $App.Ui)
    [void](Initialize-RonHudView -Ui $App.Ui -State $App.State)
    Update-RonAllViews
}

# --- the network, from inside a running game --------------------------------
#
# A game does not have to be started with -Mode Host. These are what the status
# strip's button drives: a local game becomes a hosted one over the same
# GameState, mid-turn, with nothing restarted and nobody's position lost.

# The status strip's caption. Derived from the session rather than remembered,
# so it cannot drift out of step with what is actually happening.
function Set-RonNetStatus {
    param([string]$Text = '')
    $App = (Get-RonApp)
    if ($null -eq $App -or $null -eq $App.Ui.BtnNet) { return }

    $kind = 'Local'
    if ($null -ne $App.Session) { $kind = [string]$App.Session.Kind }

    if (-not $Text) {
        if ($kind -eq 'Host') { $Text = Get-RonHostSummary -Session $App.Session }
        else                  { $Text = 'Local game' }
    }
    $tip = 'Who else is in this game.'
    if ($kind -eq 'Local') {
        # The affordance has to be in the caption. A button that says only
        # "Local game" is a button nobody presses, and the whole network layer
        # stays undiscovered behind it.
        $Text += '   -   Invite'
        $tip = 'Open this game to other people on your network.'
    }
    $App.Ui.BtnNet.Content = $Text
    $App.Ui.BtnNet.ToolTip = $tip
}

# Opens the running game to the network, handing the chosen seats to whoever
# joins. Returns @{ Ok; Reason }.
function Open-RonAppToNetwork {
    param([int[]]$SeatIds = @(), [int]$Port = 0, [switch]$LoopbackOnly)
    $App = (Get-RonApp)
    if ($null -eq $App -or $null -eq $App.State) { return @{ Ok = $false; Reason = 'No game is running.' } }
    if ($null -eq $App.Session -or $App.Session.Kind -ne 'Local') {
        return @{ Ok = $false; Reason = 'This game is already on the network.' }
    }

    $taken = New-Object System.Collections.ArrayList
    foreach ($id in @($SeatIds)) { [void]$taken.Add((Open-RonRemoteSeat -State $App.State -PlayerId $id)) }

    $session = Open-RonSessionToNetwork -Session $App.Session -Port $Port -LoopbackOnly:$LoopbackOnly
    if ($session.Kind -eq 'Failed') {
        # Hosting failed, so the game has to be exactly the game it was - not
        # one with holes in it where the bots used to be.
        foreach ($snap in $taken) { [void](Restore-RonSeat -State $App.State -Snapshot $snap) }
        return @{ Ok = $false; Reason = [string]$session.Error }
    }

    foreach ($snap in $taken) { $App.OpenedSeats[[int]$snap.Id] = $snap }
    $App.Session = $session
    $App.Mode = 'Host'
    Set-RonNetStatus
    Add-RonLogLine -Ui $App.Ui -Text (Get-RonHostSummary -Session $session) -Colour '#2FBF71'
    Update-RonAllViews
    return @{ Ok = $true; Reason = '' }
}

# Opens one more seat on a game that is already hosted.
function Open-RonAppSeat {
    param([Parameter(Mandatory)][int]$PlayerId)
    $App = (Get-RonApp)
    if ($null -eq $App -or $null -eq $App.Session -or $App.Session.Kind -ne 'Host') {
        return @{ Ok = $false; Reason = 'This game is not open to the network.' }
    }
    $App.OpenedSeats[$PlayerId] = (Open-RonRemoteSeat -State $App.State -PlayerId $PlayerId)
    $App.Session.LocalIds = Get-RonHostLocalIds -State $App.State
    Set-RonNetStatus
    Update-RonAllViews
    Start-RonAutoPlay
    return @{ Ok = $true; Reason = '' }
}

# Takes a still-unclaimed seat back off the table. Only ever offered for a seat
# nobody has joined on - dropping a player who is sitting there would be a very
# different button, and it is not this one.
function Close-RonAppSeat {
    param([Parameter(Mandatory)][int]$PlayerId)
    $App = (Get-RonApp)
    if ($null -eq $App -or $null -eq $App.State) { return @{ Ok = $false; Reason = 'No game is running.' } }
    $player = $App.State.Players[$PlayerId]
    if ($player.ConnectionState -eq 'Connected') {
        return @{ Ok = $false; Reason = "$($player.Name) is playing from another computer." }
    }
    if (-not $App.OpenedSeats.ContainsKey($PlayerId)) {
        return @{ Ok = $false; Reason = 'That seat was open before this game started.' }
    }
    [void](Restore-RonSeat -State $App.State -Snapshot $App.OpenedSeats[$PlayerId])
    $App.OpenedSeats.Remove($PlayerId)
    if ($App.Session.Kind -eq 'Host') { $App.Session.LocalIds = Get-RonHostLocalIds -State $App.State }
    Set-RonNetStatus
    Update-RonAllViews
    Start-RonAutoPlay
    return @{ Ok = $true; Reason = '' }
}

# Stops listening and goes back to a game on this machine alone, putting every
# seat that was opened back the way it was found.
function Close-RonAppNetwork {
    $App = (Get-RonApp)
    if ($null -eq $App -or $null -eq $App.Session -or $App.Session.Kind -ne 'Host') {
        return @{ Ok = $false; Reason = 'This game is not open to the network.' }
    }
    foreach ($p in $App.State.Players) {
        if ($p.Kind -eq 'Remote' -and $p.ConnectionState -eq 'Connected') {
            return @{ Ok = $false; Reason = "$($p.Name) is still playing from another computer." }
        }
    }
    foreach ($id in @($App.OpenedSeats.Keys)) { [void](Restore-RonSeat -State $App.State -Snapshot $App.OpenedSeats[$id]) }
    $App.OpenedSeats = @{}
    $App.Session = Close-RonSessionNetwork -Session $App.Session
    $App.Mode = 'Solo'
    Set-RonNetStatus
    Add-RonLogLine -Ui $App.Ui -Text 'Closed the game to the network.'
    Update-RonAllViews
    Start-RonAutoPlay
    return @{ Ok = $true; Reason = '' }
}

# --- the per-frame refresh -------------------------------------------------

function Update-RonAllViews {
    $App = (Get-RonApp)
    if ($null -eq $App -or $null -eq $App.State) { return }
    $state = $App.State

    Update-RonBoardView -Ui $App.Ui -State $state
    Update-RonHudView   -Ui $App.Ui -State $state
    if ($null -eq $App.Effects) {
        Update-RonTokenPositions -Ui $App.Ui -State $state
        # Show the roll that actually stands. Without this the dice stay blank
        # whenever the animation was skipped - in fast mode, after a resync, or
        # for a remote player who never saw it tumble.
        $roll = @($state.Turn.LastRoll)
        if ($roll.Count -eq 2) { Set-RonDiceFaces -Ui $App.Ui -Die1 $roll[0] -Die2 $roll[1] }
        else                   { Set-RonDiceFaces -Ui $App.Ui }
    }

    $acting = Get-RonActingPlayerId -State $state
    $mine = (Test-RonSessionControls -Session $App.Session -PlayerId $acting)
    Update-RonActionPanel -Ui $App.Ui -State $state -Enabled ($mine -and -not $App.ActionInFlight) -OnAction {
        param($action)
        Submit-RonUiAction -Action $action
    }

    Sync-RonOverlay
}

# Overlays follow the phase rather than being pushed by whoever caused it, so
# a remote player sees exactly the same panel at exactly the same moment.
function Sync-RonOverlay {
    $App = (Get-RonApp)
    $state = $App.State
    $phase = $state.Turn.Phase

    # A panel the player is working in - composing a trade, answering the quit
    # prompt - is never replaced by the phase. Nothing else in the app can move
    # while one is open either: see Start-RonAutoPlay.
    if (Test-RonOverlayModal -Ui $App.Ui) { return }

    if ($state.IsOver) {
        if (-not (Test-RonOverlayOpen -Ui $App.Ui)) {
            Show-RonGameOverOverlay -Ui $App.Ui -State $state -OnNewGame {
                Hide-RonOverlay -Ui (Get-RonApp).Ui
                Show-RonNewGameOverlay
            }
        }
        return
    }

    # Do not fight an animation that is still playing.
    if ($null -ne $App.Effects) { return }

    if ($phase -eq 'AwaitAuction') {
        $App.Ui.OverlayIsPhaseDriven = $true
        Show-RonAuctionOverlay -Ui $App.Ui -State $state -OnAction {
            param($action)
            Hide-RonOverlay -Ui (Get-RonApp).Ui
            Submit-RonUiAction -Action $action
        }
        return
    }

    if ($phase -eq 'AwaitTradeResponse') {
        $responder = $state.Turn.Trade.ToId
        if (-not $state.Players[$responder].IsAiControlled() -and
            (Test-RonSessionControls -Session $App.Session -PlayerId $responder)) {
            $App.Ui.OverlayIsPhaseDriven = $true
            Show-RonTradeResponseOverlay
            return
        }
    }

    # An overlay the player opened themselves (a title deed, say) is left
    # alone; a phase-driven one closes as soon as its phase ends.
    if ($App.Ui.OverlayIsPhaseDriven) {
        Hide-RonOverlay -Ui $App.Ui
        $App.Ui.OverlayIsPhaseDriven = $false
    }
}

# --- the network pump ------------------------------------------------------

function Invoke-RonNetTick {
    $App = (Get-RonApp)
    if ($null -eq $App -or $null -eq $App.Session) { return }
    if ($App.Session.Kind -eq 'Local') { return }

    foreach ($notice in (Step-RonSession -Session $App.Session)) {
        switch ($notice.Kind) {
            'Welcome' {
                Set-RonNetStatus -Text "Connected as seat $($notice.PlayerId)"
            }
            'Resync' {
                $App.State = $notice.State
                Reset-RonGameView
            }
            'Batch' {
                $App.State = $notice.State
                Add-RonEventLog -Ui $App.Ui -State $App.State -Events $notice.Events
                Update-RonAllViews
            }
            'Applied' {
                Add-RonEventLog -Ui $App.Ui -State $App.State -Events $notice.Events
                Update-RonAllViews
            }
            'Joined' {
                Add-RonLogLine -Ui $App.Ui -Text "$($notice.Name) joined." -Colour '#2FBF71'
                Set-RonNetStatus
                Update-RonAllViews
                Sync-RonNetworkOverlay
            }
            'Disconnected' {
                Add-RonLogLine -Ui $App.Ui -Text (Get-RonString 'Ui.AiTakeover' $notice.Name) -Colour '#F0553C'
                # The seat is handed to the AI so the game continues rather than
                # stalling; reconnecting within the game reclaims it.
                Set-RonAiTakeover -Session $App.Session -PlayerId $notice.PlayerId
                Set-RonNetStatus
                Update-RonAllViews
                Sync-RonNetworkOverlay
                Start-RonAutoPlay
            }
            'HostLost' {
                Set-RonNetStatus -Text 'Host lost'
                Show-RonMessageOverlay -Title 'Connection lost' -Body @('The host is no longer reachable.', $notice.Reason)
            }
            'Rejected' {
                Add-RonLogLine -Ui $App.Ui -Text "Rejected: $($notice.Reason)" -Colour '#F0553C'
            }
        }
    }
}

# GetNewClosure() puts a scriptblock in its OWN dynamic module, so a
# $script:RonApp reference inside a closure resolves against that empty module
# rather than this file's scope and silently reads $null. Every closure in the
# UI therefore reaches the app through this function instead: a function call
# resolves normally from anywhere.
function Get-RonApp { return $script:RonApp }

# The state as it stood when the window closed. Null until then.
function Get-RonLastGame { return $script:RonLastGame }

# Swaps a loaded position in and rebuilds every view around it.
function Resume-RonSavedGame {
    param([Parameter(Mandatory)][GameState]$State)
    $App = Get-RonApp
    if ($null -ne $App.Session) { Close-RonSession -Session $App.Session }
    $App.State = $State
    $App.Rules = $State.Rules
    $App.Session = New-RonLocalSession -State $State
    $App.OpenedSeats = @{}
    Set-RonNetStatus
    Reset-RonGameView
    Add-RonLogLine -Ui $App.Ui -Text "Loaded a saved game at turn $($State.Turn.TurnNumber)." -Colour '#2FBF71'
    Start-RonAutoPlay
}
