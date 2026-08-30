#
# Ronopoly - the action queue and the effect pump.
#
# THE re-entrancy guard for the whole app. Three independent things want to
# make the game move - a human clicking, an AI timer ticking, and a network
# message arriving - and any of them can fire while an animation is still
# playing. All three ENQUEUE; a single pump drains one at a time behind an
# in-flight flag. Double-clicks, laggy network bursts and impatient players all
# become harmless as a result.
#
# Everything here runs on the UI thread. No PowerShell in this project ever
# runs on a background thread, which is what removes the entire class of
# "There is no Runspace available to run scripts in this thread" failures that
# Dispatcher.Invoke marshalling would otherwise produce.
#

function Initialize-RonAnimator {
    param([Parameter(Mandatory)][hashtable]$App)
    $App.ActionQueue    = New-Object System.Collections.Queue
    $App.ActionInFlight = $false
    $App.Effects        = $null
    $App.PendingMoves   = @{}
}

# The one way anything asks the game to change.
function Submit-RonUiAction {
    param([Parameter(Mandatory)][object]$Action)
    $App = (Get-RonApp)
    if ($null -eq $App -or $null -eq $App.State) { return }
    [void]$App.ActionQueue.Enqueue($Action)
    # Guarded because a button click and a timer tick both land here, and in
    # either case an unhandled exception would leave ActionInFlight stuck true
    # and the game permanently frozen with no indication why.
    Invoke-RonGuarded -Category 'ui' -Body { Step-RonActionPump } -OnError {
        param($err)
        $a = Get-RonApp
        if ($null -ne $a) { $a.ActionInFlight = $false }
    }
}

function Step-RonActionPump {
    $App = (Get-RonApp)
    if ($null -eq $App) { return }
    if ($App.ActionInFlight) { return }
    if ($App.ActionQueue.Count -eq 0) {
        Update-RonAllViews
        Start-RonAutoPlay
        return
    }

    $action = $App.ActionQueue.Dequeue()
    $App.ActionInFlight = $true

    $before = @{}
    foreach ($p in $App.State.Players) { $before[$p.Id] = $p.Position }

    $result = Invoke-RonSessionAction -Session $App.Session -Action $action
    if (-not $result.Ok) {
        # A rejection is normal traffic, not an error: a stale button or a
        # laggy client can produce one. Log it and carry on.
        Write-RonLog "Action '$($action.Kind)' rejected: $($result.Reason)" -Level Debug -Category ui
        $App.ActionInFlight = $false
        Update-RonAllViews
        Start-RonAutoPlay
        return
    }

    $App.State = $result.State
    Add-RonEventLog -Ui $App.Ui -State $App.State -Events $result.Events
    Start-RonEffectQueue -Events $result.Events -Before $before
}

# --- effects ---------------------------------------------------------------

function Start-RonEffectQueue {
    param(
        [Parameter(Mandatory)][object[]]$Events,
        [Parameter(Mandatory)][hashtable]$Before
    )
    $App = (Get-RonApp)
    $App.Effects = @{ Items = @($Events); Index = 0; Before = $Before }
    Step-RonEffectQueue
}

