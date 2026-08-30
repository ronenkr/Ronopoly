#
# Ronopoly - houses and hotels.
#
# Houses is 0..5 where 5 means a hotel. Every level is one "building unit"
# costing the street's House price and selling back for half of it, so a hotel
# plus its four houses is five units - which keeps the arithmetic exact and
# self-consistent in both directions.
#
# The finite supply is a real rule, not decoration: building a hotel RETURNS
# four houses to the bank, and selling one requires taking four back. When the
# bank is short of houses, a hotel cannot be broken at all.
#

# Called for every owned deed on every legal-action enumeration, so like
# Get-RonRent it reads the flat board tables and makes no nested calls.
function Test-RonCanBuildHouse {
    param(
        [GameState]$State,
        [int]$PlayerId,
        [int]$SpaceIndex,
        [ref]$Reason = ([ref]$script:RonReasonSink)
    )
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    if (-not $bi.IsStreet[$SpaceIndex]) { return (Set-RonReason $Reason 'Error.NotOwner') }

    $props = $State.Properties
    $deed  = $props[$SpaceIndex]
    if ($deed.OwnerId -ne $PlayerId) { return (Set-RonReason $Reason 'Error.NotOwner') }
    if ($deed.Houses -ge 5)          { return (Set-RonReason $Reason 'Error.NoHotelsLeft') }

    # One pass over the group establishes ownership, mortgage status and the
    # current minimum - all three checks the even-build rule needs.
    $min = 99
    foreach ($i in $bi.GroupOf[$SpaceIndex]) {
        $m = $props[$i]
        if ($m.OwnerId -ne $PlayerId) { return (Set-RonReason $Reason 'Error.NotAMonopoly') }
        if ($m.Mortgaged)             { return (Set-RonReason $Reason 'Error.GroupMortgaged') }
        if ($m.Houses -lt $min)       { $min = $m.Houses }
    }
    # Even-build: you may only add to a site currently at the group's minimum.
    if ($deed.Houses -ne $min) { return (Set-RonReason $Reason 'Error.UnevenBuild') }

    if (-not $State.Rules['UnlimitedBuildings']) {
        if ($deed.Houses -eq 4) {
            if ($State.Bank.HotelsAvailable -le 0) { return (Set-RonReason $Reason 'Error.NoHotelsLeft') }
        }
        elseif ($State.Bank.HousesAvailable -le 0) { return (Set-RonReason $Reason 'Error.NoHousesLeft') }
    }

    if ($State.Players[$PlayerId].Cash -lt $bi.HouseCost[$SpaceIndex]) { return (Set-RonReason $Reason 'Error.NotEnoughCash') }
    return $true
}

function Invoke-RonBuildHouse {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [Parameter(Mandatory)][int]$SpaceIndex,
        [System.Collections.ArrayList]$Events = $null
    )
    $why = ''
    if (-not (Test-RonCanBuildHouse -State $State -PlayerId $PlayerId -SpaceIndex $SpaceIndex -Reason ([ref]$why))) {
        throw "Invoke-RonBuildHouse: $why"
    }
    $deed = $State.Properties[$SpaceIndex]
    $cost = Get-RonHouseCost $SpaceIndex
    Remove-RonCash -State $State -PlayerId $PlayerId -Amount $cost

    if ($deed.Houses -eq 4) {
        # Hotel: the four houses go back into the bank's stock, which is what
        # makes the 32-house shortage a live strategic weapon.
        $deed.Houses = 5
        if (-not $State.RuleOn('UnlimitedBuildings')) {
            $State.Bank.HousesAvailable += 4
            $State.Bank.HotelsAvailable -= 1
        }
    }
    else {
        $deed.Houses += 1
        if (-not $State.RuleOn('UnlimitedBuildings')) { $State.Bank.HousesAvailable -= 1 }
    }

    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'BuildingBuilt' @{ P = $PlayerId; S = $SpaceIndex; N = $deed.Houses; A = $cost }))
    }
    return $deed.Houses
}

