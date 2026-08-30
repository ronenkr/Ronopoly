#
# Ronopoly - the session, and THE seam that makes hot-seat and LAN one path.
#
# Three implementations, one shape:
#
#   Local   the engine, in-process. Hot-seat and solo play.
#   Host    the engine, in-process, PLUS sockets broadcasting to clients.
#   Client  no engine at all: submits actions to the host and renders what
#           comes back.
#
# The UI only ever calls Invoke-RonSessionAction / Step-RonSession /
# Test-RonSessionControls, so it cannot tell the three apart. That is what
# makes every hot-seat playtest also a test of the networked code path, and it
# is why Local exists at all rather than the UI calling the engine directly.
#

function New-RonLocalSession {
    param([Parameter(Mandatory)][GameState]$State)
    return @{
        Kind      = 'Local'
        State     = $State
        Listener  = $null
        Peers     = @()
        Conn      = $null
        LocalIds  = @()      # empty means "this session controls everyone"
        Status    = 'ready'
        Seq       = 0
        Pending   = New-Object System.Collections.Queue
    }
}

# True when this session is allowed to act for a player: always, locally; only
# for your own seat as a client; for the host's own seats plus any AI takeover
# when hosting.
function Test-RonSessionControls {
    param([Parameter(Mandatory)][hashtable]$Session, [Parameter(Mandatory)][int]$PlayerId)
    if ($Session.Kind -eq 'Local') { return $true }
    if (@($Session.LocalIds).Count -eq 0) { return $false }
    return (@($Session.LocalIds) -contains $PlayerId)
}

# Applies an action and returns @{ Ok; State; Events; Reason }.
#
# Local and Host run the engine directly. A Client sends the request and
# returns Ok=false with no events - the authoritative result arrives later as
# an EventBatch and is picked up by Step-RonSession.
function Invoke-RonSessionAction {
    param(
        [Parameter(Mandatory)][hashtable]$Session,
        [Parameter(Mandatory)][object]$Action
    )
    if ($Session.Kind -eq 'Client') {
        $Session.Seq++
        Send-RonFrame -Connection $Session.Conn -Message (New-RonActionRequest -Seq $Session.Seq -Action $Action)
        return @{ Ok = $false; State = $Session.State; Events = @(); Reason = 'sent to host' }
    }

    $base = $Session.State.Version
    $result = Invoke-RonAction -State $Session.State -Action $Action
    if (-not $result.Ok) {
        return @{ Ok = $false; State = $Session.State; Events = @(); Reason = $result.Reason }
    }

    if ($Session.Kind -eq 'Host') {
        $batch = New-RonEventBatchMessage -State $Session.State -Events $result.Events -BaseVersion $base
        Send-RonBroadcast -Session $Session -Message $batch
    }
    return @{ Ok = $true; State = $Session.State; Events = $result.Events; Reason = '' }
}

# --- transport plumbing ----------------------------------------------------

function Send-RonFrame {
    param([object]$Connection, [Parameter(Mandatory)][object]$Message)
    if ($null -eq $Connection) { return }
    $Connection.Send((ConvertTo-RonWire $Message))
}

function Send-RonBroadcast {
    param([Parameter(Mandatory)][hashtable]$Session, [Parameter(Mandatory)][object]$Message)
    $text = ConvertTo-RonWire $Message
    foreach ($peer in @($Session.Peers)) {
        if ($peer.IsConnected) { $peer.Send($text) }
    }
}

function Close-RonSession {
    param([Parameter(Mandatory)][hashtable]$Session)
    # Say goodbye first, so the host reports a clean departure rather than a
    # dropped connection and a grace-period countdown.
    if ($Session.Kind -eq 'Client' -and $null -ne $Session.Conn -and $Session.Conn.IsConnected) {
        try { Send-RonFrame -Connection $Session.Conn -Message (New-RonByeMessage) } catch { }
    }
    foreach ($peer in @($Session.Peers)) { try { $peer.Close() } catch { } }
    if ($null -ne $Session.Conn)     { try { $Session.Conn.Close() } catch { } }
    if ($null -ne $Session.Listener) { try { $Session.Listener.Stop() } catch { } }
    $Session.Peers = @()
    $Session.Conn = $null
    $Session.Listener = $null
    $Session.Status = 'closed'
}

