#
# Ronopoly - trading.
#
# An offer is validated in full and only then applied, never interleaved, so a
# rejected clause can never leave half a trade behind.
#

# How many times one negotiation may change hands inside a single turn -
# the opening offer plus every counter. Haggling is the point, but two bots
# volleying an offer forever is not, and neither is a turn that never ends.
$script:RonMaxTradeChain = 6

function Get-RonMaxTradeChain { return $script:RonMaxTradeChain }

function Test-RonTradeLegal {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][TradeOffer]$Offer,
        [ref]$Reason = ([ref]$script:RonReasonSink)
    )
    if ($Offer.FromId -eq $Offer.ToId) { return (Set-RonReason $Reason 'Error.SelfTrade') }
    if ($Offer.IsEmpty())              { return (Set-RonReason $Reason 'Error.TradeInvalid') }

    $from = $State.GetPlayer($Offer.FromId)
    $to   = $State.GetPlayer($Offer.ToId)
    if ($from.IsBankrupt -or $to.IsBankrupt) { return (Set-RonReason $Reason 'Error.TradeInvalid') }

    if ($Offer.GiveCash -lt 0 -or $Offer.GetCash -lt 0)           { return (Set-RonReason $Reason 'Error.TradeInvalid') }
    if ($Offer.GiveJailCards -lt 0 -or $Offer.GetJailCards -lt 0) { return (Set-RonReason $Reason 'Error.TradeInvalid') }
    if ($Offer.GiveCash -gt $from.Cash -or $Offer.GetCash -gt $to.Cash) { return (Set-RonReason $Reason 'Error.NotEnoughCash') }
    if ($Offer.GiveJailCards -gt $from.JailCards -or $Offer.GetJailCards -gt $to.JailCards) {
        return (Set-RonReason $Reason 'Error.TradeInvalid')
    }

    foreach ($i in $Offer.GiveProperties) {
        if ($State.Properties[$i].OwnerId -ne $Offer.FromId) { return (Set-RonReason $Reason 'Error.NotOwner') }
    }
    foreach ($i in $Offer.GetProperties) {
        if ($State.Properties[$i].OwnerId -ne $Offer.ToId)   { return (Set-RonReason $Reason 'Error.NotOwner') }
    }

    # No deed may change hands while ANY member of its colour group carries a
    # building - the buildings must be sold back first.
    $all = @($Offer.GiveProperties) + @($Offer.GetProperties)
    foreach ($i in $all) {
        $group = Get-RonSpaceGroup $i
        if ($group -and (Test-RonGroupHasBuildings -State $State -Group $group)) {
            return (Set-RonReason $Reason 'Error.HasBuildings')
        }
    }
    return $true
}

function Invoke-RonTrade {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][TradeOffer]$Offer,
        [System.Collections.ArrayList]$Events = $null
    )
    $why = ''
    if (-not (Test-RonTradeLegal -State $State -Offer $Offer -Reason ([ref]$why))) {
        throw "Invoke-RonTrade: $why"
    }

    if ($Offer.GiveCash -gt 0) { Move-RonCash -State $State -FromId $Offer.FromId -ToId $Offer.ToId -Amount $Offer.GiveCash }
    if ($Offer.GetCash  -gt 0) { Move-RonCash -State $State -FromId $Offer.ToId -ToId $Offer.FromId -Amount $Offer.GetCash }

    $from = $State.GetPlayer($Offer.FromId)
    $to   = $State.GetPlayer($Offer.ToId)
    if ($Offer.GiveJailCards -gt 0) { $from.JailCards -= $Offer.GiveJailCards; $to.JailCards += $Offer.GiveJailCards }
    if ($Offer.GetJailCards  -gt 0) { $to.JailCards  -= $Offer.GetJailCards;  $from.JailCards += $Offer.GetJailCards }

    # Mortgaged deeds carry their 10% interest to whoever receives them. Both
    # sides can owe at once, so the charges go through the pending queue rather
    # than trying to open two debts simultaneously.
    $toOwes   = 0
    $fromOwes = 0
    foreach ($i in $Offer.GiveProperties) {
        $toOwes   += Set-RonPropertyOwner -State $State -SpaceIndex $i -NewOwnerId $Offer.ToId -Events $Events
    }
    foreach ($i in $Offer.GetProperties) {
        $fromOwes += Set-RonPropertyOwner -State $State -SpaceIndex $i -NewOwnerId $Offer.FromId -Events $Events
    }

    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'TradeExecuted' @{ P = $Offer.FromId; P2 = $Offer.ToId; Offer = $Offer.ToData() }))
    }

    if ($toOwes -gt 0) {
        Add-RonPendingPayment -State $State -DebtorId $Offer.ToId -CreditorId -1 -Amount $toOwes -Reason 'mortgage-interest'
    }
    if ($fromOwes -gt 0) {
        Add-RonPendingPayment -State $State -DebtorId $Offer.FromId -CreditorId -1 -Amount $fromOwes -Reason 'mortgage-interest'
    }
    if ($toOwes -gt 0 -or $fromOwes -gt 0) {
        [void](Resolve-RonPendingPayment -State $State -Events $Events)
    }
}

