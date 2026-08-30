#
# Ronopoly - THE seam.
#
# Everything that can ever change the game goes through these three functions:
#
#   Get-RonLegalActions   what may happen next, for the player being waited on
#   Test-RonActionLegal   is this specific action allowed
#   Invoke-RonAction      apply it, return the events it produced
#
# A human click, an AI timer tick and an inbound network message are all just
# different sources of the same action object, which is why hot-seat, solo and
# LAN are one code path rather than three.
#
# An action is a hashtable or PSCustomObject:
#   @{ Kind = 'Bid'; PlayerId = 2; Amount = 120 }
# Both forms support dotted access, so ConvertFrom-Json output works unchanged.

# Phases in which a player may mortgage, sell buildings and trade.
#
# AwaitBuyDecision is in the list because the printed rules put no timing
# condition on raising money - unimproved sites may be mortgaged, and buildings
# sold back to the Bank, at any point in your own turn. Leaving it out meant a
# player who landed on a deed they were a few pounds short of had no move but
# to send it to auction, which is the opposite of what the rules allow.
#
# Anything added here must survive being INTERRUPTED: a trade opened from one
# of these phases parks at AwaitTradeResponse and comes back through
# 'Resolving', so Step-RonTurn has to put the outstanding decision back. See
# the "interrupted decision" block there.
$script:RonManagementPhases = @('AwaitRoll','AwaitEndTurn','AwaitJailChoice','AwaitDebt','AwaitBuyDecision')

function New-RonAction {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Kind,
        [Parameter(Position = 1)][hashtable]$Data = @{}
    )
    $h = @{ Kind = $Kind }
    foreach ($k in $Data.Keys) { $h[$k] = $Data[$k] }
    return [pscustomobject]$h
}

function Get-RonActionField {
    param([Parameter(Mandatory)][object]$Action, [Parameter(Mandatory)][string]$Name, $Default = $null)
    $v = $null
    if ($Action -is [System.Collections.IDictionary]) {
        if ($Action.Contains($Name)) { $v = $Action[$Name] }
    }
    else {
        $prop = $Action.PSObject.Properties[$Name]
        if ($null -ne $prop) { $v = $prop.Value }
    }
    if ($null -eq $v) { return $Default }
    return $v
}

function Get-RonNextSeatId {
    param([Parameter(Mandatory)][GameState]$State, [Parameter(Mandatory)][int]$AfterPlayerId)
    $order = @($State.Order)
    $at = 0
    for ($i = 0; $i -lt $order.Count; $i++) { if ($order[$i] -eq $AfterPlayerId) { $at = $i; break } }
    for ($step = 1; $step -le $order.Count; $step++) {
        $candidate = $order[($at + $step) % $order.Count]
        if (-not $State.GetPlayer($candidate).IsBankrupt) { return $candidate }
    }
    return $AfterPlayerId
}

# --- what may happen next --------------------------------------------------