# --- hosting ---------------------------------------------------------------

function New-RonHostSession {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [int[]]$LocalIds = @(0),
        [int]$Port = 0,
        [switch]$LoopbackOnly
    )
    Initialize-RonNetCore
    if ($Port -le 0) { $Port = Get-RonDefaultPort }

    $listener = New-Object Ronopoly.Net.RonListener
    # Start returns false rather than throwing so the lobby can show a real
    # message: on a fresh machine the FIRST non-loopback listen triggers the
    # Windows Defender prompt for powershell.exe.
    if (-not $listener.Start($Port, [bool]$LoopbackOnly)) {
        return @{ Kind = 'Failed'; Error = $listener.LastError; Status = 'failed' }
    }

    return @{
        Kind      = 'Host'
        State     = $State
        Listener  = $listener
        Peers     = @()
        Conn      = $null
        LocalIds  = $LocalIds
        Status    = 'listening'
        Port      = $listener.Port
        Address   = (Get-RonLocalAddress)
        Seq       = 0
        Tokens    = @{}      # session token -> player id, for reconnects
        Pending   = New-Object System.Collections.Queue
    }
}

# --- joining ---------------------------------------------------------------

function New-RonClientSession {
    param(
        [Parameter(Mandatory)][string]$HostAddress,
        [int]$Port = 0,
        [Parameter(Mandatory)][string]$Name,
        [int]$TimeoutMs = 5000
    )
    Initialize-RonNetCore
    if ($Port -le 0) { $Port = Get-RonDefaultPort }

    $connectError = ""
    $conn = [Ronopoly.Net.RonDial]::Connect($HostAddress, $Port, $TimeoutMs, [ref]$connectError)
    if ($null -eq $conn) {
        return @{ Kind = 'Failed'; Error = $connectError; Status = "failed" }
    }

    $session = @{
        Kind      = 'Client'
        State     = $null
        Listener  = $null
        Peers     = @()
        Conn      = $conn
        LocalIds  = @()
        Status    = 'connecting'
        Seq       = 0
        Name      = $Name
        Token     = ''
        LastPing  = [DateTime]::UtcNow
        LastPong  = [DateTime]::UtcNow
        Pending   = New-Object System.Collections.Queue
    }
    Send-RonFrame -Connection $conn -Message (New-RonHelloMessage -Name $Name)
    return $session
}

# --- the pump --------------------------------------------------------------
#
# Called from a DispatcherTimer on the UI thread at ~30 Hz. Everything here
# runs on that thread; the only work the background reader threads do is push
# whole frames into a lock-free queue.
#
# Returns a list of notices for the UI: @{ Kind; ... }.
function Step-RonSession {
    param([Parameter(Mandatory)][hashtable]$Session)
    $notices = New-Object System.Collections.ArrayList

    if ($Session.Kind -eq 'Host')   { Step-RonHostSession   -Session $Session -Notices $notices }
    if ($Session.Kind -eq 'Client') { Step-RonClientSession -Session $Session -Notices $notices }

    return $notices.ToArray()
}

