#
# Ronopoly - trade evaluation.
#
# The key move is to evaluate the SAME offer twice: once from my seat and once
# from the opponent's, using the identical valuation function. That is what
# lets the bot construct deals the other side will actually take, instead of
# lopsided offers that always get refused.
#

$script:RonTradeCandidateCap = 20   # hard performance guard on the search

# Extra penalty for handing an opponent the deed that completes their group,
# as a multiple of what that deed is worth to me.
#
# This is deliberately SMALL. Get-RonPropertyValue already multiplies a deed by
# 1.8 when an opponent is one short, so the denial cost is mostly priced in
# already; the original 2.0 here double-counted it so severely that no
# monopoly-completing trade was ever mutually positive - and since those are
# the only trades the proposer searches for, the whole trading module was
# effectively dead code. 0.5 keeps a real bias against giving a monopoly away
# while leaving genuinely good two-sided deals reachable.
$script:RonTradeDenialPenalty = 0.5

# Cash sweeteners tried, as a fraction of the proposer's spare cash. The window
# where both sides gain can be narrow, so a coarse two-step search walks past
# workable deals.
$script:RonTradeCashSteps = @(0.0, 0.15, 0.3, 0.5)

# Net worth of an offer to one side, in pounds. Direction is always expressed
# from the PROPOSER's point of view in the offer itself, so this flips the
# signs when evaluating for the recipient.
function Get-RonTradeGain {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][TradeOffer]$Offer,
        [Parameter(Mandatory)][int]$ForPlayerId
    )
    if ($ForPlayerId -eq $Offer.FromId) {
        $incoming = $Offer.GetProperties
        $outgoing = $Offer.GiveProperties
        $cash = $Offer.GetCash - $Offer.GiveCash
        $other = $Offer.ToId
    }
    else {
        $incoming = $Offer.GiveProperties
        $outgoing = $Offer.GetProperties
        $cash = $Offer.GiveCash - $Offer.GetCash
        $other = $Offer.FromId
    }

    $gain = [double]$cash
    foreach ($i in $incoming) { $gain += Get-RonPropertyValue -State $State -PlayerId $ForPlayerId -SpaceIndex $i }
    foreach ($i in $outgoing) { $gain -= Get-RonPropertyValue -State $State -PlayerId $ForPlayerId -SpaceIndex $i }

    # Handing an opponent a monopoly costs far more than the deed is worth.
    foreach ($i in $outgoing) {
        $group = Get-RonSpaceGroup $i
        if (-not $group) { continue }
        $members = Get-RonGroupIndices $group
        $theirs = 0
        foreach ($m in $members) {
            if ($m -eq $i) { $theirs++ }
            elseif ($State.Properties[$m].OwnerId -eq $other) { $theirs++ }
        }
        if ($theirs -eq $members.Length) {
            $gain -= (Get-RonPropertyValue -State $State -PlayerId $ForPlayerId -SpaceIndex $i) * $script:RonTradeDenialPenalty
        }
    }
    return [int][math]::Round($gain)
}

function Test-RonShouldAcceptTrade {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [Parameter(Mandatory)][TradeOffer]$Offer
    )
    $profile = Get-RonAiProfile $State.GetPlayer($PlayerId).AiProfile
    if (-not $profile.AcceptTrades) { return $false }
    return ((Get-RonTradeGain -State $State -Offer $Offer -ForPlayerId $PlayerId) -gt 0)
}

# The answer to a bad offer that is not simply "no".
#
# The shape of the deal is left exactly as proposed - the same deeds, the same
# jail cards - and only the CASH moves, to the smallest number that puts this
# side in front. That is deliberate: the proposer already searched for a swap
# it wanted, so re-searching from scratch usually just produces a different
# deal it will refuse. Naming a price keeps the negotiation on the one term
# that has a continuum of answers.
function Find-RonTradeCounter {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [Parameter(Mandatory)][TradeOffer]$Offer
    )
    $me = $State.GetPlayer($PlayerId)
    $profile = Get-RonAiProfile $me.AiProfile
    if (-not $profile.ProposeTrades) { return $null }
    if ($PlayerId -ne $Offer.ToId) { return $null }
    if ($State.Turn.TradesProposed -ge (Get-RonMaxTradeChain)) { return $null }

    $myGain = Get-RonTradeGain -State $State -Offer $Offer -ForPlayerId $PlayerId
    if ($myGain -gt 0) { return $null }        # nothing to haggle over - accept it

    # Every pound clawed back comes out of what the deal is worth to THEM, so
    # if the gap is wider than their whole gain no price exists and this is a
    # straight refusal rather than a negotiation.
    $need = (-$myGain) + 1
    $theirGain = Get-RonTradeGain -State $State -Offer $Offer -ForPlayerId $Offer.FromId
    if (($theirGain - $need) -le 0) { return $null }

    $counter = [TradeOffer]::new()
    $counter.FromId = $PlayerId
    $counter.ToId   = $Offer.FromId
    $counter.GiveProperties = @($Offer.GetProperties)
    $counter.GetProperties  = @($Offer.GiveProperties)
    $counter.GiveJailCards  = $Offer.GetJailCards
    $counter.GetJailCards   = $Offer.GiveJailCards

    # Cash, always stated from this side: what the original moved towards me,
    # plus the shortfall. A negative result means I am the one paying.
    $net = ($Offer.GiveCash - $Offer.GetCash) + $need
    if ($net -ge 0) { $counter.GetCash = $net }
    else {
        $reserve = Get-RonCashReserveTarget -State $State -PlayerId $PlayerId
        $spare = $me.Cash - $reserve
        if ((-$net) -gt $spare) { return $null }
        $counter.GiveCash = -$net
    }

    if (-not (Test-RonTradeLegal -State $State -Offer $counter)) { return $null }
    return $counter
}