function Get-RonLegalActions {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [int]$PlayerId = -1
    )
    $out = New-Object System.Collections.ArrayList
    if ($State.IsOver) { return $out.ToArray() }

    $acting = Get-RonActingPlayerId -State $State
    if ($PlayerId -lt 0) { $PlayerId = $acting }
    if ($PlayerId -ne $acting) { return $out.ToArray() }

    $p     = $State.GetPlayer($PlayerId)
    $phase = $State.Turn.Phase

    switch ($phase) {

        'AwaitRoll' {
            [void]$out.Add(@{ Kind = 'Roll'; PlayerId = $PlayerId })
        }

        'AwaitJailChoice' {
            $fine = [int](Get-RonBoard).JailFine
            if ($p.Cash -ge $fine) { [void]$out.Add(@{ Kind = 'PayJailFine'; PlayerId = $PlayerId; Amount = $fine }) }
            if ($p.JailCards -gt 0) { [void]$out.Add(@{ Kind = 'UseJailCard'; PlayerId = $PlayerId }) }
            [void]$out.Add(@{ Kind = 'JailRoll'; PlayerId = $PlayerId })
        }

        'AwaitBuyDecision' {
            $index = $State.Turn.PendingSpaceIndex
            $price = Get-RonSpacePrice $index
            if ($p.Cash -ge $price) {
                [void]$out.Add(@{ Kind = 'BuyProperty'; PlayerId = $PlayerId; SpaceIndex = $index; Amount = $price })
            }
            [void]$out.Add(@{ Kind = 'DeclineProperty'; PlayerId = $PlayerId; SpaceIndex = $index })
        }

        'AwaitAuction' {
            $min = Get-RonMinimumBid -State $State
            $ceiling = $p.Cash
            if ($State.RuleOn('AllowBidToRaiseFunds')) { $ceiling = Get-RonLiquidatableCash -State $State -PlayerId $PlayerId }
            if ($ceiling -ge $min) {
                [void]$out.Add(@{ Kind = 'Bid'; PlayerId = $PlayerId; Amount = $min; MaxAmount = $ceiling })
            }
            [void]$out.Add(@{ Kind = 'PassBid'; PlayerId = $PlayerId })
        }

        'AwaitDebt' {
            # Bankruptcy is always available: without it a player who cannot
            # raise the money would have no legal move at all.
            [void]$out.Add(@{ Kind = 'DeclareBankruptcy'; PlayerId = $PlayerId })
        }

        'AwaitTradeResponse' {
            [void]$out.Add(@{ Kind = 'RespondTrade'; PlayerId = $PlayerId; Accept = $true })
            [void]$out.Add(@{ Kind = 'RespondTrade'; PlayerId = $PlayerId; Accept = $false })
        }

        'AwaitEndTurn' {
            [void]$out.Add(@{ Kind = 'EndTurn'; PlayerId = $PlayerId })
        }
    }

    # Property management is legal in any phase where the acting player is not
    # mid-decision on something else. One pass over the deed table covers all
    # four management kinds; this runs on every AI decision, so it avoids the
    # three separate owned-property scans the obvious version would do.
    if ($script:RonManagementPhases -contains $phase) {
        $bi = $script:RonBoardIndex
        if ($null -eq $bi) { $bi = Get-RonBoardIndex }
        $props = $State.Properties
        foreach ($i in $bi.Deeds) {
            if ($props[$i].OwnerId -ne $PlayerId) { continue }
            if (Test-RonCanBuildHouse -State $State -PlayerId $PlayerId -SpaceIndex $i) {
                [void]$out.Add(@{ Kind = 'BuildHouse'; PlayerId = $PlayerId; SpaceIndex = $i; Amount = $bi.HouseCost[$i] })
            }
            if ($props[$i].Houses -gt 0 -and (Test-RonCanSellBuilding -State $State -PlayerId $PlayerId -SpaceIndex $i)) {
                [void]$out.Add(@{ Kind = 'SellBuilding'; PlayerId = $PlayerId; SpaceIndex = $i; Amount = [int]($bi.HouseCost[$i] / 2) })
            }
            if (Test-RonCanMortgage -State $State -PlayerId $PlayerId -SpaceIndex $i) {
                [void]$out.Add(@{ Kind = 'Mortgage'; PlayerId = $PlayerId; SpaceIndex = $i; Amount = $bi.Mortgage[$i] })
            }
            elseif (Test-RonCanUnmortgage -State $State -PlayerId $PlayerId -SpaceIndex $i) {
                [void]$out.Add(@{ Kind = 'Unmortgage'; PlayerId = $PlayerId; SpaceIndex = $i; Amount = (Get-RonUnmortgageCost -Index $i -Rules $State.Rules) })
            }
        }
    }

    return $out.ToArray()
}

# --- validation ------------------------------------------------------------

