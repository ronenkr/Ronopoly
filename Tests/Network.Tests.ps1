. (Join-Path (Split-Path -Parent $PSCommandPath) '_Common.ps1')
. (Join-Path (Split-Path -Parent $PSCommandPath) '..\src\Net\NetCore.cs.ps1')
. (Join-Path (Split-Path -Parent $PSCommandPath) '..\src\Net\Protocol.ps1')
. (Join-Path (Split-Path -Parent $PSCommandPath) '..\src\Net\Session.ps1')
. (Join-Path (Split-Path -Parent $PSCommandPath) '..\src\Net\Lobby.ps1')

# Host and client live in the SAME process here, talking over a real loopback
# socket. That exercises the real framing, the real protocol and the real host
# authority check, while needing no second window and - because it binds
# 127.0.0.1 only - never triggering the Windows Defender prompt.
$script:TestPort = 27099

function Step-TestPumps {
    param([hashtable]$Server, [hashtable]$Client, [int]$Rounds = 60, [scriptblock]$Until = $null)
    $notices = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $Rounds; $i++) {
        foreach ($n in (Step-RonSession -Session $Server)) { [void]$notices.Add($n) }
        foreach ($n in (Step-RonSession -Session $Client)) { [void]$notices.Add($n) }
        if ($null -ne $Until -and (& $Until)) { break }
        Start-Sleep -Milliseconds 25
    }
    return $notices.ToArray()
}

function New-TestNetSeats {
    return @(
        (New-RonSeat -Name 'HostPlayer' -Kind 'Human'  -Token 'hat'),
        (New-RonSeat -Name 'Waiting'    -Kind 'Remote' -Token 'car')
    )
}

