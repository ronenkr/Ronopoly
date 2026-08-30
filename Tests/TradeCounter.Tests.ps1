. (Join-Path (Split-Path -Parent $PSCommandPath) '_Common.ps1')

# Counter-offers: the answering player replacing the offer on the table with
# their own version of it, without the turn moving on in between.

function New-TestOffer {
    param([int]$From, [int]$To, [int[]]$Give = @(), [int[]]$Get = @(),
          [int]$GiveCash = 0, [int]$GetCash = 0, [int]$GiveJail = 0, [int]$GetJail = 0)
    $o = [TradeOffer]::new()
    $o.FromId = $From
    $o.ToId = $To
    $o.GiveProperties = $Give
    $o.GetProperties = $Get
    $o.GiveCash = $GiveCash
    $o.GetCash = $GetCash
    $o.GiveJailCards = $GiveJail
    $o.GetJailCards = $GetJail
    return $o
}

# Hands a player a Get Out Of Jail Free card the way the game does: taken OUT
# of its deck. Setting JailCards directly leaves three cards in the world and
# the invariant rightly complains.
function Grant-TestJailCard {
    param([Parameter(Mandatory)][GameState]$State, [Parameter(Mandatory)][int]$PlayerId)
    $cards = Get-RonCards
    foreach ($deckName in @('Chance', 'Chest')) {
        $deck = $State.$deckName
        $kept = New-Object System.Collections.ArrayList
        $taken = $false
        foreach ($id in $deck.Cards) {
            if (-not $taken -and $cards.$deckName[$id].Kind -eq 'GetOutOfJailFree') { $taken = $true; continue }
            [void]$kept.Add($id)
        }
        if ($taken) {
            $deck.Cards = [int[]]$kept.ToArray()
            $State.GetPlayer($PlayerId).JailCards += 1
            return
        }
    }
    throw 'Grant-TestJailCard: no jail card left in either deck'
}

# Player 0 holds Old Kent Road, player 1 holds Whitechapel and Angel.
function New-TradeGame {
    $g = New-TestGame -Players 3
    Set-TestOwner -State $g -PlayerId 0 -Indices @(1)
    Set-TestOwner -State $g -PlayerId 1 -Indices @(3, 6)
    return $g
}

