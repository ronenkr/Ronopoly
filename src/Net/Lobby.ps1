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
function New-RonDefaultSeats {
    param([int]$Humans = 1, [int]$Bots = 3)
    $tokens = (Get-RonTokens).Order
    $names  = @('You','Ada','Blake','Cleo','Dax','Esme','Fox','Gwen')
    $seats  = New-Object System.Collections.ArrayList
    $profiles = @('Normal','Hard','Expert','Easy','Normal','Hard','Expert','Easy')
    $slot = 0

    for ($i = 0; $i -lt $Humans; $i++) {
        [void]$seats.Add((New-RonSeat -Name $names[$slot] -Kind 'Human' -Token $tokens[$slot]))
        $slot++
    }
    for ($i = 0; $i -lt $Bots; $i++) {
        [void]$seats.Add((New-RonSeat -Name $names[$slot] -Kind 'AI' -AiProfile $profiles[$i] -Token $tokens[$slot]))
        $slot++
    }
    return $seats.ToArray()
}

function Test-RonSeatsValid {
    param([object[]]$Seats, [ref]$Reason = $null)
    $count = @($Seats).Count
    if ($count -lt 2) {
        if ($null -ne $Reason) { $Reason.Value = 'A game needs at least two players.' }
        return $false
    }
    if ($count -gt 8) {
        if ($null -ne $Reason) { $Reason.Value = 'A game takes at most eight players.' }
        return $false
    }
    $tokens = @()
    foreach ($s in $Seats) {
        if ([string]::IsNullOrWhiteSpace($s.Name)) {
            if ($null -ne $Reason) { $Reason.Value = 'Every player needs a name.' }
            return $false
        }
        if ($tokens -contains $s.Token) {
            if ($null -ne $Reason) { $Reason.Value = 'Two players cannot share a token.' }
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
        if ($p.Kind -eq 'Remote' -and $p.ConnectionState -ne 'Connected') { $waiting++ }
    }
    $text = "Hosting on $($Session.Address):$($Session.Port)"
    if ($waiting -gt 0) { $text += "  -  waiting for $waiting player(s)" }
    return $text
}
