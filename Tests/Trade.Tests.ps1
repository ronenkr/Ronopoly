. (Join-Path (Split-Path -Parent $PSCommandPath) '_Common.ps1')

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

Describe 'Trade' {

    It 'swaps deeds and cash in both directions' {
        $g = New-TestGame
        Set-TestOwner -State $g -PlayerId 0 -Indices @(1)
        Set-TestOwner -State $g -PlayerId 1 -Indices @(3)
        Invoke-RonTrade -State $g -Offer (New-TestOffer -From 0 -To 1 -Give @(1) -Get @(3) -GiveCash 100)
        Assert-Equal 1 $g.Properties[1].OwnerId
        Assert-Equal 0 $g.Properties[3].OwnerId
        Assert-Equal 1400 $g.GetPlayer(0).Cash
        Assert-Equal 1600 $g.GetPlayer(1).Cash
        Assert-RonInvariant -State $g
    }

    It 'refuses a trade for a deed the offerer does not own' {
        $g = New-TestGame
        $why = ''
        Assert-False (Test-RonTradeLegal -State $g -Offer (New-TestOffer -From 0 -To 1 -Give @(1)) -Reason ([ref]$why))
        Assert-Equal (Get-RonString 'Error.NotOwner') $why
    }

    It 'refuses to trade a deed whose colour group carries buildings' {
        $g = New-TestGame
        Set-TestOwner -State $g -PlayerId 0 -Indices @(1, 3)
        $g.Properties[1].Houses = 1
        $why = ''
        Assert-False (Test-RonTradeLegal -State $g -Offer (New-TestOffer -From 0 -To 1 -Give @(3)) -Reason ([ref]$why))
        Assert-Equal (Get-RonString 'Error.HasBuildings') $why
    }

    It 'refuses more cash than the offerer holds' {
        $g = New-TestGame
        Set-TestOwner -State $g -PlayerId 1 -Indices @(3)
        $why = ''
        Assert-False (Test-RonTradeLegal -State $g -Offer (New-TestOffer -From 0 -To 1 -Get @(3) -GiveCash 5000) -Reason ([ref]$why))
        Assert-Equal (Get-RonString 'Error.NotEnoughCash') $why
    }

    It 'refuses an empty offer and a trade with yourself' {
        $g = New-TestGame
        Assert-False (Test-RonTradeLegal -State $g -Offer (New-TestOffer -From 0 -To 1))
        Assert-False (Test-RonTradeLegal -State $g -Offer (New-TestOffer -From 0 -To 0 -GiveCash 10))
    }

    It 'charges the receiver 10% interest on a mortgaged deed' {
        $g = New-TestGame
        Set-TestOwner -State $g -PlayerId 0 -Indices @(39) -Mortgaged     # mortgage 200
        Invoke-RonTrade -State $g -Offer (New-TestOffer -From 0 -To 1 -Give @(39) -GetCash 50)
        Assert-Equal 1 $g.Properties[39].OwnerId
        Assert-True  $g.Properties[39].Mortgaged 'it stays mortgaged'
        Assert-Equal (1500 - 50 - 20) $g.GetPlayer(1).Cash '50 paid plus 20 interest'
        Assert-RonInvariant -State $g
    }

    It 'moves Get Out of Jail Free cards' {
        $g = New-TestGame
        $cards = Get-RonCards
        $jailId = -1
        foreach ($c in $cards.Chance) { if ($c.Kind -eq 'GetOutOfJailFree') { $jailId = [int]$c.Id } }
        $kept = New-Object System.Collections.ArrayList
        foreach ($id in $g.Chance.Cards) { if ($id -ne $jailId) { [void]$kept.Add($id) } }
        $g.Chance.Cards = [int[]]$kept.ToArray()
        $g.GetPlayer(0).JailCards = 1

        Invoke-RonTrade -State $g -Offer (New-TestOffer -From 0 -To 1 -GiveJail 1 -GetCash 200)
        Assert-Equal 0 $g.GetPlayer(0).JailCards
        Assert-Equal 1 $g.GetPlayer(1).JailCards
        Assert-Equal 1700 $g.GetPlayer(0).Cash
        Assert-RonInvariant -State $g
    }

    Context 'the offer flow' {
        It 'parks in AwaitTradeResponse and applies on accept' {
            $g = New-TestGame
            Set-TestOwner -State $g -PlayerId 1 -Indices @(3)
            Set-TestPhase -State $g -Phase 'AwaitEndTurn'
            $offer = New-TestOffer -From 0 -To 1 -Get @(3) -GiveCash 100
            $r = Invoke-RonAction -State $g -Action @{ Kind = 'ProposeTrade'; PlayerId = 0; Offer = $offer.ToData() }
            Assert-True $r.Ok
            Assert-Equal 'AwaitTradeResponse' $g.Turn.Phase
            Assert-Equal 1 (Get-RonActingPlayerId -State $g) 'the answer is the other player to give'

            $r2 = Invoke-RonAction -State $g -Action @{ Kind = 'RespondTrade'; PlayerId = 1; Accept = $true }
            Assert-True $r2.Ok
            Assert-Equal 0 $g.Properties[3].OwnerId
            Assert-RonInvariant -State $g
        }

        It 'changes nothing on reject' {
            $g = New-TestGame
            Set-TestOwner -State $g -PlayerId 1 -Indices @(3)
            Set-TestPhase -State $g -Phase 'AwaitEndTurn'
            $offer = New-TestOffer -From 0 -To 1 -Get @(3) -GiveCash 100
            [void](Invoke-RonAction -State $g -Action @{ Kind = 'ProposeTrade'; PlayerId = 0; Offer = $offer.ToData() })
            [void](Invoke-RonAction -State $g -Action @{ Kind = 'RespondTrade'; PlayerId = 1; Accept = $false })
            Assert-Equal 1 $g.Properties[3].OwnerId
            Assert-Equal 1500 $g.GetPlayer(0).Cash
            Assert-Equal 'AwaitEndTurn' $g.Turn.Phase
        }
    }

    Context 'the AI side' {
        It 'accepts a trade that gains it value and refuses one that does not' {
            $g = New-TestGame
            Set-TestOwner -State $g -PlayerId 0 -Indices @(1)
            Set-TestOwner -State $g -PlayerId 1 -Indices @(3)
            $generous = New-TestOffer -From 0 -To 1 -Give @(1) -GiveCash 500
            Assert-True (Test-RonShouldAcceptTrade -State $g -PlayerId 1 -Offer $generous)
            $greedy = New-TestOffer -From 0 -To 1 -Get @(3) -GiveCash 1
            Assert-False (Test-RonShouldAcceptTrade -State $g -PlayerId 1 -Offer $greedy)
        }

        It 'proposes only offers the other side would also gain from' {
            $g = New-TestGame
            # The classic two-sided swap: player 0 is one orange short and holds
            # the light blue player 1 needs, and vice versa. Both complete a
            # group, so there is a real price at which both gain.
            Set-TestOwner -State $g -PlayerId 0 -Indices @(16, 18, 9)   # Bow, Marlborough, Pentonville
            Set-TestOwner -State $g -PlayerId 1 -Indices @(19, 6, 8)    # Vine, Angel, Euston
            $g.GetPlayer(0).AiProfile = 'Expert'

            $offer = Find-RonTradeOffer -State $g -PlayerId 0
            Assert-NotNull $offer 'a win-win deal exists here'
            Assert-Equal 19 $offer.GetProperties[0] 'it chases the orange it needs'
            Assert-True ((Get-RonTradeGain -State $g -Offer $offer -ForPlayerId 0) -gt 0)
            Assert-True ((Get-RonTradeGain -State $g -Offer $offer -ForPlayerId 1) -gt 0) 'and they gain too'
            Assert-True (Test-RonTradeLegal -State $g -Offer $offer)
        }

        It 'proposes nothing when it would only be handing a monopoly away' {
            $g = New-TestGame
            # Player 0 needs Whitechapel; player 1 has nothing player 0 can
            # sensibly pay with, so no price makes both sides better off.
            Set-TestOwner -State $g -PlayerId 0 -Indices @(1)
            Set-TestOwner -State $g -PlayerId 1 -Indices @(3)
            $g.GetPlayer(0).AiProfile = 'Expert'
            Assert-Null (Find-RonTradeOffer -State $g -PlayerId 0)
        }
    }
}

exit (Complete-RonTests)