function Test-RonCanSellBuilding {
    param(
        [GameState]$State,
        [int]$PlayerId,
        [int]$SpaceIndex,
        [ref]$Reason = ([ref]$script:RonReasonSink)
    )
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    if (-not $bi.IsStreet[$SpaceIndex]) { return (Set-RonReason $Reason 'Error.NotOwner') }

    $props = $State.Properties
    $deed  = $props[$SpaceIndex]
    if ($deed.OwnerId -ne $PlayerId) { return (Set-RonReason $Reason 'Error.NotOwner') }
    if ($deed.Houses -le 0)          { return (Set-RonReason $Reason 'Error.NotOwner') }

    $max = -1
    foreach ($i in $bi.GroupOf[$SpaceIndex]) {
        if ($props[$i].Houses -gt $max) { $max = $props[$i].Houses }
    }
    # Even-sell: only a site at the group's maximum may be reduced.
    if ($deed.Houses -ne $max) { return (Set-RonReason $Reason 'Error.UnevenSell') }

    # Breaking a hotel needs four houses back from the bank. If they are not
    # there, the hotel is stuck - a real rule and a real bug source.
    if ($deed.Houses -eq 5 -and -not $State.Rules['UnlimitedBuildings']) {
        if ($State.Bank.HousesAvailable -lt 4) { return (Set-RonReason $Reason 'Error.CannotBreakHotel') }
    }
    return $true
}

function Invoke-RonSellBuilding {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [Parameter(Mandatory)][int]$SpaceIndex,
        [System.Collections.ArrayList]$Events = $null
    )
    $why = ''
    if (-not (Test-RonCanSellBuilding -State $State -PlayerId $PlayerId -SpaceIndex $SpaceIndex -Reason ([ref]$why))) {
        throw "Invoke-RonSellBuilding: $why"
    }
    $deed = $State.Properties[$SpaceIndex]
    $proceeds = [int]((Get-RonHouseCost $SpaceIndex) / 2)

    if ($deed.Houses -eq 5) {
        $deed.Houses = 4
        if (-not $State.RuleOn('UnlimitedBuildings')) {
            $State.Bank.HotelsAvailable += 1
            $State.Bank.HousesAvailable -= 4
        }
    }
    else {
        $deed.Houses -= 1
        if (-not $State.RuleOn('UnlimitedBuildings')) { $State.Bank.HousesAvailable += 1 }
    }

    Add-RonCash -State $State -PlayerId $PlayerId -Amount $proceeds
    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'BuildingSold' @{ P = $PlayerId; S = $SpaceIndex; N = $deed.Houses; A = $proceeds }))
    }
    return $proceeds
}

function Get-RonBuildableIndices {
    param([GameState]$State, [int]$PlayerId)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    $props = $State.Properties
    $out = New-Object System.Collections.ArrayList
    foreach ($i in $bi.Deeds) {
        if ($props[$i].OwnerId -ne $PlayerId) { continue }
        if (Test-RonCanBuildHouse -State $State -PlayerId $PlayerId -SpaceIndex $i) { [void]$out.Add($i) }
    }
    return [int[]]$out.ToArray()
}

function Get-RonSellableIndices {
    param([GameState]$State, [int]$PlayerId)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    $props = $State.Properties
    $out = New-Object System.Collections.ArrayList
    foreach ($i in $bi.Deeds) {
        if ($props[$i].OwnerId -ne $PlayerId) { continue }
        if ($props[$i].Houses -le 0) { continue }
        if (Test-RonCanSellBuilding -State $State -PlayerId $PlayerId -SpaceIndex $i) { [void]$out.Add($i) }
    }
    return [int[]]$out.ToArray()
}

# Total building units a player holds, used by valuation and the HUD.
function Get-RonBuildingCount {
    param([Parameter(Mandatory)][GameState]$State, [Parameter(Mandatory)][int]$PlayerId)
    $houses = 0
    $hotels = 0
    foreach ($i in (Get-RonOwnedIndices -State $State -PlayerId $PlayerId)) {
        $h = $State.Properties[$i].Houses
        if ($h -eq 5) { $hotels++ } else { $houses += $h }
    }
    return @{ Houses = $houses; Hotels = $hotels }
}
