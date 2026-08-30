. (Join-Path (Split-Path -Parent $PSCommandPath) '_Common.ps1')

Describe 'Rent' {

    Context 'streets' {
        It 'charges the printed site rent when the group is incomplete' {
            $g = New-TestGame
            Set-TestOwner -State $g -PlayerId 1 -Indices @(1)      # Old Kent Road only
            Assert-Equal 2 (Get-RonRent -State $g -SpaceIndex 1)
        }

        It 'DOUBLES the site rent on an undeveloped monopoly' {
            $g = New-TestGame
            Set-TestOwner -State $g -PlayerId 1 -Indices @(1, 3)   # both browns
            Assert-Equal 4 (Get-RonRent -State $g -SpaceIndex 1) 'Old Kent Road 2 -> 4'
            Assert-Equal 8 (Get-RonRent -State $g -SpaceIndex 3) 'Whitechapel 4 -> 8'
        }

        It 'does NOT double once the site is developed' {
            $g = New-TestGame
            Set-TestOwner -State $g -PlayerId 1 -Indices @(1, 3)
            $g.Properties[1].Houses = 1
            Assert-Equal 10 (Get-RonRent -State $g -SpaceIndex 1) 'one house is a flat 10'
        }

        It 'walks the whole rent ladder on Mayfair' {
            $g = New-TestGame
            Set-TestOwner -State $g -PlayerId 1 -Indices @(37, 39)
            $expected = @(100, 200, 600, 1400, 1700, 2000)   # [0] is doubled site rent
            for ($h = 0; $h -le 5; $h++) {
                $g.Properties[39].Houses = $h
                Assert-Equal $expected[$h] (Get-RonRent -State $g -SpaceIndex 39) "Mayfair with $h"
            }
        }

        It 'charges nothing while mortgaged' {
            $g = New-TestGame
            Set-TestOwner -State $g -PlayerId 1 -Indices @(1, 3) -Mortgaged
            Assert-Equal 0 (Get-RonRent -State $g -SpaceIndex 1)
        }

        It 'charges nothing when nobody owns it' {
            $g = New-TestGame
            Assert-Equal 0 (Get-RonRent -State $g -SpaceIndex 39)
        }

        It 'still doubles when a sibling is mortgaged, unless the rule says otherwise' {
            # The printed rules define a monopoly by OWNERSHIP, so the default
            # keeps the doubling.
            $g = New-TestGame
            Set-TestOwner -State $g -PlayerId 1 -Indices @(1)
            Set-TestOwner -State $g -PlayerId 1 -Indices @(3) -Mortgaged
            Assert-Equal 4 (Get-RonRent -State $g -SpaceIndex 1) 'default: ownership defines the monopoly'

            $g2 = New-TestGame -RuleOverrides @{ MonopolyDoubleRequiresUnmortgagedGroup = $true }
            Set-TestOwner -State $g2 -PlayerId 1 -Indices @(1)
            Set-TestOwner -State $g2 -PlayerId 1 -Indices @(3) -Mortgaged
            Assert-Equal 2 (Get-RonRent -State $g2 -SpaceIndex 1) 'rule on: no doubling'
        }
    }

    Context 'stations' {
        It 'doubles per station held: 25 / 50 / 100 / 200' {
            $stations = Get-RonStationIndices
            $expected = @(25, 50, 100, 200)
            for ($n = 1; $n -le 4; $n++) {
                $g = New-TestGame
                Set-TestOwner -State $g -PlayerId 1 -Indices @($stations[0..($n - 1)])
                Assert-Equal $expected[$n - 1] (Get-RonRent -State $g -SpaceIndex $stations[0]) "$n stations"
            }
        }

        It 'pays DOUBLE when reached by the Chance card' {
            $g = New-TestGame
            $stations = Get-RonStationIndices
            Set-TestOwner -State $g -PlayerId 1 -Indices @($stations[0], $stations[1])
            Assert-Equal 50  (Get-RonRent -State $g -SpaceIndex $stations[0])
            Assert-Equal 100 (Get-RonRent -State $g -SpaceIndex $stations[0] -RentMultiplier 2) 'card doubles it'
        }
    }

    Context 'utilities' {
        It 'charges 4x the dice with one utility and 10x with both' {
            $utils = Get-RonUtilityIndices
            $g = New-TestGame
            Set-TestOwner -State $g -PlayerId 1 -Indices @($utils[0])
            Assert-Equal 28 (Get-RonRent -State $g -SpaceIndex $utils[0] -DiceTotal 7) '4 x 7'

            Set-TestOwner -State $g -PlayerId 1 -Indices @($utils[1])
            Assert-Equal 70 (Get-RonRent -State $g -SpaceIndex $utils[0] -DiceTotal 7) '10 x 7'
        }

        It 'charges 10x from the Chance card even when the owner holds only one' {
            $utils = Get-RonUtilityIndices
            $g = New-TestGame
            Set-TestOwner -State $g -PlayerId 1 -Indices @($utils[0])
            Assert-Equal 90 (Get-RonRent -State $g -SpaceIndex $utils[0] -DiceTotal 9 -ForceUtilityTenX) '10 x 9 regardless'
        }

        It 'charges nothing without a dice total' {
            $utils = Get-RonUtilityIndices
            $g = New-TestGame
            Set-TestOwner -State $g -PlayerId 1 -Indices @($utils[0])
            Assert-Equal 0 (Get-RonRent -State $g -SpaceIndex $utils[0])
        }
    }

    Context 'house rules' {
        It 'suppresses rent for a jailed owner under NoRentInJail' {
            $g = New-TestGame -RuleOverrides @{ NoRentInJail = $true }
            Set-TestOwner -State $g -PlayerId 1 -Indices @(39)
            Assert-Equal 50 (Get-RonRent -State $g -SpaceIndex 39)
            $g.GetPlayer(1).InJail = $true
            Assert-Equal 0 (Get-RonRent -State $g -SpaceIndex 39)
        }
    }
}

exit (Complete-RonTests)