function Test-RonActionLegal {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][object]$Action,
        [ref]$Reason = ([ref]$script:RonReasonSink)
    )
    if ($State.IsOver) { return (Set-RonReason $Reason 'Error.WrongPhase' 'GameOver') }

    $kind     = [string](Get-RonActionField $Action 'Kind' '')
    $playerId = [int](Get-RonActionField $Action 'PlayerId' -1)
    $index    = [int](Get-RonActionField $Action 'SpaceIndex' -1)
    $amount   = [int](Get-RonActionField $Action 'Amount' 0)
    $phase    = $State.Turn.Phase
    $acting   = Get-RonActingPlayerId -State $State

    if ($playerId -lt 0 -or $playerId -ge $State.Players.Length) { return (Set-RonReason $Reason 'Error.NotYourTurn') }
    if ($State.GetPlayer($playerId).IsBankrupt)                  { return (Set-RonReason $Reason 'Error.NotYourTurn') }
    if ($playerId -ne $acting)                                   { return (Set-RonReason $Reason 'Error.NotYourTurn') }

    switch ($kind) {

        'Roll'        { if ($phase -ne 'AwaitRoll') { return (Set-RonReason $Reason 'Error.WrongPhase' $phase) }; return $true }
        'EndTurn'     { if ($phase -ne 'AwaitEndTurn') { return (Set-RonReason $Reason 'Error.WrongPhase' $phase) }; return $true }
        'JailRoll'    { if ($phase -ne 'AwaitJailChoice') { return (Set-RonReason $Reason 'Error.WrongPhase' $phase) }; return $true }

        'PayJailFine' {
            if ($phase -ne 'AwaitJailChoice') { return (Set-RonReason $Reason 'Error.WrongPhase' $phase) }
            if ($State.GetPlayer($playerId).Cash -lt [int](Get-RonBoard).JailFine) { return (Set-RonReason $Reason 'Error.NotEnoughCash') }
            return $true
        }

        'UseJailCard' {
            if ($phase -ne 'AwaitJailChoice') { return (Set-RonReason $Reason 'Error.WrongPhase' $phase) }
            if ($State.GetPlayer($playerId).JailCards -le 0) { return (Set-RonReason $Reason 'Error.TradeInvalid') }
            return $true
        }

        'BuyProperty' {
            if ($phase -ne 'AwaitBuyDecision') { return (Set-RonReason $Reason 'Error.WrongPhase' $phase) }
            if ($index -ne $State.Turn.PendingSpaceIndex) { return (Set-RonReason $Reason 'Error.WrongPhase' $phase) }
            if ($State.Properties[$index].OwnerId -ge 0) { return (Set-RonReason $Reason 'Error.NotOwner') }
            if ($State.GetPlayer($playerId).Cash -lt (Get-RonSpacePrice $index)) { return (Set-RonReason $Reason 'Error.NotEnoughCash') }
            return $true
        }

        'DeclineProperty' {
            if ($phase -ne 'AwaitBuyDecision') { return (Set-RonReason $Reason 'Error.WrongPhase' $phase) }
            return $true
        }

        'Bid' {
            if ($phase -ne 'AwaitAuction') { return (Set-RonReason $Reason 'Error.WrongPhase' $phase) }
            return (Test-RonCanBid -State $State -PlayerId $playerId -Amount $amount -Reason $Reason)
        }

        'PassBid' {
            if ($phase -ne 'AwaitAuction') { return (Set-RonReason $Reason 'Error.WrongPhase' $phase) }
            return $true
        }

        'DeclareBankruptcy' {
            if ($phase -ne 'AwaitDebt') { return (Set-RonReason $Reason 'Error.NothingToSettle') }
            return $true
        }

        'RespondTrade' {
            if ($phase -ne 'AwaitTradeResponse') { return (Set-RonReason $Reason 'Error.WrongPhase' $phase) }
            return $true
        }

        'CounterTrade' {
            if ($phase -ne 'AwaitTradeResponse') { return (Set-RonReason $Reason 'Error.WrongPhase' $phase) }
            $pending = $State.Turn.Trade
            if ($null -eq $pending) { return (Set-RonReason $Reason 'Error.WrongPhase' $phase) }
            # Only the player being asked may counter, and only back to the
            # player who asked - otherwise a counter is a way to propose a
            # trade out of turn to somebody else entirely.
            if ($playerId -ne $pending.ToId) { return (Set-RonReason $Reason 'Error.NotYourTurn') }
            if ($State.Turn.TradesProposed -ge $script:RonMaxTradeChain) {
                return (Set-RonReason $Reason 'Error.TradeChainTooLong')
            }
            $offer = [TradeOffer]::FromData((Get-RonActionField $Action 'Offer' $null))
            if ($offer.FromId -ne $playerId -or $offer.ToId -ne $pending.FromId) {
                return (Set-RonReason $Reason 'Error.TradeInvalid')
            }
            return (Test-RonTradeLegal -State $State -Offer $offer -Reason $Reason)
        }

        'BuildHouse' {
            if ($script:RonManagementPhases -notcontains $phase) { return (Set-RonReason $Reason 'Error.WrongPhase' $phase) }
            return (Test-RonCanBuildHouse -State $State -PlayerId $playerId -SpaceIndex $index -Reason $Reason)
        }

        'SellBuilding' {
            if ($script:RonManagementPhases -notcontains $phase) { return (Set-RonReason $Reason 'Error.WrongPhase' $phase) }
            return (Test-RonCanSellBuilding -State $State -PlayerId $playerId -SpaceIndex $index -Reason $Reason)
        }

        'Mortgage' {
            if ($script:RonManagementPhases -notcontains $phase) { return (Set-RonReason $Reason 'Error.WrongPhase' $phase) }
            return (Test-RonCanMortgage -State $State -PlayerId $playerId -SpaceIndex $index -Reason $Reason)
        }

        'Unmortgage' {
            if ($script:RonManagementPhases -notcontains $phase) { return (Set-RonReason $Reason 'Error.WrongPhase' $phase) }
            return (Test-RonCanUnmortgage -State $State -PlayerId $playerId -SpaceIndex $index -Reason $Reason)
        }

        'ProposeTrade' {
            if ($script:RonManagementPhases -notcontains $phase) { return (Set-RonReason $Reason 'Error.WrongPhase' $phase) }
            $offer = [TradeOffer]::FromData((Get-RonActionField $Action 'Offer' $null))
            if ($offer.FromId -ne $playerId) { return (Set-RonReason $Reason 'Error.TradeInvalid') }
            return (Test-RonTradeLegal -State $State -Offer $offer -Reason $Reason)
        }
    }
    return (Set-RonReason $Reason 'Error.WrongPhase' $phase)
}

