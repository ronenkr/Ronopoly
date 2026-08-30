. (Join-Path (Split-Path -Parent $PSCommandPath) '_Common.ps1')

Describe 'Building' {

    Context 'even build' {
        It 'refuses to build without the whole colour group' {
            $g = New-TestGame
            Set-TestOwner -State $g -PlayerId 0 -Indices @(1)      # Old Kent only
            $why = ''
            Assert-False (Test-RonCanBuildHouse -State $g -PlayerId 0 -SpaceIndex 1 -Reason ([ref]$why))
            Assert-Equal (Get-RonString 'Error.NotAMonopoly') $why
        }

        It 'refuses to build a second house before the sibling has its first' {
            $g = New-TestGame
            Set-TestOwner -State $g -PlayerId 0 -Indices @(1, 3)
            Invoke-RonBuildHouse -State $g -PlayerId 0 -SpaceIndex 1 | Out-Null
            $why = ''
            Assert-False (Test-RonCanBuildHouse -State $g -PlayerId 0 -SpaceIndex 1 -Reason ([ref]$why))
            Assert-Equal (Get-RonString 'Error.UnevenBuild') $why
            Assert-True (Test-RonCanBuildHouse -State $g -PlayerId 0 -SpaceIndex 3) 'the sibling is at the minimum'
        }

        It 'refuses to sell from below the group maximum' {
            $g = New-TestGame
            Set-TestOwner -State $g -PlayerId 0 -Indices @(1, 3)
            Invoke-RonBuildHouse -State $g -PlayerId 0 -SpaceIndex 1 | Out-Null
            $why = ''
            Assert-False (Test-RonCanSellBuilding -State $g -PlayerId 0 -SpaceIndex 3 -Reason ([ref]$why)) 'it has none'
            Assert-True  (Test-RonCanSellBuilding -State $g -PlayerId 0 -SpaceIndex 1) 'it is at the maximum'
        }

        It 'refuses to build when any site in the group is mortgaged' {
            $g = New-TestGame
            Set-TestOwner -State $g -PlayerId 0 -Indices @(1, 3)
            $g.Properties[3].Mortgaged = $true
            $why = ''
            Assert-False (Test-RonCanBuildHouse -State $g -PlayerId 0 -SpaceIndex 1 -Reason ([ref]$why))
            Assert-Equal (Get-RonString 'Error.GroupMortgaged') $why
        }
    }

    Context 'the bank supply' {
        It 'returns four houses to the bank when a hotel goes up' {
            $g = New-TestGame
            Set-TestOwner -State $g -PlayerId 0 -Indices @(1, 3)
            Set-TestCash -State $g -PlayerId 0 -Cash 5000
            for ($round = 1; $round -le 4; $round++) {
                Invoke-RonBuildHouse -State $g -PlayerId 0 -SpaceIndex 1 | Out-Null
                Invoke-RonBuildHouse -State $g -PlayerId 0 -SpaceIndex 3 | Out-Null
            }
            Assert-Equal 24 $g.Bank.HousesAvailable '32 - 8'
            Invoke-RonBuildHouse -State $g -PlayerId 0 -SpaceIndex 1 | Out-Null   # hotel
            Assert-Equal 5  $g.Properties[1].Houses
            Assert-Equal 28 $g.Bank.HousesAvailable 'the four houses come back'
            Assert-Equal 11 $g.Bank.HotelsAvailable
            Assert-RonInvariant -State $g
        }

        It 'blocks breaking a hotel when the bank has fewer than four houses' {
            $g = New-TestGame
            Set-TestOwner -State $g -PlayerId 0 -Indices @(1, 3) -Houses 5
            $g.Bank.HousesAvailable = 3
            $why = ''
            Assert-False (Test-RonCanSellBuilding -State $g -PlayerId 0 -SpaceIndex 1 -Reason ([ref]$why))
            Assert-Equal (Get-RonString 'Error.CannotBreakHotel') $why

            $g.Bank.HousesAvailable = 4
            Assert-True (Test-RonCanSellBuilding -State $g -PlayerId 0 -SpaceIndex 1) 'four is enough'
        }

        It 'blocks building once the bank runs out of houses' {
            $g = New-TestGame
            Set-TestOwner -State $g -PlayerId 0 -Indices @(1, 3)
            Set-TestCash -State $g -PlayerId 0 -Cash 5000
            $g.Bank.HousesAvailable = 0
            $why = ''
            Assert-False (Test-RonCanBuildHouse -State $g -PlayerId 0 -SpaceIndex 1 -Reason ([ref]$why))
            Assert-Equal (Get-RonString 'Error.NoHousesLeft') $why
        }

        It 'ignores the supply entirely under UnlimitedBuildings' {
            $g = New-TestGame -RuleOverrides @{ UnlimitedBuildings = $true }
            Set-TestOwner -State $g -PlayerId 0 -Indices @(1, 3)
            Set-TestCash -State $g -PlayerId 0 -Cash 5000
            $g.Bank.HousesAvailable = 0
            Assert-True (Test-RonCanBuildHouse -State $g -PlayerId 0 -SpaceIndex 1)
        }
    }

    Context 'prices' {
        It 'sells every building level back for half the house price' {
            $g = New-TestGame
            Set-TestOwner -State $g -PlayerId 0 -Indices @(37, 39)     # dark blue, 200/house
            Set-TestCash -State $g -PlayerId 0 -Cash 5000
            $before = $g.GetPlayer(0).Cash
            Invoke-RonBuildHouse -State $g -PlayerId 0 -SpaceIndex 37 | Out-Null
            Assert-Equal ($before - 200) $g.GetPlayer(0).Cash
            $proceeds = Invoke-RonSellBuilding -State $g -PlayerId 0 -SpaceIndex 37
            Assert-Equal 100 $proceeds 'half of 200'
            # Selling back at half price is a real loss: 200 out, 100 back.
            Assert-Equal ($before - 100) $g.GetPlayer(0).Cash
            Assert-RonInvariant -State $g
        }
    }
}

exit (Complete-RonTests)