function Step-RonHostSession {
    param([hashtable]$Session, [System.Collections.ArrayList]$Notices)

    # 1. Accept anyone new.
    $incoming = $null
    while ($Session.Listener.Pending.TryDequeue([ref]$incoming)) {
        $Session.Peers = @($Session.Peers) + @($incoming)
        Write-RonLog "Peer connected from $($incoming.Endpoint)" -Level Info -Category net
    }

    # 2. Drain every peer's inbox.
    foreach ($peer in @($Session.Peers)) {
        $text = $null
        while ($peer.Inbox.TryDequeue([ref]$text)) {
            $msg = ConvertFrom-RonWire $text
            if ($null -eq $msg) { continue }
            Receive-RonHostMessage -Session $Session -Peer $peer -Message $msg -Notices $Notices
        }
    }

    # 3. Notice anyone who has gone away.
    $alive = New-Object System.Collections.ArrayList
    foreach ($peer in @($Session.Peers)) {
        if ($peer.IsConnected) { [void]$alive.Add($peer); continue }
        if ($peer.PlayerId -ge 0 -and $null -ne $Session.State) {
            $player = $Session.State.Players[$peer.PlayerId]
            if ($player.ConnectionState -ne 'AiTakeover') {
                $player.ConnectionState = 'Disconnected'
                [void]$Notices.Add(@{ Kind = 'Disconnected'; PlayerId = $peer.PlayerId; Name = $player.Name })
            }
        }
        Write-RonLog "Peer lost: $($peer.RemoteName) ($($peer.LastError))" -Level Warn -Category net
    }
    $Session.Peers = $alive.ToArray()
}

