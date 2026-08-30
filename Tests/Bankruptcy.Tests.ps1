. (Join-Path (Split-Path -Parent $PSCommandPath) '_Common.ps1')

Describe 'Bankruptcy' {

    It 'hands cash and deeds to the creditor when bankrupt to a player' {
        $g = New-TestGame
        Set-TestOwner -State $g -PlayerId 0 -Indices @(1, 3)
        Set-TestCash  -State $g -PlayerId 0 -Cash 40
        # Player 0 owes 500 they cannot raise.
        Assert-False (Request-RonPayment -State $g -DebtorId 0 -CreditorId 1 -Amount 500 -Reason 'rent')
        Assert-Equal 'AwaitDebt' $g.Turn.Phase

        $before = $g.GetPlayer(1).Cash
        Invoke-RonDeclareBankruptcy -State $g -PlayerId 0
        Assert-True  $g.GetPlayer(0).IsBankrupt
        Assert-Equal 0 $g.GetPlayer(0).Cash
        Assert-Equal ($before + 40) $g.GetPlayer(1).Cash 'the creditor takes the cash'
        Assert-Equal 1 $g.Properties[1].OwnerId
        Assert-Equal 1 $g.Properties[3].OwnerId
        Assert-RonInvariant -State $g
    }

    It 'charges the creditor 10% interest on each mortgaged deed received' {
        $g = New-TestGame
        Set-TestOwner -State $g -PlayerId 0 -Indices @(37, 39) -Mortgaged   # 175 + 200 mortgage
        Set-TestCash  -State $g -PlayerId 0 -Cash 0
        Assert-False (Request-RonPayment -State $g -DebtorId 0 -CreditorId 1 -Amount 900 -Reason 'rent')

        $before = $g.GetPlayer(1).Cash
        Invoke-RonDeclareBankruptcy -State $g -PlayerId 0
        # Park Lane mortgage 175 -> 18 interest; Mayfair 200 -> 20. Total 38.
        Assert-Equal ($before - 38) $g.GetPlayer(1).Cash
        Assert-True $g.Properties[39].Mortgaged 'deeds transfer still mortgaged'
        Assert-RonInvariant -State $g
    }

    It 'cascades when the forced interest bankrupts the creditor too' {
        $g = New-TestGame -Players 3
        # Player 0 is broke and holds a lot of mortgaged property; player 1 is
        # the creditor with almost no cash, so the interest wipes them out.
        $mortgaged = @(1, 3, 6, 8, 9, 11, 13, 14, 16, 18, 19)
        Set-TestOwner -State $g -PlayerId 0 -Indices $mortgaged -Mortgaged
        Set-TestCash  -State $g -PlayerId 0 -Cash 0
        Set-TestCash  -State $g -PlayerId 1 -Cash 5
        Assert-False (Request-RonPayment -State $g -DebtorId 0 -CreditorId 1 -Amount 300 -Reason 'rent')
        Invoke-RonDeclareBankruptcy -State $g -PlayerId 0

        Assert-True $g.GetPlayer(0).IsBankrupt
        Assert-Equal 'AwaitDebt' $g.Turn.Phase 'the creditor now owes the interest'
        Assert-Equal 1 $g.Turn.Debt.DebtorId
        Assert-Equal 1 $g.Turn.Debt.Depth 'the cascade depth is tracked'
        Assert-RonInvariant -State $g
    }

    It 'returns everything to the bank and auctions the estate' {
        $g = New-TestGame -Players 3
        Set-TestOwner -State $g -PlayerId 0 -Indices @(1, 3)
        Set-TestCash  -State $g -PlayerId 0 -Cash 10
        Assert-False (Request-RonPayment -State $g -DebtorId 0 -CreditorId -1 -Amount 900 -Reason 'tax')

        Invoke-RonDeclareBankruptcy -State $g -PlayerId 0
        Assert-True $g.GetPlayer(0).IsBankrupt
        Assert-Equal 0 $g.GetPlayer(0).Cash
        Assert-Equal -1 $g.Properties[1].OwnerId 'back to the bank'
        Step-RonTurn -State $g
        Assert-Equal 'AwaitAuction' $g.Turn.Phase 'and the estate goes under the hammer'
        Assert-RonInvariant -State $g
    }

    It 'sells the buildings back before anything else' {
        $g = New-TestGame
        Set-TestOwner -State $g -PlayerId 0 -Indices @(1, 3) -Houses 5     # two hotels
        Set-TestCash  -State $g -PlayerId 0 -Cash 0
        Assert-False (Request-RonPayment -State $g -DebtorId 0 -CreditorId 1 -Amount 5000 -Reason 'rent')

        $before = $g.GetPlayer(1).Cash
        Invoke-RonDeclareBankruptcy -State $g -PlayerId 0
        # Browns cost 50 a house, so a unit sells back for 25 and a hotel is
        # five units: 125 a site, 250 for the pair.
        Assert-Equal ($before + 250) $g.GetPlayer(1).Cash
        Assert-Equal 0 $g.Properties[1].Houses
        Assert-Equal 12 $g.Bank.HotelsAvailable 'both hotels returned'
        Assert-RonInvariant -State $g
    }

    It 'ends the game when only one player is left standing' {
        $g = New-TestGame
        Set-TestCash -State $g -PlayerId 0 -Cash 0
        Assert-False (Request-RonPayment -State $g -DebtorId 0 -CreditorId 1 -Amount 100 -Reason 'rent')
        Invoke-RonDeclareBankruptcy -State $g -PlayerId 0
        Step-RonTurn -State $g
        Assert-True  $g.IsOver
        Assert-Equal 1 $g.WinnerId
    }

    Context 'settling without going bankrupt' {
        It 'clears the debt as soon as a mortgage raises enough' {
            $g = New-TestGame
            Set-TestOwner -State $g -PlayerId 0 -Indices @(39)     # mortgages for 200
            Set-TestCash  -State $g -PlayerId 0 -Cash 0
            Assert-False (Request-RonPayment -State $g -DebtorId 0 -CreditorId 1 -Amount 150 -Reason 'rent')

            $r = Invoke-RonAction -State $g -Action @{ Kind = 'Mortgage'; PlayerId = 0; SpaceIndex = 39 }
            Assert-True $r.Ok
            Assert-Null $g.Turn.Debt 'settled automatically'
            Assert-Equal 50 $g.GetPlayer(0).Cash '200 raised, 150 paid'
            Assert-Equal 1650 $g.GetPlayer(1).Cash
            Assert-RonInvariant -State $g
        }

        It 'offers bankruptcy as the only way out when nothing can be raised' {
            $g = New-TestGame
            Set-TestCash -State $g -PlayerId 0 -Cash 10
            Assert-False (Request-RonPayment -State $g -DebtorId 0 -CreditorId 1 -Amount 900 -Reason 'rent')
            Assert-False (Test-RonCanSurviveDebt -State $g)
            $legal = @(Get-RonLegalActions -State $g)
            Assert-Equal 1 $legal.Count
            Assert-Equal 'DeclareBankruptcy' $legal[0].Kind
        }
    }
}

exit (Complete-RonTests)