Describe 'Trade counter-offers' {

    It 'hands the decision back without leaving the phase' {
        $g = New-TradeGame
        $offer = New-TestOffer -From 0 -To 1 -Give @(1) -Get @(3)
        $r = Invoke-RonAction -State $g -Action @{ Kind = 'ProposeTrade'; PlayerId = 0; Offer = $offer.ToData() }
        Assert-True $r.Ok $r.Reason
        Assert-Equal 'AwaitTradeResponse' $g.Turn.Phase
        Assert-Equal 1 (Get-RonActingPlayerId -State $g)

        # Player 1 wants cash on top of the swap.
        $counter = New-TestOffer -From 1 -To 0 -Give @(3) -Get @(1) -GetCash 75
        $r2 = Invoke-RonAction -State $g -Action @{ Kind = 'CounterTrade'; PlayerId = 1; Offer = $counter.ToData() }
        Assert-True $r2.Ok $r2.Reason
        Assert-Equal 'AwaitTradeResponse' $g.Turn.Phase
        # The ball is back with the original proposer, and the turn has not moved.
        Assert-Equal 0 (Get-RonActingPlayerId -State $g)
        Assert-Equal 0 $g.Turn.CurrentPlayerId
        Assert-Equal 1 $g.Turn.Trade.FromId
        Assert-Equal 75 $g.Turn.Trade.GetCash
    }

    It 'applies the countered terms, not the original ones, on accept' {
        $g = New-TradeGame
        $cash0 = $g.Players[0].Cash
        $cash1 = $g.Players[1].Cash
        $offer = New-TestOffer -From 0 -To 1 -Give @(1) -Get @(3)
        [void](Invoke-RonAction -State $g -Action @{ Kind = 'ProposeTrade'; PlayerId = 0; Offer = $offer.ToData() })
        $counter = New-TestOffer -From 1 -To 0 -Give @(3) -Get @(1) -GetCash 75
        [void](Invoke-RonAction -State $g -Action @{ Kind = 'CounterTrade'; PlayerId = 1; Offer = $counter.ToData() })
        $r = Invoke-RonAction -State $g -Action @{ Kind = 'RespondTrade'; PlayerId = 0; Accept = $true }
        Assert-True $r.Ok $r.Reason

        Assert-Equal 1 $g.Properties[1].OwnerId
        Assert-Equal 0 $g.Properties[3].OwnerId
        Assert-Equal ($cash0 - 75) $g.Players[0].Cash
        Assert-Equal ($cash1 + 75) $g.Players[1].Cash
        Assert-RonInvariant -State $g
    }

    It 'refuses a counter from anyone but the player being asked' {
        $g = New-TradeGame
        $offer = New-TestOffer -From 0 -To 1 -Give @(1) -Get @(3)
        [void](Invoke-RonAction -State $g -Action @{ Kind = 'ProposeTrade'; PlayerId = 0; Offer = $offer.ToData() })

        # Player 2 is not part of this negotiation.
        $meddle = New-TestOffer -From 2 -To 0 -Give @() -Get @(1) -GiveCash 10
        $r = Invoke-RonAction -State $g -Action @{ Kind = 'CounterTrade'; PlayerId = 2; Offer = $meddle.ToData() }
        Assert-True (-not $r.Ok) 'a bystander countered a trade'

        # Nor may the answering player redirect it to somebody else.
        $redirect = New-TestOffer -From 1 -To 2 -Give @(3) -Get @()
        $r2 = Invoke-RonAction -State $g -Action @{ Kind = 'CounterTrade'; PlayerId = 1; Offer = $redirect.ToData() }
        Assert-True (-not $r2.Ok) 'a counter was redirected to a third player'
        Assert-Equal 1 $g.Turn.Trade.ToId
    }

    It 'refuses a counter outside AwaitTradeResponse' {
        $g = New-TradeGame
        $counter = New-TestOffer -From 1 -To 0 -Give @(3) -Get @(1)
        $r = Invoke-RonAction -State $g -Action @{ Kind = 'CounterTrade'; PlayerId = 1; Offer = $counter.ToData() }
        Assert-True (-not $r.Ok) 'a counter was accepted with no trade pending'
    }

    It 'caps the volley so a negotiation cannot run forever' {
        $g = New-TradeGame
        $offer = New-TestOffer -From 0 -To 1 -Give @(1) -Get @(3)
        [void](Invoke-RonAction -State $g -Action @{ Kind = 'ProposeTrade'; PlayerId = 0; Offer = $offer.ToData() })

        $max = Get-RonMaxTradeChain
        $rejected = $false
        for ($i = 0; $i -lt ($max + 3); $i++) {
            $actor = Get-RonActingPlayerId -State $g
            $other = 0
            if ($actor -eq 0) { $other = 1 }
            $give = @(3)
            $get = @(1)
            if ($actor -eq 0) { $give = @(1); $get = @(3) }
            $next = New-TestOffer -From $actor -To $other -Give $give -Get $get -GetCash (10 + $i)
            $r = Invoke-RonAction -State $g -Action @{ Kind = 'CounterTrade'; PlayerId = $actor; Offer = $next.ToData() }
            if (-not $r.Ok) { $rejected = $true; break }
        }
        Assert-True $rejected "the volley never stopped after $max exchanges"
        Assert-Equal $max $g.Turn.TradesProposed
        # And the trade is still answerable - the cap must not deadlock it.
        $actor = Get-RonActingPlayerId -State $g
        $r = Invoke-RonAction -State $g -Action @{ Kind = 'RespondTrade'; PlayerId = $actor; Accept = $false }
        Assert-True $r.Ok $r.Reason
        Assert-True ($g.Turn.Phase -ne 'AwaitTradeResponse') 'the phase never cleared'
    }

    It 'carries jail cards both ways' {
        $g = New-TradeGame
        Grant-TestJailCard -State $g -PlayerId 0
        Grant-TestJailCard -State $g -PlayerId 1
        Assert-RonInvariant -State $g
        $offer = New-TestOffer -From 0 -To 1 -GiveJail 1 -Get @(3)
        [void](Invoke-RonAction -State $g -Action @{ Kind = 'ProposeTrade'; PlayerId = 0; Offer = $offer.ToData() })
        # Answer: I will swap cards instead, and keep Whitechapel.
        $counter = New-TestOffer -From 1 -To 0 -GiveJail 1 -GetJail 1
        $r = Invoke-RonAction -State $g -Action @{ Kind = 'CounterTrade'; PlayerId = 1; Offer = $counter.ToData() }
        Assert-True $r.Ok $r.Reason
        [void](Invoke-RonAction -State $g -Action @{ Kind = 'RespondTrade'; PlayerId = 0; Accept = $true })
        Assert-Equal 1 $g.Players[0].JailCards
        Assert-Equal 1 $g.Players[1].JailCards
        Assert-Equal 1 $g.Properties[3].OwnerId
        Assert-RonInvariant -State $g
    }

    It 'names a price the AI itself would take' {
        # A deal that is good for player 0 and slightly bad for player 1 should
        # come back as a counter, not a refusal - and the counter must be worth
        # having for both sides, or it is just a different refusal.
        $g = New-TestGame -Players 2
        $g.Players[1].AiProfile = 'Hard'
        Set-TestOwner -State $g -PlayerId 0 -Indices @(1, 6, 8)
        Set-TestOwner -State $g -PlayerId 1 -Indices @(3, 9)

        $offer = New-TestOffer -From 0 -To 1 -Give @(1) -Get @(9)
        [void](Invoke-RonAction -State $g -Action @{ Kind = 'ProposeTrade'; PlayerId = 0; Offer = $offer.ToData() })
        $counter = Find-RonTradeCounter -State $g -PlayerId 1 -Offer $g.Turn.Trade
        if ($null -ne $counter) {
            Assert-True ((Get-RonTradeGain -State $g -Offer $counter -ForPlayerId 1) -gt 0) 'the counter did not help the counterer'
            Assert-True ((Get-RonTradeGain -State $g -Offer $counter -ForPlayerId 0) -gt 0) 'the counter was one the proposer would refuse'
            Assert-True (Test-RonTradeLegal -State $g -Offer $counter) 'the counter was not legal'
            $r = Invoke-RonAction -State $g -Action @{ Kind = 'CounterTrade'; PlayerId = 1; Offer = $counter.ToData() }
            Assert-True $r.Ok $r.Reason
        }
    }
}

exit (Complete-RonTests)
