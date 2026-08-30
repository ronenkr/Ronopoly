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

exit (Complete-RonTests)
