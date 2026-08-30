#
# Ronopoly - the AI decision dispatcher.
#
# One implementation per decision, parameterised by the profile table. The
# driver calls this repeatedly: a bot may build a house, then build another,
# then finally roll - one action per call, exactly as a human would click.
#

function Get-RonAiAction {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [int]$PlayerId = -1
    )
    if ($State.IsOver) { return $null }
    if ($PlayerId -lt 0) { $PlayerId = Get-RonActingPlayerId -State $State }

    $legal = @(Get-RonLegalActions -State $State -PlayerId $PlayerId)
    if ($legal.Count -eq 0) { return $null }

    $player  = $State.GetPlayer($PlayerId)
    $profile = Get-RonAiProfile $player.AiProfile
    $rng     = Get-RonAiRng -State $State -PlayerId $PlayerId

    # An Easy bot occasionally just does something legal instead of something
    # good. Far more convincing than simply being worse at arithmetic.
    if ([double]$profile.MistakeRate -gt 0 -and $rng.NextDouble() -lt [double]$profile.MistakeRate) {
        return $legal[$rng.NextInt($legal.Count)]
    }

    switch ($State.Turn.Phase) {
        'AwaitBuyDecision'   { return (Get-RonAiBuyDecision   -State $State -PlayerId $PlayerId -Legal $legal -Profile $profile) }
        'AwaitAuction'       { return (Get-RonAiBidDecision   -State $State -PlayerId $PlayerId -Legal $legal -Profile $profile) }
        'AwaitJailChoice'    { return (Get-RonAiJailDecision  -State $State -PlayerId $PlayerId -Legal $legal -Profile $profile) }
        'AwaitDebt'          { return (Get-RonAiDebtDecision  -State $State -PlayerId $PlayerId -Legal $legal -Profile $profile) }
        'AwaitTradeResponse' { return (Get-RonAiTradeResponse -State $State -PlayerId $PlayerId -Legal $legal) }
    }
    # AwaitRoll / AwaitEndTurn: manage the portfolio, then get on with it.
    return (Get-RonAiTurnAction -State $State -PlayerId $PlayerId -Legal $legal -Profile $profile)
}

function Select-RonAction {
    param([object[]]$Legal, [Parameter(Mandatory)][string]$Kind, [int]$SpaceIndex = -1)
    foreach ($a in $Legal) {
        if ($a.Kind -ne $Kind) { continue }
        if ($SpaceIndex -ge 0 -and [int]$a.SpaceIndex -ne $SpaceIndex) { continue }
        return $a
    }
    return $null
}

# --- buy / decline ---------------------------------------------------------

function Get-RonAiBuyDecision {
    param([GameState]$State, [int]$PlayerId, [object[]]$Legal, [hashtable]$Profile)
    $buy = Select-RonAction -Legal $Legal -Kind 'BuyProperty'
    $decline = Select-RonAction -Legal $Legal -Kind 'DeclineProperty'
    if ($null -eq $buy) { return $decline }

    $index   = [int]$buy.SpaceIndex
    $price   = [int]$buy.Amount
    $value   = Get-RonPropertyValue -State $State -PlayerId $PlayerId -SpaceIndex $index
    $reserve = Get-RonCashReserveTarget -State $State -PlayerId $PlayerId
    $cash    = $State.GetPlayer($PlayerId).Cash

    if (($cash - $price) -lt $reserve) { return $decline }
    if ($value -lt ($price * [double]$Profile.BuyThreshold)) { return $decline }
    return $buy
}

# --- auction ---------------------------------------------------------------