# Looks for a deed held by someone else that would complete one of my groups,
# and builds a two-sided offer around it: a deed they need plus a cash
# sweetener, sized so the deal is genuinely positive for both of us.
function Find-RonTradeOffer {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId
    )
    $me = $State.GetPlayer($PlayerId)
    $profile = Get-RonAiProfile $me.AiProfile
    if (-not $profile.ProposeTrades) { return $null }

    $reserve = Get-RonCashReserveTarget -State $State -PlayerId $PlayerId
    $spare   = $me.Cash - $reserve
    if ($spare -lt 0) { $spare = 0 }

    $best = $null
    $bestGain = 0
    $examined = 0

    foreach ($want in (Get-RonDeedIndices)) {
        if ($examined -ge $script:RonTradeCandidateCap) { break }
        $deed = $State.Properties[$want]
        if ($deed.OwnerId -lt 0 -or $deed.OwnerId -eq $PlayerId) { continue }
        if ($State.GetPlayer($deed.OwnerId).IsBankrupt) { continue }

        # Only chase deeds that would complete a group for me.
        $group = Get-RonSpaceGroup $want
        if (-not $group) { continue }
        $members = Get-RonGroupIndices $group
        $mine = 0
        foreach ($m in $members) { if ($State.Properties[$m].OwnerId -eq $PlayerId) { $mine++ } }
        if ($mine -ne ($members.Length - 1)) { continue }

        # A colour group with buildings anywhere cannot be traded at all.
        if (Test-RonGroupHasBuildings -State $State -Group $group) { continue }

        $examined++
        $themId = $deed.OwnerId

        # Valuations that do not vary across the inner loops are hoisted out.
        # Recomputing them per combination made this the single most expensive
        # function in the engine, at ~10 ms a call.
        $wantMine   = Get-RonPropertyValue -State $State -PlayerId $PlayerId -SpaceIndex $want
        $wantTheirs = Get-RonPropertyValue -State $State -PlayerId $themId   -SpaceIndex $want
        # They are handing me a monopoly, and they know it.
        $wantPenaltyForThem = $wantTheirs * $script:RonTradeDenialPenalty

        # Deeds I can spare: not in the group I am chasing, not part of a
        # monopoly of mine, and not in a group carrying buildings.
        $offerables = New-Object System.Collections.ArrayList
        [void]$offerables.Add(-1)      # cash-only offer
        foreach ($give in (Get-RonOwnedIndices -State $State -PlayerId $PlayerId)) {
            $gGroup = Get-RonSpaceGroup $give
            if ($gGroup -eq $group) { continue }
            if (Test-RonHasMonopoly -State $State -PlayerId $PlayerId -Group $gGroup) { continue }
            if (Test-RonGroupHasBuildings -State $State -Group $gGroup) { continue }
            [void]$offerables.Add($give)
            if ($offerables.Count -ge 6) { break }
        }

        foreach ($give in $offerables) {
            $giveMine = 0
            $giveTheirs = 0
            $givePenalty = 0
            if ($give -ge 0) {
                $giveMine   = Get-RonPropertyValue -State $State -PlayerId $PlayerId -SpaceIndex $give
                $giveTheirs = Get-RonPropertyValue -State $State -PlayerId $themId   -SpaceIndex $give
                # Would handing this over complete a group for THEM?
                if (Test-RonSpaceInMonopolyAfterGift -State $State -SpaceIndex $give -NewOwnerId $themId) {
                    $givePenalty = $giveMine * $script:RonTradeDenialPenalty
                }
            }

            foreach ($cashStep in $script:RonTradeCashSteps) {
                $cash = [int]($spare * $cashStep)
                $myGain    = $wantMine - $giveMine - $givePenalty - $cash
                $theirGain = $giveTheirs - $wantTheirs - $wantPenaltyForThem + $cash
                # Only genuinely win-win deals; anything else just wastes a turn.
                if ($myGain -le 0 -or $theirGain -le 0) { continue }
                if ($myGain -le $bestGain) { continue }

                $offer = [TradeOffer]::new()
                $offer.FromId = $PlayerId
                $offer.ToId   = $themId
                $offer.GetProperties = @($want)
                if ($give -ge 0) { $offer.GiveProperties = @($give) }
                $offer.GiveCash = $cash
                if (-not (Test-RonTradeLegal -State $State -Offer $offer)) { continue }
                $bestGain = $myGain
                $best = $offer
            }
        }
    }
    return $best
}

# Would giving this deed to NewOwnerId complete a colour group for them?
function Test-RonSpaceInMonopolyAfterGift {
    param([GameState]$State, [int]$SpaceIndex, [int]$NewOwnerId)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    $members = $bi.GroupOf[$SpaceIndex]
    if ($members.Length -eq 0) { return $false }
    $props = $State.Properties
    foreach ($i in $members) {
        if ($i -eq $SpaceIndex) { continue }
        if ($props[$i].OwnerId -ne $NewOwnerId) { return $false }
    }
    return $true
}
