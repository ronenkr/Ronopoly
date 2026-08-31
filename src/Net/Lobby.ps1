#
# Ronopoly - the lobby: who is playing, and how.
#
# A seat list is all a game needs to start. The same list produces a solo game
# against bots, a hot-seat game round one screen, or a LAN game - the only
# difference is which Kind each seat has and which session wraps the result.
#

function New-RonSeat {
    param(
        [Parameter(Mandatory)][string]$Name,
        [ValidateSet('Human','AI','Remote')][string]$Kind = 'Human',
        [string]$AiProfile = 'Normal',
        [string]$Token = ''
    )
    return @{ Name = $Name; Kind = $Kind; AiProfile = $AiProfile; Token = $Token }
}

# A sensible starting line-up: one human plus three bots of mixed strength.
#
# Remote is the seat NOBODY here plays - it is the empty chair a joiner claims,
# and a game with none of them cannot be joined at all, however well the
# networking works. They come out of the bots' places rather than adding to the
# table, so hosting seats the same size of game as playing alone does.
function New-RonDefaultSeats {
    param([int]$Humans = 1, [int]$Bots = 3, [int]$Remote = 0)
    if ($Remote -gt 0) { $Bots = [math]::Max(0, $Bots - $Remote) }
    $tokens = (Get-RonTokens).Order
    $names  = @('You','Ada','Blake','Cleo','Dax','Esme','Fox','Gwen')
    $seats  = New-Object System.Collections.ArrayList
    $profiles = @('Normal','Hard','Expert','Easy','Normal','Hard','Expert','Easy')
    $slot = 0

    for ($i = 0; $i -lt $Humans; $i++) {
        [void]$seats.Add((New-RonSeat -Name $names[$slot] -Kind 'Human' -Token $tokens[$slot]))
        $slot++
    }
    # Named for what they are until somebody joins: the host reads the real
    # name off the joiner's Hello and overwrites it.
    for ($i = 0; $i -lt $Remote; $i++) {
        [void]$seats.Add((New-RonSeat -Name ("Open seat " + ($i + 1)) -Kind 'Remote' -Token $tokens[$slot]))
        $slot++
    }
    for ($i = 0; $i -lt $Bots; $i++) {
        [void]$seats.Add((New-RonSeat -Name $names[$slot] -Kind 'AI' -AiProfile $profiles[$i] -Token $tokens[$slot]))
        $slot++
    }
    return $seats.ToArray()
}

# The [ref] default is the shared sink, NOT $null: PowerShell cannot bind $null
# to a [ref] parameter, so a plain Test-RonSeatsValid -Seats $x - with no
# interest in the reason - failed with "Reference type is expected in
# argument" rather than answering the question. The engine uses the same idiom
# everywhere for the same reason.
function Test-RonSeatsValid {
    param([object[]]$Seats, [ref]$Reason = ([ref]$script:RonReasonSink))
    $count = @($Seats).Count
    if ($count -lt 2) {
        $Reason.Value = 'A game needs at least two players.'
        return $false
    }
    if ($count -gt 8) {
        $Reason.Value = 'A game takes at most eight players.'
        return $false
    }
    $tokens = @()
    foreach ($s in $Seats) {
        if ([string]::IsNullOrWhiteSpace($s.Name)) {
            $Reason.Value = 'Every player needs a name.'
            return $false
        }
        if ($tokens -contains $s.Token) {
            $Reason.Value = 'Two players cannot share a token.'
            return $false
        }
        $tokens += $s.Token
    }
    return $true
}

function New-RonGameFromSeats {
    param(
        [Parameter(Mandatory)][object[]]$Seats,
        [hashtable]$Rules = $null,
        [int]$Seed = 0,
        [switch]$RandomiseOrder
    )
    $specs = @()
    foreach ($s in $Seats) {
        $specs += @{ Name = $s.Name; Kind = $s.Kind; AiProfile = $s.AiProfile; Token = $s.Token }
    }
    return (New-RonGame -Players $specs -Seed $Seed -Rules $Rules -RandomiseOrder:$RandomiseOrder)
}

# Seat indices this machine drives directly. For a host that is every seat that
# is not Remote; for a solo or hot-seat game the local session controls
# everything and this is unused.
function Get-RonLocalSeatIds {
    param([Parameter(Mandatory)][object[]]$Seats)
    $ids = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt @($Seats).Count; $i++) {
        if ($Seats[$i].Kind -ne 'Remote') { [void]$ids.Add($i) }
    }
    return [int[]]$ids.ToArray()
}

# What the host should read out to the other players. The firewall note matters
# on a fresh machine: the FIRST non-loopback listen prompts Windows Defender,
# and until it is allowed nobody can connect.
function Get-RonHostSummary {
    param([Parameter(Mandatory)][hashtable]$Session)
    if ($Session.Kind -ne 'Host') { return '' }
    $waiting = 0
    foreach ($p in $Session.State.Players) {
        if ($p.IsBankrupt) { continue }
        if ($p.Kind -eq 'Remote' -and $p.ConnectionState -ne 'Connected') { $waiting++ }
    }
    $text = "Hosting on $($Session.Address):$($Session.Port)"
    if ($waiting -gt 0) { $text += "  -  waiting for $waiting player(s)" }
    return $text
}