function Get-RonAiBidDecision {
    param([GameState]$State, [int]$PlayerId, [object[]]$Legal, [hashtable]$Profile)
    $bid  = Select-RonAction -Legal $Legal -Kind 'Bid'
    $pass = Select-RonAction -Legal $Legal -Kind 'PassBid'
    if ($null -eq $bid) { return $pass }

    $index   = $State.Turn.Auction.SpaceIndex
    $value   = Get-RonPropertyValue -State $State -PlayerId $PlayerId -SpaceIndex $index
    $ceiling = [int]($value * [double]$Profile.Aggression)

    if ($Profile.DenialBids) {
        # A lot that would complete an OPPONENT's monopoly is worth bidding up:
        # it drains their cash and denies the group. Stop just below the point
        # where actually winning it would hurt.
        $threat = 0
        foreach ($other in $State.ActivePlayers()) {
            if ($other.Id -eq $PlayerId) { continue }
            $v = Get-RonPropertyValue -State $State -PlayerId $other.Id -SpaceIndex $index
            if ($v -gt $threat) { $threat = $v }
        }
        $denial = [int]($threat * 0.9)
        if ($denial -gt $ceiling) { $ceiling = $denial }
    }

    $reserve    = [int]((Get-RonCashReserveTarget -State $State -PlayerId $PlayerId) * 0.5)
    $affordable = $State.GetPlayer($PlayerId).Cash - $reserve
    if ($ceiling -gt $affordable) { $ceiling = $affordable }
    if ([int]$bid.Amount -gt $ceiling) { return $pass }
    return $bid
}

# --- jail ------------------------------------------------------------------

function Get-RonAiJailDecision {
    param([GameState]$State, [int]$PlayerId, [object[]]$Legal, [hashtable]$Profile)
    $card = Select-RonAction -Legal $Legal -Kind 'UseJailCard'
    $fine = Select-RonAction -Legal $Legal -Kind 'PayJailFine'
    $roll = Select-RonAction -Legal $Legal -Kind 'JailRoll'

    # Early on the board is cheap and full of unowned deeds, so getting out is
    # worth the 50. Later, with hotels everywhere, jail is the safest square on
    # the board and the bot should sit tight and roll for doubles.
    $danger = Get-RonDevelopedRentDensity -State $State -PlayerId $PlayerId
    $free   = Get-RonUnownedFraction -State $State
    $stay   = ($danger + [double]$Profile.JailStayBias) -gt ($free + 0.25)

    if (-not $stay) {
        if ($null -ne $card) { return $card }
        if ($null -ne $fine) { return $fine }
    }
    if ($null -ne $roll) { return $roll }
    if ($null -ne $card) { return $card }
    return $fine
}

# --- debt ------------------------------------------------------------------

function Get-RonAiDebtDecision {
    param([GameState]$State, [int]$PlayerId, [object[]]$Legal, [hashtable]$Profile)
    # If the money simply is not there, stop stalling.
    if (-not (Test-RonCanSurviveDebt -State $State)) {
        return (Select-RonAction -Legal $Legal -Kind 'DeclareBankruptcy')
    }

    # Mortgage first, least useful deed first, and never touch a monopoly while
    # anything else can still be sold.
    $mortgages = @($Legal | Where-Object { $_.Kind -eq 'Mortgage' })
    if ($mortgages.Count -gt 0) {
        $best = $null
        $bestScore = [double]::MaxValue
        foreach ($m in $mortgages) {
            $score = [double](Get-RonPropertyValue -State $State -PlayerId $PlayerId -SpaceIndex ([int]$m.SpaceIndex))
            $group = Get-RonSpaceGroup ([int]$m.SpaceIndex)
            if ($group -and (Test-RonHasMonopoly -State $State -PlayerId $PlayerId -Group $group)) { $score *= 10.0 }
            if ($score -lt $bestScore) { $bestScore = $score; $best = $m }
        }
        if ($null -ne $best) { return $best }
    }

    # Buildings go last: they sell back at half price, which makes them the
    # most expensive way to raise cash.
    $sells = @($Legal | Where-Object { $_.Kind -eq 'SellBuilding' })
    if ($sells.Count -gt 0) {
        $worst = $null
        $worstPriority = [double]::MaxValue
        foreach ($s in $sells) {
            $pr = Get-RonBuildPriority -State $State -SpaceIndex ([int]$s.SpaceIndex)
            if ($pr -lt $worstPriority) { $worstPriority = $pr; $worst = $s }
        }
        if ($null -ne $worst) { return $worst }
    }

    return (Select-RonAction -Legal $Legal -Kind 'DeclareBankruptcy')
}