# --- offer flow ------------------------------------------------------------

function Start-RonTradeOffer {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][TradeOffer]$Offer,
        [System.Collections.ArrayList]$Events = $null
    )
    $why = ''
    if (-not (Test-RonTradeLegal -State $State -Offer $Offer -Reason ([ref]$why))) {
        throw "Start-RonTradeOffer: $why"
    }
    $State.Turn.Trade = $Offer
    $State.Turn.TradesProposed += 1
    $State.Turn.PendingDecision = 'trade'
    $State.Turn.Phase = 'AwaitTradeResponse'
    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'TradeOffered' @{ P = $Offer.FromId; P2 = $Offer.ToId; Offer = $Offer.ToData() }))
    }
}

# A counter-offer replaces the offer on the table with the answering player's
# version of it and hands the decision straight back, without ever passing
# through 'Resolving'. That is what keeps it a NEGOTIATION rather than two
# unrelated proposals: the phase never leaves AwaitTradeResponse, so nobody
# gets a turn, a roll or a build in between.
function Invoke-RonTradeCounter {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][TradeOffer]$Offer,
        [System.Collections.ArrayList]$Events = $null
    )
    $pending = $State.Turn.Trade
    if ($null -eq $pending) { throw 'Invoke-RonTradeCounter: no trade is pending' }
    $why = ''
    if (-not (Test-RonTradeLegal -State $State -Offer $Offer -Reason ([ref]$why))) {
        throw "Invoke-RonTradeCounter: $why"
    }
    $State.Turn.Trade = $Offer
    $State.Turn.TradesProposed += 1
    $State.Turn.PendingDecision = 'trade'
    $State.Turn.Phase = 'AwaitTradeResponse'
    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'TradeCountered' @{ P = $Offer.FromId; P2 = $Offer.ToId; Offer = $Offer.ToData() }))
    }
}

function Invoke-RonTradeResponse {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][bool]$Accept,
        [System.Collections.ArrayList]$Events = $null
    )
    $offer = $State.Turn.Trade
    if ($null -eq $offer) { throw 'Invoke-RonTradeResponse: no trade is pending' }
    $State.Turn.Trade = $null
    $State.Turn.PendingDecision = ''

    if ($Accept) {
        # Re-validate: the board may have moved on between offer and answer.
        $why = ''
        if (Test-RonTradeLegal -State $State -Offer $offer -Reason ([ref]$why)) {
            Invoke-RonTrade -State $State -Offer $offer -Events $Events
        }
        elseif ($null -ne $Events) {
            [void]$Events.Add((New-RonEvent 'TradeRejected' @{ P = $offer.FromId; P2 = $offer.ToId; Reason = $why }))
        }
    }
    elseif ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'TradeRejected' @{ P = $offer.FromId; P2 = $offer.ToId }))
    }

    if ($State.Turn.Phase -eq 'AwaitTradeResponse') { $State.Turn.Phase = 'Resolving' }
}