Describe 'Networking' {

    It 'compiles the socket engine and reports a local address' {
        Initialize-RonNetCore
        Assert-NotNull ('Ronopoly.Net.RonConnection' -as [type])
        Assert-NotNull ('Ronopoly.Net.RonListener' -as [type])
        $addr = Get-RonLocalAddress
        Assert-True ($addr -match '^\d+\.\d+\.\d+\.\d+$') "local address looked like '$addr'"
    }

    It 'connects, seats the client, and sends it the full state' {
        $game = New-RonGameFromSeats -Seats (New-TestNetSeats) -Rules (Get-RonDefaultRules) -Seed 4242
        $server = New-RonHostSession -State $game -LocalIds @(0) -Port $script:TestPort -LoopbackOnly
        try {
            Assert-NotEqual 'Failed' $server.Kind ([string]$server.Error)
            $client = New-RonClientSession -HostAddress '127.0.0.1' -Port $script:TestPort -Name 'Zoe'
            try {
                Assert-NotEqual 'Failed' $client.Kind ([string]$client.Error)
                [void](Step-TestPumps -Server $server -Client $client -Until { $null -ne $client.State })

                Assert-Equal 'connected' $client.Status
                Assert-Sequence @(1) $client.LocalIds 'the client was given seat 1'
                Assert-NotNull $client.State
                Assert-Equal $game.GameId $client.State.GameId
                Assert-Equal 'Zoe' $server.State.Players[1].Name 'the host took the joiner name'
                Assert-Equal 'Connected' $server.State.Players[1].ConnectionState
            }
            finally { Close-RonSession -Session $client }
        }
        finally { Close-RonSession -Session $server }
    }

    It 'broadcasts a host move to the client, state and all' {
        $game = New-RonGameFromSeats -Seats (New-TestNetSeats) -Rules (Get-RonDefaultRules) -Seed 777
        $port = $script:TestPort + 1
        $server = New-RonHostSession -State $game -LocalIds @(0) -Port $port -LoopbackOnly
        try {
            $client = New-RonClientSession -HostAddress '127.0.0.1' -Port $port -Name 'Zoe'
            try {
                [void](Step-TestPumps -Server $server -Client $client -Until { $null -ne $client.State })

                $r = Invoke-RonSessionAction -Session $server -Action @{ Kind = 'Roll'; PlayerId = 0 }
                Assert-True $r.Ok
                $notices = Step-TestPumps -Server $server -Client $client -Until { $client.State.Version -ge $server.State.Version }

                Assert-Equal $server.State.Version $client.State.Version 'the client caught up'
                Assert-Equal $server.State.Players[0].Position $client.State.Players[0].Position
                Assert-Equal $server.State.Turn.Phase $client.State.Turn.Phase
                Assert-True (@($notices | Where-Object { $_.Kind -eq 'Batch' }).Count -ge 1) 'an event batch arrived'
            }
            finally { Close-RonSession -Session $client }
        }
        finally { Close-RonSession -Session $server }
    }

    It 'refuses to let a client move a seat that is not theirs' {
        # The host re-checks the actor on every request, whatever the action
        # object claims. This is the whole point of host authority.
        $game = New-RonGameFromSeats -Seats (New-TestNetSeats) -Rules (Get-RonDefaultRules) -Seed 555
        $port = $script:TestPort + 2
        $server = New-RonHostSession -State $game -LocalIds @(0) -Port $port -LoopbackOnly
        try {
            $client = New-RonClientSession -HostAddress '127.0.0.1' -Port $port -Name 'Zoe'
            try {
                [void](Step-TestPumps -Server $server -Client $client -Until { $null -ne $client.State })
                $before = $server.State.Version

                # Seat 1 tries to roll for seat 0.
                [void](Invoke-RonSessionAction -Session $client -Action @{ Kind = 'Roll'; PlayerId = 0 })
                $notices = Step-TestPumps -Server $server -Client $client -Rounds 24

                Assert-Equal $before $server.State.Version 'the host applied nothing'
                Assert-True (@($notices | Where-Object { $_.Kind -eq 'Rejected' }).Count -ge 1) 'and said so'
            }
            finally { Close-RonSession -Session $client }
        }
        finally { Close-RonSession -Session $server }
    }

    It 'reassembles a frame far larger than one TCP read' {
        # A late-game snapshot is tens of kilobytes and will not arrive in a
        # single read, so the length-prefixed framing has to stitch it together.
        Initialize-RonNetCore
        $listener = New-Object Ronopoly.Net.RonListener
        Assert-True ($listener.Start(($script:TestPort + 3), $true)) ([string]$listener.LastError)
        try {
            $err = ''
            $client = [Ronopoly.Net.RonDial]::Connect('127.0.0.1', ($script:TestPort + 3), 3000, [ref]$err)
            Assert-NotNull $client ([string]$err)
            try {
                $peer = $null
                for ($i = 0; $i -lt 60 -and -not $listener.Pending.TryDequeue([ref]$peer); $i++) { Start-Sleep -Milliseconds 20 }
                Assert-NotNull $peer 'the listener accepted the connection'

                $payload = 'x' * 200000
                $peer.Send($payload)
                $got = $null
                for ($i = 0; $i -lt 100 -and -not $client.Inbox.TryDequeue([ref]$got); $i++) { Start-Sleep -Milliseconds 20 }
                Assert-NotNull $got 'the frame arrived'
                Assert-Equal $payload.Length $got.Length 'and arrived whole'
            }
            finally { $client.Close() }
        }
        finally { $listener.Stop() }
    }

    It 'hands a disconnected seat to the AI so the game can continue' {
        $game = New-RonGameFromSeats -Seats (New-TestNetSeats) -Rules (Get-RonDefaultRules) -Seed 909
        $port = $script:TestPort + 4
        $server = New-RonHostSession -State $game -LocalIds @(0) -Port $port -LoopbackOnly
        try {
            $client = New-RonClientSession -HostAddress '127.0.0.1' -Port $port -Name 'Zoe'
            [void](Step-TestPumps -Server $server -Client $client -Until { $null -ne $client.State })
            Assert-Equal 'Connected' $server.State.Players[1].ConnectionState

            Close-RonSession -Session $client
            $notices = Step-TestPumps -Server $server -Client $client -Rounds 40 `
                -Until { $server.State.Players[1].ConnectionState -eq 'Disconnected' }
            Assert-Equal 'Disconnected' $server.State.Players[1].ConnectionState
            Assert-True (@($notices | Where-Object { $_.Kind -eq 'Disconnected' }).Count -ge 1)

            Set-RonAiTakeover -Session $server -PlayerId 1
            Assert-Equal 'AiTakeover' $server.State.Players[1].ConnectionState
            Assert-True ($server.State.Players[1].IsAiControlled()) 'the AI now drives that seat'
            Assert-True (Test-RonSessionControls -Session $server -PlayerId 1) 'and the host may act for it'
        }
        finally { Close-RonSession -Session $server }
    }
}

Describe 'Hosting leaves somewhere to sit' {

    It 'opens a remote seat when hosting' {
        # The whole network layer is useless without this. Hosting used to deal
        # the default line-up - one human and three bots - which answers every
        # joiner with "this game is full", because a seat can only be claimed
        # if its Kind is Remote and nothing ever created one.
        $seats = New-RonDefaultSeats -Remote 1
        $remote = @($seats | Where-Object { $_.Kind -eq 'Remote' })
        Assert-Equal 1 $remote.Count 'hosting opened no seat for anyone to join'
        Assert-True (Test-RonSeatsValid -Seats $seats) 'the hosting line-up is not a legal table'
        # And the seat is not one this machine plays.
        $local = @(Get-RonLocalSeatIds -Seats $seats)
        Assert-True (-not ($local -contains 1)) 'the open seat is being driven locally'
    }

    It 'takes its remote seats out of the bots, not out of the table' {
        $solo = New-RonDefaultSeats
        $hosted = New-RonDefaultSeats -Remote 2
        Assert-Equal @($solo).Count @($hosted).Count 'hosting changed the size of the game'
    }

    It 'still leaves nothing open for a solo game' {
        $seats = New-RonDefaultSeats
        Assert-Equal 0 @($seats | Where-Object { $_.Kind -eq 'Remote' }).Count 'a solo game opened a network seat'
    }
}

Describe 'Opening a game that is already running' {

    # The feature the status strip's button drives. A game does not have to be
    # started with -Mode Host, so these check the mid-game path specifically:
    # the same GameState object, no restart, and nobody's position lost.

    function New-TestRunningGame {
        param([int]$Seed = 1234)
        $seats = @(
            (New-RonSeat -Name 'Host' -Kind 'Human' -Token 'hat'),
            (New-RonSeat -Name 'Bot'  -Kind 'AI' -AiProfile 'Hard' -Token 'car')
        )
        return (New-RonGameFromSeats -Seats $seats -Rules (Get-RonDefaultRules) -Seed $Seed)
    }

    It 'hands a bot seat over and leaves the AI holding it' {
        # An opened seat that nobody drives stops the whole table. AiTakeover is
        # the state a DROPPED player's seat is left in, so the bot keeps the
        # chair warm and the existing join path reclaims it.
        $game = New-TestRunningGame
        Assert-Sequence @(0, 1) (Get-RonOpenableSeatIds -State $game) 'both seats could be opened'

        [void](Open-RonRemoteSeat -State $game -PlayerId 1)
        Assert-Equal 'Remote' $game.Players[1].Kind
        Assert-Equal 'AiTakeover' $game.Players[1].ConnectionState
        Assert-True ($game.Players[1].IsAiControlled()) 'the table would sit waiting for nobody'
        Assert-Sequence @(0, 1) (Get-RonHostLocalIds -State $game) 'the host must keep driving it until someone joins'
        Assert-Sequence @(0) (Get-RonOpenableSeatIds -State $game) 'an open seat cannot be opened twice'
    }

    It 'gives a human seat a profile so the bot can actually play it' {
        # A hot-seat player moving to their own computer leaves a seat with no
        # AiProfile at all. Get-RonAiProfile falls back to Normal, but leaving
        # the field blank makes the HUD say nothing about who is playing.
        $game = New-TestRunningGame
        $game.Players[0].AiProfile = ''
        [void](Open-RonRemoteSeat -State $game -PlayerId 0)
        Assert-Equal 'Normal' $game.Players[0].AiProfile
    }

    It 'refuses a seat that is already out of the game' {
        $game = New-TestRunningGame
        $game.Players[1].IsBankrupt = $true
        Assert-Sequence @(0) (Get-RonOpenableSeatIds -State $game) 'a bankrupt seat was offered'
        Assert-Throws { Open-RonRemoteSeat -State $game -PlayerId 1 }
    }

    It 'puts a seat back exactly as it was' {
        $game = New-TestRunningGame
        $before = Open-RonRemoteSeat -State $game -PlayerId 1
        [void](Restore-RonSeat -State $game -Snapshot $before)
        Assert-Equal 'AI' $game.Players[1].Kind
        Assert-Equal 'Hard' $game.Players[1].AiProfile
        Assert-Equal 'Local' $game.Players[1].ConnectionState
    }

    It 'fails cleanly when the port is already taken' {
        # And leaves the local session usable, which is what lets the panel put
        # the seats back and say why rather than losing the game.
        Initialize-RonNetCore
        $port = $script:TestPort + 5
        $blocker = New-Object Ronopoly.Net.RonListener
        Assert-True ($blocker.Start($port, $true)) ([string]$blocker.LastError)
        try {
            $game = New-TestRunningGame
            $local = New-RonLocalSession -State $game
            $result = Open-RonSessionToNetwork -Session $local -Port $port -LoopbackOnly
            Assert-Equal 'Failed' $result.Kind 'a busy port was hosted on anyway'
            Assert-Equal 'Local' $local.Kind 'the local game was thrown away'
            Assert-NotNull $local.State
        }
        finally { $blocker.Stop() }
    }

    It 'lets a joiner take a seat opened mid-game, and stops driving it' {
        $port = $script:TestPort + 6
        $game = New-TestRunningGame -Seed 24680
        $local = New-RonLocalSession -State $game

        # Play a turn first, so this is genuinely a game in progress rather than
        # a fresh one hosted by another name.
        [void](Invoke-RonSessionAction -Session $local -Action @{ Kind = 'Roll'; PlayerId = 0 })
        $moved = $game.Version
        Assert-True ($moved -gt 0) 'nothing had happened yet'

        [void](Open-RonRemoteSeat -State $game -PlayerId 1)
        $server = Open-RonSessionToNetwork -Session $local -Port $port -LoopbackOnly
        try {
            Assert-NotEqual 'Failed' $server.Kind ([string]$server.Error)
            Assert-Equal '127.0.0.1' $server.Address 'a loopback listener advertised a LAN address'
            Assert-True ($server.State -eq $game) 'hosting swapped the state object out from under the game'
            Assert-True (Test-RonSessionControls -Session $server -PlayerId 1) 'nobody was left driving the open seat'

            $client = New-RonClientSession -HostAddress '127.0.0.1' -Port $port -Name 'Zoe'
            try {
                Assert-NotEqual 'Failed' $client.Kind ([string]$client.Error)
                [void](Step-TestPumps -Server $server -Client $client -Until { $null -ne $client.State })

                Assert-Sequence @(1) $client.LocalIds 'the joiner was given the opened seat'
                Assert-Equal $moved $client.State.Version 'the joiner did not get the turn already played'
                Assert-Equal $game.Players[0].Position $client.State.Players[0].Position
                Assert-Equal 'Zoe' $server.State.Players[1].Name
                Assert-Equal 'Connected' $server.State.Players[1].ConnectionState
                Assert-False ($server.State.Players[1].IsAiControlled()) 'the bot kept playing a claimed seat'
                # The handover: the host was holding the seat, and now it is not.
                Assert-False (Test-RonSessionControls -Session $server -PlayerId 1) 'the host still drives a claimed seat'
                Assert-True  (Test-RonSessionControls -Session $server -PlayerId 0) 'the host lost its own seat'
            }
            finally { Close-RonSession -Session $client }
        }
        finally { Close-RonSession -Session $server }
    }

    It 'goes back to a local game when hosting stops' {
        $port = $script:TestPort + 7
        $game = New-TestRunningGame
        $snapshot = Open-RonRemoteSeat -State $game -PlayerId 1
        $server = Open-RonSessionToNetwork -Session (New-RonLocalSession -State $game) -Port $port -LoopbackOnly
        Assert-NotEqual 'Failed' $server.Kind ([string]$server.Error)

        $back = Close-RonSessionNetwork -Session $server
        [void](Restore-RonSeat -State $game -Snapshot $snapshot)
        Assert-Equal 'Local' $back.Kind
        Assert-True ($back.State -eq $game) 'the position was lost on the way back'
        Assert-Equal 'AI' $game.Players[1].Kind

        # And the port is genuinely free again, which is the only way to know
        # the listener was actually stopped rather than merely forgotten.
        $probe = New-Object Ronopoly.Net.RonListener
        Assert-True ($probe.Start($port, $true)) 'the listener was still holding the port'
        $probe.Stop()
    }
}

exit (Complete-RonTests)
