#
# Ronopoly - buying, transferring and mortgaging deeds.
#

# Price is passed explicitly because an auction can settle below or above the
# printed price.
function Invoke-RonBuyProperty {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [Parameter(Mandatory)][int]$SpaceIndex,
        [int]$Price = -1,
        [System.Collections.ArrayList]$Events = $null
    )
    if (-not (Test-RonIsDeed $SpaceIndex)) { throw "Invoke-RonBuyProperty: $SpaceIndex is not a deed" }
    $deed = $State.Properties[$SpaceIndex]
    if ($deed.OwnerId -ge 0) { throw "Invoke-RonBuyProperty: $(Get-RonSpaceName $SpaceIndex) is already owned" }
    if ($Price -lt 0) { $Price = Get-RonSpacePrice $SpaceIndex }

    Remove-RonCash -State $State -PlayerId $PlayerId -Amount $Price
    $deed.OwnerId = $PlayerId
    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'Bought' @{ P = $PlayerId; S = $SpaceIndex; A = $Price }))
    }
}

# Ownership change with no money attached. Used by trades and by bankruptcy.
# A mortgaged deed carries its 10% interest charge with it: the RECEIVER pays
# it immediately, which is the rule that can bankrupt a creditor and start a
# cascade.
function Set-RonPropertyOwner {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$SpaceIndex,
        [Parameter(Mandatory)][int]$NewOwnerId,
        [System.Collections.ArrayList]$Events = $null,
        [switch]$NoMortgageInterest
    )
    $deed = $State.Properties[$SpaceIndex]
    $oldOwner = $deed.OwnerId
    $deed.OwnerId = $NewOwnerId
    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'OwnerChanged' @{ S = $SpaceIndex; P = $NewOwnerId; P2 = $oldOwner }))
    }
    if ($deed.Mortgaged -and $NewOwnerId -ge 0 -and -not $NoMortgageInterest) {
        return (Get-RonUnmortgageInterest -State $State -SpaceIndex $SpaceIndex)
    }
    return 0
}

function Get-RonUnmortgageInterest {
    param([Parameter(Mandatory)][GameState]$State, [Parameter(Mandatory)][int]$SpaceIndex)
    if ($State.RuleOn('MortgageInterestFree')) { return 0 }
    $m = Get-RonMortgageValue $SpaceIndex
    return (Get-RonInterest -Principal $m -Percent (Get-RonBoard).MortgageRate)
}

# --- mortgage --------------------------------------------------------------
#
# The printed rules require every building on the whole COLOUR GROUP to be
# sold before any member can be mortgaged - not just the one being mortgaged.

function Test-RonCanMortgage {
    param(
        [GameState]$State,
        [int]$PlayerId,
        [int]$SpaceIndex,
        [ref]$Reason = ([ref]$script:RonReasonSink)
    )
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    if (-not $bi.IsDeed[$SpaceIndex]) { return (Set-RonReason $Reason 'Error.NotOwner') }

    $props = $State.Properties
    $deed  = $props[$SpaceIndex]
    if ($deed.OwnerId -ne $PlayerId) { return (Set-RonReason $Reason 'Error.NotOwner') }
    if ($deed.Mortgaged)             { return (Set-RonReason $Reason 'Error.AlreadyMortgaged') }

    foreach ($i in $bi.GroupOf[$SpaceIndex]) {
        if ($props[$i].Houses -gt 0) { return (Set-RonReason $Reason 'Error.HasBuildings') }
    }
    return $true
}

function Invoke-RonMortgage {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [Parameter(Mandatory)][int]$SpaceIndex,
        [System.Collections.ArrayList]$Events = $null
    )
    $why = ''
    if (-not (Test-RonCanMortgage -State $State -PlayerId $PlayerId -SpaceIndex $SpaceIndex -Reason ([ref]$why))) {
        throw "Invoke-RonMortgage: $why"
    }
    $value = Get-RonMortgageValue $SpaceIndex
    $State.Properties[$SpaceIndex].Mortgaged = $true
    Add-RonCash -State $State -PlayerId $PlayerId -Amount $value
    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'Mortgaged' @{ P = $PlayerId; S = $SpaceIndex; A = $value }))
    }
    return $value
}

function Test-RonCanUnmortgage {
    param(
        [GameState]$State,
        [int]$PlayerId,
        [int]$SpaceIndex,
        [ref]$Reason = ([ref]$script:RonReasonSink)
    )
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    if (-not $bi.IsDeed[$SpaceIndex]) { return (Set-RonReason $Reason 'Error.NotOwner') }

    $deed = $State.Properties[$SpaceIndex]
    if ($deed.OwnerId -ne $PlayerId) { return (Set-RonReason $Reason 'Error.NotOwner') }
    if (-not $deed.Mortgaged)        { return (Set-RonReason $Reason 'Error.AlreadyMortgaged') }

    $cost = $bi.Mortgage[$SpaceIndex]
    if (-not $State.Rules['MortgageInterestFree']) { $cost += [int][math]::Ceiling($cost * $bi.MortgageRate / 100.0) }
    if ($State.Players[$PlayerId].Cash -lt $cost) { return (Set-RonReason $Reason 'Error.NotEnoughCash') }
    return $true
}

function Invoke-RonUnmortgage {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [Parameter(Mandatory)][int]$SpaceIndex,
        [System.Collections.ArrayList]$Events = $null
    )
    $why = ''
    if (-not (Test-RonCanUnmortgage -State $State -PlayerId $PlayerId -SpaceIndex $SpaceIndex -Reason ([ref]$why))) {
        throw "Invoke-RonUnmortgage: $why"
    }
    $cost = Get-RonUnmortgageCost -Index $SpaceIndex -Rules $State.Rules
    Remove-RonCash -State $State -PlayerId $PlayerId -Amount $cost
    $State.Properties[$SpaceIndex].Mortgaged = $false
    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'Unmortgaged' @{ P = $PlayerId; S = $SpaceIndex; A = $cost }))
    }
    return $cost
}