function Receive-RonHostMessage {
    param([hashtable]$Session, $Peer, [object]$Message, [System.Collections.ArrayList]$Notices)

    switch ([string]$Message.T) {

        'Hello' {
            if ([int]$Message.ProtocolVersion -ne (Get-RonProtocolVersion)) {
                Send-RonFrame -Connection $Peer -Message (New-RonRejectMessage 'version' `
                    "This game speaks protocol $(Get-RonProtocolVersion); you sent $($Message.ProtocolVersion).")
                $Peer.Close()
                return
            }
            $seat = Get-RonFreeSeat -Session $Session -Token ([string]$Message.SessionToken)
            if ($seat -lt 0) {
                Send-RonFrame -Connection $Peer -Message (New-RonRejectMessage 'full' 'This game is full.')
                $Peer.Close()
                return
            }
            $token = New-RonId
            $Session.Tokens[$token] = $seat
            $Peer.PlayerId = $seat
            $Peer.RemoteName = [string]$Message.Name

            $player = $Session.State.Players[$seat]
            $player.Name = [string]$Message.Name
            $player.Kind = 'Remote'
            $player.ConnectionState = 'Connected'
            $player.SessionToken = $token

            Send-RonFrame -Connection $Peer -Message (New-RonWelcomeMessage -PlayerId $seat -GameId $Session.State.GameId -SessionToken $token)
            Send-RonFrame -Connection $Peer -Message (New-RonFullStateMessage -State $Session.State)
            [void]$Notices.Add(@{ Kind = 'Joined'; PlayerId = $seat; Name = $player.Name })
        }

        'ActionRequest' {
            $action = $Message.Action
            # The host re-checks the actor: a client may only move its own seat,
            # whatever the action object claims.
            if ([int](Get-RonActionField $action 'PlayerId' -1) -ne $Peer.PlayerId) {
                Send-RonFrame -Connection $Peer -Message (New-RonActionRejectedMessage ([int]$Message.Seq) 'not your seat')
                return
            }
            $base = $Session.State.Version
            $result = Invoke-RonAction -State $Session.State -Action $action
            if (-not $result.Ok) {
                Send-RonFrame -Connection $Peer -Message (New-RonActionRejectedMessage ([int]$Message.Seq) $result.Reason)
                return
            }
            Send-RonBroadcast -Session $Session -Message (New-RonEventBatchMessage -State $Session.State -Events $result.Events -BaseVersion $base)
            [void]$Notices.Add(@{ Kind = 'Applied'; Events = $result.Events })
        }

        'RequestResync' {
            Send-RonFrame -Connection $Peer -Message (New-RonFullStateMessage -State $Session.State)
        }

        'Ping' { Send-RonFrame -Connection $Peer -Message (New-RonPongMessage ([long]$Message.T0)) }

        'Bye' { $Peer.Close() }
    }
}

# A returning player reclaims their own seat via the token they were given;
# otherwise the first seat still marked Remote and unclaimed is handed out.
function Get-RonFreeSeat {
    param([hashtable]$Session, [string]$Token)
    if ($Token -and $Session.Tokens.ContainsKey($Token)) { return [int]$Session.Tokens[$Token] }
    foreach ($p in $Session.State.Players) {
        if ($p.Kind -ne 'Remote') { continue }
        if ($p.IsBankrupt) { continue }
        if ($p.ConnectionState -eq 'Connected') { continue }
        return $p.Id
    }
    return -1
}

function Step-RonClientSession {
    param([hashtable]$Session, [System.Collections.ArrayList]$Notices)
    $conn = $Session.Conn
    if ($null -eq $conn) { return }

    $text = $null
    while ($conn.Inbox.TryDequeue([ref]$text)) {
        $msg = ConvertFrom-RonWire $text
        if ($null -eq $msg) { continue }

        switch ([string]$msg.T) {
            'Welcome' {
                $Session.LocalIds = @([int]$msg.PlayerId)
                $Session.Token = [string]$msg.SessionToken
                $Session.Status = 'connected'
                [void]$Notices.Add(@{ Kind = 'Welcome'; PlayerId = [int]$msg.PlayerId })
            }
            'Reject' {
                $Session.Status = 'rejected'
                [void]$Notices.Add(@{ Kind = 'Rejected'; Reason = [string]$msg.Reason })
            }
            'FullState' {
                $Session.State = [GameState]::FromData($msg.State)
                [void]$Notices.Add(@{ Kind = 'Resync'; State = $Session.State })
            }
            'EventBatch' {
                # The host sends authoritative state with every batch, so there
                # is nothing to replay and nothing that can drift.
                $have = 0
                if ($null -ne $Session.State) { $have = $Session.State.Version }
                $Session.State = [GameState]::FromData($msg.State)
                [void]$Notices.Add(@{ Kind = 'Batch'; State = $Session.State; Events = @($msg.Events) })

                # A gap means a batch was missed - which TCP ordering should
                # make impossible, but a reconnect can produce. Ask for the
                # whole position rather than guessing.
                if ([int]$msg.BaseVersion -ne $have) {
                    Send-RonFrame -Connection $conn -Message (New-RonResyncRequest -HaveVersion $Session.State.Version)
                }
            }
            'ActionRejected' {
                [void]$Notices.Add(@{ Kind = 'Rejected'; Reason = [string]$msg.Reason })
            }
            'Pong' { $Session.LastPong = [DateTime]::UtcNow }
        }
    }

    # A keepalive, and the only way to notice a half-open connection: a TCP
    # peer that has vanished without a FIN looks perfectly healthy until
    # something is actually written to it.
    if ($Session.Status -eq 'connected') {
        $since = ([DateTime]::UtcNow - $Session.LastPing).TotalSeconds
        if ($since -ge 5) {
            $Session.LastPing = [DateTime]::UtcNow
            Send-RonFrame -Connection $conn -Message (New-RonPingMessage)
        }
    }

    if (-not $conn.IsConnected -and $Session.Status -ne 'lost') {
        $Session.Status = 'lost'
        [void]$Notices.Add(@{ Kind = 'HostLost'; Reason = $conn.LastError })
    }
}

# After the grace period a disconnected player's seat is handed to the AI, so
# the game continues instead of stalling. Reconnecting reclaims it.
function Set-RonAiTakeover {
    param(
        [Parameter(Mandatory)][hashtable]$Session,
        [Parameter(Mandatory)][int]$PlayerId,
        [string]$Profile = 'Normal'
    )
    $player = $Session.State.Players[$PlayerId]
    $player.ConnectionState = 'AiTakeover'
    if (-not $player.AiProfile) { $player.AiProfile = $Profile }
    $Session.LocalIds = @(@($Session.LocalIds) + $PlayerId | Select-Object -Unique)
}