# Plays the event list. Non-visual events are applied in a tight loop; the few
# that need time on screen start an animation and return, and their completion
# callback re-enters here.
function Step-RonEffectQueue {
    $App = (Get-RonApp)
    if ($null -eq $App -or $null -eq $App.Effects) { return }
    $fx = $App.Effects

    while ($true) {
        if ($fx.Index -ge $fx.Items.Count) {
            $App.Effects = $null
            $App.ActionInFlight = $false
            Update-RonAllViews
            Start-RonAutoPlay
            return
        }

        $e = $fx.Items[$fx.Index]
        $fx.Index++

        # Sound plays even in fast mode: it is the only feedback left when the
        # animations are skipped.
        Invoke-RonEventSound -Event $e
        if ($App.FastMode) { continue }

        switch ($e.T) {
            'Rolled' {
                Start-RonDiceRoll -Ui $App.Ui -Die1 ([int]$e.D1) -Die2 ([int]$e.D2) `
                    -Seconds 0.55 -OnDone { Step-RonEffectQueue }
                return
            }
            'Moved' {
                $playerId = [int]$e.P
                $from = [int]$e.From
                $to = [int]$e.S
                if ($from -eq $to) { continue }
                Set-RonTileHighlight -Ui $App.Ui -Index $to
                Start-RonTokenMove -Ui $App.Ui -State $App.State -PlayerId $playerId -From $from -To $to `
                    -SecondsPerSpace 0.085 -OnDone { Step-RonEffectQueue }
                return
            }
            'CardDrawn' {
                Show-RonCardToast -Ui $App.Ui -Deck ([string]$e.Deck) -Text ([string]$e.Text) `
                    -Seconds 2.2 -OnDone { Step-RonEffectQueue }
                return
            }
            'JailEntered' {
                Update-RonTokenPositions -Ui $App.Ui -State $App.State
                Set-RonTileHighlight -Ui $App.Ui -Index 10
                continue
            }
        }
    }
}

# Abandons whatever is playing and snaps the board to the true state. Used when
# the player asks to skip, and on a network resync.
function Reset-RonEffects {
    $App = (Get-RonApp)
    if ($null -eq $App) { return }
    $App.Effects = $null
    Stop-RonDiceRoll -Ui $App.Ui
    Clear-RonToast -Ui $App.Ui
    if ($null -ne $App.State) { Update-RonTokenPositions -Ui $App.Ui -State $App.State }
    $App.ActionInFlight = $false
}

# --- the AI clock ----------------------------------------------------------
#
# An AI decision takes single-digit milliseconds. The delay exists purely so a
# human can follow what is happening, which is why it is a cosmetic timer on
# the UI thread rather than any kind of background work.

function Start-RonAutoPlay {
    $App = (Get-RonApp)
    if ($null -eq $App -or $null -eq $App.State) { return }
    if ($App.ActionInFlight) { return }
    if ($App.ActionQueue.Count -gt 0) { return }
    if ($App.State.IsOver) { return }
    if ($App.AiTimer.IsEnabled) { return }
    # The bots wait while a player is mid-decision in a modal panel. Composing
    # a trade against a board that is still moving is not a decision, it is a
    # race - and the offer would be validated against a position that no longer
    # exists by the time it is sent.
    if (Test-RonOverlayModal -Ui $App.Ui) { return }

    $acting = Get-RonActingPlayerId -State $App.State
    $player = $App.State.Players[$acting]
    if (-not $player.IsAiControlled()) { return }
    if (-not (Test-RonSessionControls -Session $App.Session -PlayerId $acting)) { return }

    $delay = 500
    if ($App.FastMode) { $delay = 20 }
    $App.AiTimer.Interval = [TimeSpan]::FromMilliseconds($delay)
    $App.AiTimer.Start()
}

function Invoke-RonAiTick {
    $App = (Get-RonApp)
    $App.AiTimer.Stop()
    if ($null -eq $App.State -or $App.State.IsOver) { return }
    if ($App.ActionInFlight -or $App.ActionQueue.Count -gt 0) { return }
    # A tick already in flight when a modal panel opened must not sneak a move
    # in behind it.
    if (Test-RonOverlayModal -Ui $App.Ui) { return }

    $acting = Get-RonActingPlayerId -State $App.State
    $player = $App.State.Players[$acting]
    if (-not $player.IsAiControlled()) { return }
    if (-not (Test-RonSessionControls -Session $App.Session -PlayerId $acting)) { return }

    $action = Get-RonAiAction -State $App.State -PlayerId $acting
    if ($null -eq $action) {
        Write-RonLog "AI produced no action for $($player.Name) in phase $($App.State.Turn.Phase)" -Level Warn -Category ai
        return
    }
    Submit-RonUiAction -Action $action
}

# Events the player should hear. Kept beside the animation pump so sound and
# picture are driven by the same list, in the same order.
function Invoke-RonEventSound {
    param([Parameter(Mandatory)][object]$Event)
    switch ($Event.T) {
        'Rolled'        { Invoke-RonSound 'dice' }
        'Bought'        { Invoke-RonSound 'cash' }
        'RentPaid'      { Invoke-RonSound 'cash' }
        'PassedGo'      { Invoke-RonSound 'cash' }
        'AuctionWon'    { Invoke-RonSound 'cash' }
        'CardDrawn'     { Invoke-RonSound 'card' }
        'BuildingBuilt' { Invoke-RonSound 'build' }
        'TradeExecuted' { Invoke-RonSound 'trade' }
        'JailEntered'   { Invoke-RonSound 'jail' }
        'Bankrupt'      { Invoke-RonSound 'bankrupt' }
        'GameOver'      { Invoke-RonSound 'win' }
    }
}