# --- trade response --------------------------------------------------------

function Get-RonAiTradeResponse {
    param([GameState]$State, [int]$PlayerId, [object[]]$Legal)
    $offer = $State.Turn.Trade
    $accept = Test-RonShouldAcceptTrade -State $State -PlayerId $PlayerId -Offer $offer

    # A bot that only ever says yes or no is a bot you stop bothering to trade
    # with. Before refusing, see whether a price exists that suits both sides
    # and name it. The engine caps how many times one offer may cross the
    # table, so this cannot become a loop.
    if (-not $accept) {
        $counter = Find-RonTradeCounter -State $State -PlayerId $PlayerId -Offer $offer
        if ($null -ne $counter) {
            return @{ Kind = 'CounterTrade'; PlayerId = $PlayerId; Offer = $counter.ToData() }
        }
    }

    foreach ($a in $Legal) {
        if ($a.Kind -eq 'RespondTrade' -and ([bool]$a.Accept -eq $accept)) { return $a }
    }
    return $Legal[0]
}

# --- ordinary turn ---------------------------------------------------------

function Get-RonAiTurnAction {
    param([GameState]$State, [int]$PlayerId, [object[]]$Legal, [hashtable]$Profile)
    $cash    = $State.GetPlayer($PlayerId).Cash
    $reserve = Get-RonCashReserveTarget -State $State -PlayerId $PlayerId
    $spare   = $cash - [int]($reserve * [double]$Profile.BuildFactor)

    # 1. Build, best return on capital first.
    if ($spare -gt 0) {
        $builds = @($Legal | Where-Object { $_.Kind -eq 'BuildHouse' -and [int]$_.Amount -le $spare })
        if ($builds.Count -gt 0) {
            $best = $null
            $bestPriority = 0.0
            foreach ($b in $builds) {
                $pr = Get-RonBuildPriority -State $State -SpaceIndex ([int]$b.SpaceIndex)
                if ($pr -gt $bestPriority) { $bestPriority = $pr; $best = $b }
            }
            if ($null -ne $best) { return $best }
        }
    }

    # 2. Lift mortgages once comfortable - a mortgaged deed earns nothing.
    if ($spare -gt 0) {
        $lifts = @($Legal | Where-Object { $_.Kind -eq 'Unmortgage' -and [int]$_.Amount -le $spare })
        if ($lifts.Count -gt 0) { return $lifts[0] }
    }

    # 3. Try a trade, capped per turn so a refused offer cannot loop forever.
    if ($Profile.ProposeTrades -and $State.Turn.TradesProposed -lt 2) {
        if ($null -ne (Select-RonAction -Legal $Legal -Kind 'EndTurn')) {
            $offer = Find-RonTradeOffer -State $State -PlayerId $PlayerId
            if ($null -ne $offer) {
                return @{ Kind = 'ProposeTrade'; PlayerId = $PlayerId; Offer = $offer.ToData() }
            }
        }
    }

    $roll = Select-RonAction -Legal $Legal -Kind 'Roll'
    if ($null -ne $roll) { return $roll }
    $end = Select-RonAction -Legal $Legal -Kind 'EndTurn'
    if ($null -ne $end) { return $end }
    return $Legal[0]
}

# Picks a uniformly random legal action. Used by the M1 shakedown simulation:
# a bot with no strategy at all still exercises every rule path, and any
# exception it triggers is a genuine engine bug rather than an AI bug.
function Get-RonRandomAction {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][RonRng]$Rng,
        [int]$PlayerId = -1
    )
    if ($PlayerId -lt 0) { $PlayerId = Get-RonActingPlayerId -State $State }
    $legal = @(Get-RonLegalActions -State $State -PlayerId $PlayerId)
    if ($legal.Count -eq 0) { return $null }
    return $legal[$Rng.NextInt($legal.Count)]
}
