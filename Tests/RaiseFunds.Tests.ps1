. (Join-Path (Split-Path -Parent $PSCommandPath) '_Common.ps1')

# Raising money mid-decision.
#
# The printed rules put no timing condition on mortgaging or selling buildings
# during your own turn, so being a few pounds short of a deed you have landed
# on must not force it to auction.

function New-TestOffer {
    param([int]$From, [int]$To, [int[]]$Give = @(), [int[]]$Get = @(),
          [int]$GiveCash = 0, [int]$GetCash = 0)
    $o = [TradeOffer]::new()
    $o.FromId = $From
    $o.ToId = $To
    $o.GiveProperties = $Give
    $o.GetProperties = $Get
    $o.GiveCash = $GiveCash
    $o.GetCash = $GetCash
    return $o
}

# Player 0 standing on Bond Street (index 34, price 320) with too little cash
# and two mortgageable deeds behind them.
function New-ShortOfCashGame {
    param([int]$Cash = 100)
    $g = New-TestGame -Players 2
    Set-TestOwner -State $g -PlayerId 0 -Indices @(1, 3)
    Set-TestOwner -State $g -PlayerId 1 -Indices @(6)
    Set-TestCash -State $g -PlayerId 0 -Cash $Cash
    $g.GetPlayer(0).Position = 34
    $g.Turn.PendingSpaceIndex = 34
    $g.Turn.Phase = 'AwaitBuyDecision'
    return $g
}

Describe 'Raising money during a buy decision' {

    It 'offers mortgaging and selling while the deed is still on the table' {
        $g = New-ShortOfCashGame
        $legal = @(Get-RonLegalActions -State $g -PlayerId 0)
        $kinds = @($legal | ForEach-Object { $_.Kind })
        Assert-True ($kinds -contains 'Mortgage') 'could not mortgage while deciding whether to buy'
        Assert-True ($kinds -contains 'DeclineProperty') 'the auction route disappeared'
        # Not affordable yet, so there is no buy on offer.
        Assert-True (-not ($kinds -contains 'BuyProperty')) 'offered a purchase it cannot pay for'
    }

    It 'lets a player mortgage their way to the asking price' {
        $g = New-ShortOfCashGame -Cash 100
        $price = Get-RonSpacePrice 34

        foreach ($i in @(1, 3)) {
            $r = Invoke-RonAction -State $g -Action @{ Kind = 'Mortgage'; PlayerId = 0; SpaceIndex = $i } -AssertInvariants
            Assert-True $r.Ok $r.Reason
            # Raising money must not cost the decision.
            Assert-Equal 'AwaitBuyDecision' $g.Turn.Phase
            Assert-Equal 34 $g.Turn.PendingSpaceIndex
        }
        Set-TestCash -State $g -PlayerId 0 -Cash $price

        $r = Invoke-RonAction -State $g -Action @{ Kind = 'BuyProperty'; PlayerId = 0; SpaceIndex = 34 } -AssertInvariants
        Assert-True $r.Ok $r.Reason
        Assert-Equal 0 $g.Properties[34].OwnerId
        Assert-RonInvariant -State $g
    }

    It 'sells a building without ending the decision' {
        $g = New-ShortOfCashGame
        # A monopoly with houses on it, so selling one is legal.
        Set-TestOwner -State $g -PlayerId 0 -Indices @(1, 3) -Houses 1
        $before = $g.GetPlayer(0).Cash
        $r = Invoke-RonAction -State $g -Action @{ Kind = 'SellBuilding'; PlayerId = 0; SpaceIndex = 1 } -AssertInvariants
        Assert-True $r.Ok $r.Reason
        Assert-True ($g.GetPlayer(0).Cash -gt $before) 'selling raised nothing'
        Assert-Equal 'AwaitBuyDecision' $g.Turn.Phase
        Assert-RonInvariant -State $g
    }

    It 'gives the decision back after a trade interrupts it' {
        # A trade parks the game at AwaitTradeResponse and comes back through
        # 'Resolving'. Without the interrupted-decision rule the deed would sit
        # unowned for the rest of the game, never bought and never auctioned.
        $g = New-ShortOfCashGame -Cash 500
        $offer = New-TestOffer -From 0 -To 1 -Give @(1) -Get @(6)
        $r = Invoke-RonAction -State $g -Action @{ Kind = 'ProposeTrade'; PlayerId = 0; Offer = $offer.ToData() }
        Assert-True $r.Ok $r.Reason
        Assert-Equal 'AwaitTradeResponse' $g.Turn.Phase

        $r2 = Invoke-RonAction -State $g -Action @{ Kind = 'RespondTrade'; PlayerId = 1; Accept = $true } -AssertInvariants
        Assert-True $r2.Ok $r2.Reason
        Assert-Equal 'AwaitBuyDecision' $g.Turn.Phase
        Assert-Equal 34 $g.Turn.PendingSpaceIndex

        # And it still resolves normally afterwards.
        $r3 = Invoke-RonAction -State $g -Action @{ Kind = 'BuyProperty'; PlayerId = 0; SpaceIndex = 34 } -AssertInvariants
        Assert-True $r3.Ok $r3.Reason
        Assert-Equal 0 $g.Properties[34].OwnerId
        Assert-True ($g.Turn.Phase -ne 'AwaitBuyDecision') 'the decision came back after being answered'
    }

    It 'gives a jail turn back after a trade interrupts it' {
        # The same bug, in the phase where it was already reachable: trading
        # from inside jail used to skip the jail choice entirely, costing the
        # player their whole turn.
        $g = New-TestGame -Players 2
        Set-TestOwner -State $g -PlayerId 0 -Indices @(1)
        Set-TestOwner -State $g -PlayerId 1 -Indices @(6)
        Send-RonPlayerToJail -State $g -PlayerId 0
        Start-RonTurn -State $g
        Assert-Equal 'AwaitJailChoice' $g.Turn.Phase

        $offer = New-TestOffer -From 0 -To 1 -Give @(1) -Get @(6)
        [void](Invoke-RonAction -State $g -Action @{ Kind = 'ProposeTrade'; PlayerId = 0; Offer = $offer.ToData() })
        $r = Invoke-RonAction -State $g -Action @{ Kind = 'RespondTrade'; PlayerId = 1; Accept = $true } -AssertInvariants
        Assert-True $r.Ok $r.Reason
        Assert-Equal 'AwaitJailChoice' $g.Turn.Phase
        Assert-Equal 0 (Get-RonActingPlayerId -State $g)
    }

    It 'still ends the turn once the decision is answered' {
        # The guard must not be able to trap a turn in a phase it has left.
        $g = New-ShortOfCashGame -Cash 500
        [void](Invoke-RonAction -State $g -Action @{ Kind = 'DeclineProperty'; PlayerId = 0; SpaceIndex = 34 })
        Assert-True ($g.Turn.Phase -ne 'AwaitBuyDecision') 'declining did not clear the decision'
        Assert-Equal -1 $g.Turn.PendingSpaceIndex
    }
}

exit (Complete-RonTests)