# --- opening a game that is already in progress ----------------------------
#
# A game does not have to be started as a network game. Nothing about the
# engine changes when one is opened: a Host session is a Local session plus a
# listener, over the SAME GameState object, so a seat can be handed to somebody
# who turns up at turn forty and play carries straight on.

# Seats a joiner could be given. Bankrupt players are excluded - there is
# nothing left to take over - and so are seats already open or claimed.
function Get-RonOpenableSeatIds {
    param([Parameter(Mandatory)][GameState]$State)
    $ids = New-Object System.Collections.ArrayList
    foreach ($p in $State.Players) {
        if ($p.IsBankrupt) { continue }
        if ($p.Kind -eq 'Remote') { continue }
        [void]$ids.Add($p.Id)
    }
    return [int[]]$ids.ToArray()
}

# Hands a seat to whoever joins next, and returns what it looked like first so
# the change can be undone.
#
# The bot keeps playing it in the meantime rather than the table stopping dead.
# AiTakeover is exactly the state a DROPPED player's seat is left in, and the
# same join path reclaims it - so opening a seat mid-game needs no new
# machinery at all. It is a disconnect that has not had its player yet.
function Open-RonRemoteSeat {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [string]$Profile = 'Normal'
    )
    if ($PlayerId -lt 0 -or $PlayerId -ge @($State.Players).Count) {
        throw "Open-RonRemoteSeat: there is no seat $PlayerId."
    }
    $p = $State.Players[$PlayerId]
    if ($p.IsBankrupt) { throw "Open-RonRemoteSeat: $($p.Name) is already out of the game." }

    $before = @{ Id = $PlayerId; Kind = $p.Kind; AiProfile = $p.AiProfile; ConnectionState = $p.ConnectionState }
    $p.Kind = 'Remote'
    if (-not $p.AiProfile) { $p.AiProfile = $Profile }
    $p.ConnectionState = 'AiTakeover'
    $p.SessionToken = ''
    return $before
}

# Puts a seat back the way Open-RonRemoteSeat found it. Hosting can fail - a
# port in use, a firewall saying no - and a game that failed to open has to be
# exactly the game it was, not one with holes where the bots used to be.
function Restore-RonSeat {
    param([Parameter(Mandatory)][GameState]$State, [Parameter(Mandatory)][hashtable]$Snapshot)
    $p = $State.Players[[int]$Snapshot.Id]
    $p.Kind = [string]$Snapshot.Kind
    $p.AiProfile = [string]$Snapshot.AiProfile
    $p.ConnectionState = [string]$Snapshot.ConnectionState
    $p.SessionToken = ''
    return $p
}

# Seats the HOST machine drives, derived from the state rather than maintained
# by hand: everything that is not a remote seat, plus every remote seat the AI
# is holding until its player arrives.
#
# Without that second half an opened seat stalls the whole game, because
# Test-RonSessionControls would let nobody move it - not the bots, not the
# host, and not the player who has not joined yet.
function Get-RonHostLocalIds {
    param([Parameter(Mandatory)][GameState]$State)
    $ids = New-Object System.Collections.ArrayList
    foreach ($p in $State.Players) {
        if ($p.Kind -ne 'Remote' -or $p.ConnectionState -eq 'AiTakeover') { [void]$ids.Add($p.Id) }
    }
    return [int[]]$ids.ToArray()
}

# The line a host reads out - or pastes - for somebody to join with.
function Get-RonJoinCommand {
    param([Parameter(Mandatory)][hashtable]$Session, [string]$Name = 'YourName')
    if ($Session.Kind -ne 'Host') { return '' }
    return ('.\Ronopoly.cmd -Mode Join -HostAddress {0} -Port {1} -Name {2}' -f $Session.Address, $Session.Port, $Name)
}

# How a seat stands, for the hosting panel: one short phrase per player.
function Get-RonSeatStatus {
    param([Parameter(Mandatory)][GameState]$State, [Parameter(Mandatory)][int]$PlayerId)
    $p = $State.Players[$PlayerId]
    if ($p.IsBankrupt) { return 'out of the game' }
    if ($p.Kind -ne 'Remote') {
        if ($p.Kind -eq 'AI') { return "bot ($($p.AiProfile))" }
        return 'you, at this keyboard'
    }
    if ($p.ConnectionState -eq 'Connected')  { return 'joined and playing' }
    if ($p.ConnectionState -eq 'AiTakeover') {
        if ($p.SessionToken) { return 'dropped out - a bot took over' }
        return 'open - a bot is holding it'
    }
    if ($p.ConnectionState -eq 'Disconnected') { return 'dropped out' }
    return 'open - waiting'
}
