#
# Ronopoly - the wire protocol.
#
# Messages are compact JSON objects with a short type tag. The engine's own
# action objects travel unchanged inside ActionRequest, so there is no second
# representation of an action to keep in step.
#
# HOST-AUTHORITATIVE. A client never decides legality: it sends an
# ActionRequest, and the host runs the SAME Test-RonActionLegal that hot-seat
# uses. There is exactly one rules implementation in the project.
#
# DESIGN NOTE (a deliberate change from the original plan): the host sends the
# full authoritative state alongside each event batch rather than having
# clients replay events into a local replica. A snapshot is ~20 KB and ~2 ms to
# build, which is nothing on a LAN, and it removes the largest correctness risk
# in the whole networking layer - an Apply-Event that has to mirror the rules
# exactly and desyncs silently when it does not.
#

$script:RonProtocolVersion = 1
$script:RonDefaultPort     = 27015

function New-RonMessage {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Type,
        [Parameter(Position = 1)][hashtable]$Data = @{}
    )
    $h = @{ T = $Type }
    foreach ($k in $Data.Keys) { $h[$k] = $Data[$k] }
    return $h
}

function ConvertTo-RonWire {
    param([Parameter(Mandatory)][object]$Message)
    return (ConvertTo-RonJson $Message)
}

function ConvertFrom-RonWire {
    param([Parameter(Mandatory)][string]$Text)
    try { return (ConvertFrom-RonJson $Text) }
    catch {
        Write-RonLog "Undecodable frame ($($_.Exception.Message))" -Level Warn -Category net
        return $null
    }
}

# --- client to host --------------------------------------------------------

function New-RonHelloMessage {
    param([string]$Name, [string]$SessionToken = '')
    return (New-RonMessage 'Hello' @{
        Name = $Name
        ProtocolVersion = $script:RonProtocolVersion
        SessionToken = $SessionToken
    })
}

function New-RonActionRequest {
    param([int]$Seq, [object]$Action)
    return (New-RonMessage 'ActionRequest' @{ Seq = $Seq; Action = $Action })
}

function New-RonResyncRequest {
    param([int]$HaveVersion)
    return (New-RonMessage 'RequestResync' @{ HaveVersion = $HaveVersion })
}

function New-RonPingMessage { return (New-RonMessage 'Ping' @{ T0 = [DateTime]::UtcNow.Ticks }) }
function New-RonByeMessage  { return (New-RonMessage 'Bye' @{}) }

# --- host to client --------------------------------------------------------

function New-RonWelcomeMessage {
    param([int]$PlayerId, [string]$GameId, [string]$SessionToken)
    return (New-RonMessage 'Welcome' @{
        PlayerId = $PlayerId
        GameId = $GameId
        SessionToken = $SessionToken
        ProtocolVersion = $script:RonProtocolVersion
    })
}

function New-RonRejectMessage {
    param([string]$Code, [string]$Reason)
    return (New-RonMessage 'Reject' @{ Code = $Code; Reason = $Reason })
}

function New-RonFullStateMessage {
    param([Parameter(Mandatory)][GameState]$State)
    return (New-RonMessage 'FullState' @{ Version = $State.Version; State = $State.ToData() })
}

# Events for the animation and the log; State so the client never has to derive
# anything itself.
function New-RonEventBatchMessage {
    param([Parameter(Mandatory)][GameState]$State, [object[]]$Events, [int]$BaseVersion)
    return (New-RonMessage 'EventBatch' @{
        BaseVersion = $BaseVersion
        NewVersion = $State.Version
        Events = $Events
        State = $State.ToData()
    })
}

function New-RonActionRejectedMessage {
    param([int]$Seq, [string]$Reason)
    return (New-RonMessage 'ActionRejected' @{ Seq = $Seq; Reason = $Reason })
}

function New-RonPongMessage {
    param([long]$T0)
    return (New-RonMessage 'Pong' @{ T0 = $T0 })
}

function Get-RonDefaultPort { return $script:RonDefaultPort }
function Get-RonProtocolVersion { return $script:RonProtocolVersion }

# Shown in the lobby so the host can read it out. Uses the interface Windows
# would actually route over.
function Get-RonLocalAddress {
    Initialize-RonNetCore
    return [Ronopoly.Net.RonDial]::GetLocalAddress()
}