# --- application -----------------------------------------------------------
#
# Validates, applies, and returns @{ Ok; Version; Events; Reason }. Never
# throws for an illegal action - a laggy client or a confused AI must get a
# clean rejection, not an exception.
function Invoke-RonAction {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][object]$Action,
        [switch]$AssertInvariants
    )
    $why = ''
    if (-not (Test-RonActionLegal -State $State -Action $Action -Reason ([ref]$why))) {
        return @{ Ok = $false; Version = $State.Version; Events = @(); Reason = $why }
    }

    $events   = New-Object System.Collections.ArrayList
    $kind     = [string](Get-RonActionField $Action 'Kind' '')
    $playerId = [int](Get-RonActionField $Action 'PlayerId' -1)
    $index    = [int](Get-RonActionField $Action 'SpaceIndex' -1)
    $amount   = [int](Get-RonActionField $Action 'Amount' 0)

    switch ($kind) {

        'Roll'        { Invoke-RonRoll        -State $State -Events $events }
        'JailRoll'    { Invoke-RonJailRoll    -State $State -Events $events }
        'PayJailFine' { Invoke-RonPayJailFine -State $State -Events $events }
        'UseJailCard' { Invoke-RonUseJailCard -State $State -Events $events }
        'EndTurn'     { Complete-RonTurn      -State $State -Events $events }

        'BuyProperty' {
            Invoke-RonBuyProperty -State $State -PlayerId $playerId -SpaceIndex $index -Events $events
            $State.Turn.PendingSpaceIndex = -1
            $State.Turn.Phase = 'Resolving'
        }

        'DeclineProperty' {
            $State.Turn.PendingSpaceIndex = -1
            if ($State.RuleOn('DisableAuctions')) {
                # House rule: the deed simply stays with the bank.
                $State.Turn.Phase = 'Resolving'
            }
            else {
                # Bidding opens with the player to the decliner's left.
                $first = Get-RonNextSeatId -State $State -AfterPlayerId $playerId
                Start-RonAuction -State $State -SpaceIndex $index -Events $events -FirstBidderId $first
            }
        }

        'Bid'     { Invoke-RonAuctionBid  -State $State -PlayerId $playerId -Amount $amount -Events $events }
        'PassBid' { Invoke-RonAuctionPass -State $State -PlayerId $playerId -Events $events }

        'BuildHouse'   { [void](Invoke-RonBuildHouse   -State $State -PlayerId $playerId -SpaceIndex $index -Events $events) }
        'SellBuilding' { [void](Invoke-RonSellBuilding -State $State -PlayerId $playerId -SpaceIndex $index -Events $events) }
        'Mortgage'     { [void](Invoke-RonMortgage     -State $State -PlayerId $playerId -SpaceIndex $index -Events $events) }
        'Unmortgage'   { [void](Invoke-RonUnmortgage   -State $State -PlayerId $playerId -SpaceIndex $index -Events $events) }

        'ProposeTrade' {
            $offer = [TradeOffer]::FromData((Get-RonActionField $Action 'Offer' $null))
            Start-RonTradeOffer -State $State -Offer $offer -Events $events
        }

        'RespondTrade' {
            $accept = [bool](Get-RonActionField $Action 'Accept' $false)
            Invoke-RonTradeResponse -State $State -Accept $accept -Events $events
        }

        'CounterTrade' {
            $offer = [TradeOffer]::FromData((Get-RonActionField $Action 'Offer' $null))
            Invoke-RonTradeCounter -State $State -Offer $offer -Events $events
        }

        'DeclareBankruptcy' {
            Invoke-RonDeclareBankruptcy -State $State -PlayerId $playerId -Events $events
        }
    }

    # Management actions leave the phase alone; everything else has already
    # parked at 'Resolving' or at a phase that is waiting on a player.
    Step-RonTurn -State $State -Events $events

    $State.Version += 1
    if ($AssertInvariants) { Assert-RonInvariant -State $State }

    return @{ Ok = $true; Version = $State.Version; Events = $events.ToArray(); Reason = '' }
}

# Convenience for tests and the simulator: apply and throw on rejection.
function Invoke-RonActionOrThrow {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][object]$Action,
        [switch]$AssertInvariants
    )
    $r = Invoke-RonAction -State $State -Action $Action -AssertInvariants:$AssertInvariants
    if (-not $r.Ok) {
        throw ("Action '{0}' by player {1} rejected: {2}" -f (Get-RonActionField $Action 'Kind' '?'), (Get-RonActionField $Action 'PlayerId' '?'), $r.Reason)
    }
    return $r
}
