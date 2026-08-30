#
# Ronopoly - rent calculation.
#
# One function covers all six variants. The two rules clones most often get
# wrong are handled by CONTEXT parameters rather than duplicated code:
#
#   "Advance to the nearest Station"  -> pay DOUBLE the normal station rent,
#                                        i.e. 50 / 100 / 200 / 400.
#   "Advance to the nearest Utility"  -> throw again and pay 10x the roll,
#                                        REGARDLESS of how many utilities the
#                                        owner holds (so 10x even with one).
#
# This is the single hottest function in the engine - the AI's cash-reserve
# estimate calls it once per owned deed on every decision - so it reads the
# flat board tables directly and makes no nested function calls at all.
#
function Get-RonRent {
    param(
        [GameState]$State,
        [int]$SpaceIndex,
        [int]$DiceTotal = 0,
        [int]$RentMultiplier = 1,
        [switch]$ForceUtilityTenX
    )
    $deed = $State.Properties[$SpaceIndex]
    $ownerId = $deed.OwnerId
    if ($ownerId -lt 0)  { return 0 }
    if ($deed.Mortgaged) { return 0 }

    $owner = $State.Players[$ownerId]
    if ($owner.IsBankrupt) { return 0 }
    if ($owner.InJail -and $State.Rules['NoRentInJail']) { return 0 }

    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    $props = $State.Properties

    switch ($bi.Type[$SpaceIndex]) {

        'Street' {
            $houses = $deed.Houses
            if ($houses -gt 0) { return $bi.Rent[$SpaceIndex][$houses] * $RentMultiplier }

            $rent = $bi.Rent[$SpaceIndex][0]
            # An undeveloped site in a complete colour group pays DOUBLE.
            $members = $bi.GroupOf[$SpaceIndex]
            $monopoly = $true
            foreach ($m in $members) {
                if ($props[$m].OwnerId -ne $ownerId) { $monopoly = $false; break }
            }
            if ($monopoly -and $State.Rules['MonopolyDoubleRequiresUnmortgagedGroup']) {
                foreach ($m in $members) {
                    if ($props[$m].Mortgaged) { $monopoly = $false; break }
                }
            }
            if ($monopoly) { $rent = $rent * 2 }
            return $rent * $RentMultiplier
        }

        'Station' {
            $n = 0
            foreach ($i in $bi.Stations) { if ($props[$i].OwnerId -eq $ownerId) { $n++ } }
            if ($n -le 0) { return 0 }
            # 25 / 50 / 100 / 200
            return $bi.StationBaseRent * [int][math]::Pow(2, $n - 1) * $RentMultiplier
        }

        'Utility' {
            if ($DiceTotal -le 0) { return 0 }
            if ($ForceUtilityTenX) { return $bi.UtilityBoth * $DiceTotal }
            $n = 0
            foreach ($i in $bi.Utilities) { if ($props[$i].OwnerId -eq $ownerId) { $n++ } }
            if ($n -ge 2) { return $bi.UtilityBoth * $DiceTotal }
            if ($n -eq 1) { return $bi.UtilityOne  * $DiceTotal }
            return 0
        }
    }
    return 0
}
