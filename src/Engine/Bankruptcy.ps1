#
# Ronopoly - debt settlement and bankruptcy.
#
# While a debt is open the debtor may mortgage, sell buildings, or declare
# bankruptcy. All three are ORDINARY actions, so a human, an AI and a remote
# player all go through identical machinery - there is no separate "forced
# liquidation" code path to keep in sync.
#

# Called after every liquidation action. Settles the open debt the moment the
# debtor can cover it.
function Step-RonDebt {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [System.Collections.ArrayList]$Events = $null
    )
    $debt = $State.Turn.Debt
    if ($null -eq $debt) { return $true }

    $debtor = $State.GetPlayer($debt.DebtorId)
    if ($debtor.Cash -lt $debt.Amount) { return $false }

    if ($debt.CreditorId -ge 0) {
        Move-RonCash -State $State -FromId $debt.DebtorId -ToId $debt.CreditorId -Amount $debt.Amount
    }
    elseif ((Test-RonFinesGoToPot -State $State) -and ($debt.Reason -eq 'tax' -or $debt.Reason -eq 'card' -or $debt.Reason -eq 'jail')) {
        Move-RonCashToPot -State $State -PlayerId $debt.DebtorId -Amount $debt.Amount
    }
    else {
        Remove-RonCash -State $State -PlayerId $debt.DebtorId -Amount $debt.Amount
    }

    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'DebtSettled' @{ P = $debt.DebtorId; P2 = $debt.CreditorId; A = $debt.Amount; Reason = $debt.Reason }))
    }
    $State.Turn.Debt  = $null
    $State.Turn.Phase = 'Resolving'
    return $true
}

# Can the debtor still raise the money at all? If not, bankruptcy is the only
# legal action left - which is what stops a player stalling forever.
function Test-RonCanSurviveDebt {
    param([Parameter(Mandatory)][GameState]$State)
    $debt = $State.Turn.Debt
    if ($null -eq $debt) { return $true }
    return ((Get-RonLiquidatableCash -State $State -PlayerId $debt.DebtorId) -ge $debt.Amount)
}

function Invoke-RonDeclareBankruptcy {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [System.Collections.ArrayList]$Events = $null
    )
    $debt = $State.Turn.Debt
    $creditorId = -1
    $depth = 0
    if ($null -ne $debt -and $debt.DebtorId -eq $PlayerId) {
        $creditorId = $debt.CreditorId
        $depth = $debt.Depth
    }
    if ($depth -gt 8) { throw "Invoke-RonDeclareBankruptcy: bankruptcy cascade exceeded depth 8" }

    $debtor = $State.GetPlayer($PlayerId)
    $owned  = Get-RonOwnedIndices -State $State -PlayerId $PlayerId

    # Buildings always go back to the bank at half price first. When there IS a
    # creditor those proceeds end up with them, via the cash sweep below.
    # A forced liquidation is not a voluntary sale, so the "bank needs 4 houses
    # to break a hotel" restriction does not apply: the whole estate clears at
    # once. A hotel is five building units - itself plus the four houses it
    # replaced - which is exactly what it cost to build.
    $unlimited = $State.RuleOn('UnlimitedBuildings')
    foreach ($i in $owned) {
        $deed = $State.Properties[$i]
        if ($deed.Houses -le 0) { continue }
        $unit = [int]((Get-RonHouseCost $i) / 2)
        if ($deed.Houses -eq 5) {
            Add-RonCash -State $State -PlayerId $PlayerId -Amount ($unit * 5)
            if (-not $unlimited) { $State.Bank.HotelsAvailable += 1 }
        }
        else {
            Add-RonCash -State $State -PlayerId $PlayerId -Amount ($unit * $deed.Houses)
            if (-not $unlimited) { $State.Bank.HousesAvailable += $deed.Houses }
        }
        $deed.Houses = 0
    }

    $State.Turn.Debt = $null

    if ($creditorId -ge 0) {
        # --- bankrupt to another player -----------------------------------
        $cash = $debtor.Cash
        if ($cash -gt 0) { Move-RonCash -State $State -FromId $PlayerId -ToId $creditorId -Amount $cash }

        $jail = $debtor.JailCards
        if ($jail -gt 0) {
            $debtor.JailCards = 0
            $State.GetPlayer($creditorId).JailCards += $jail
        }

        # Deeds transfer STILL MORTGAGED, and the receiver owes 10% interest on
        # each one immediately. That charge is what can bankrupt the creditor in
        # turn and start a cascade.
        $interest = 0
        foreach ($i in $owned) {
            $interest += Set-RonPropertyOwner -State $State -SpaceIndex $i -NewOwnerId $creditorId -Events $Events
        }

        $debtor.IsBankrupt   = $true
        $debtor.BankruptTurn = $State.Turn.TurnNumber
        if ($null -ne $Events) {
            [void]$Events.Add((New-RonEvent 'Bankrupt' @{ P = $PlayerId; P2 = $creditorId }))
        }

        if ($interest -gt 0) {
            if (Request-RonPayment -State $State -DebtorId $creditorId -CreditorId -1 -Amount $interest `
                    -Reason 'mortgage-interest' -Events $Events -Depth ($depth + 1)) {
                if ($null -ne $Events) {
                    [void]$Events.Add((New-RonEvent 'MortgageInterest' @{ P = $creditorId; A = $interest }))
                }
            }
        }
    }
    else {
        # --- bankrupt to the bank -----------------------------------------
        # Remaining cash leaves the game entirely.
        $cash = $debtor.Cash
        if ($cash -gt 0) { Remove-RonCash -State $State -PlayerId $PlayerId -Amount $cash }

        # Held jail cards go back to their decks.
        while ($debtor.JailCards -gt 0) {
            $debtor.JailCards -= 1
            Restore-RonJailCardToDeck -State $State
        }

        # The estate returns to the bank free of encumbrance and is auctioned
        # lot by lot. (Simplification: the printed rules carry the mortgage over
        # to the buyer; clearing it instead keeps the money invariant exact and
        # simply means bidders pay more for the same asset.)
        foreach ($i in $owned) {
            $State.Properties[$i].OwnerId   = -1
            $State.Properties[$i].Mortgaged = $false
        }

        $debtor.IsBankrupt   = $true
        $debtor.BankruptTurn = $State.Turn.TurnNumber
        if ($null -ne $Events) {
            [void]$Events.Add((New-RonEvent 'Bankrupt' @{ P = $PlayerId; P2 = -1 }))
        }

        if ($State.RuleOn('AuctionBankruptEstate') -and $owned.Length -gt 0 -and $State.ActivePlayers().Count -gt 1) {
            $State.Turn.EstateQueue = $owned
        }
    }

    # Anything the bankrupt player still owed in the pending queue is void, and
    # anything owed TO them is void too.
    $keep = New-Object System.Collections.ArrayList
    foreach ($item in @($State.Turn.Pending)) {
        if ([int]$item.D -ne $PlayerId -and [int]$item.C -ne $PlayerId) { [void]$keep.Add($item) }
    }
    $State.Turn.Pending = $keep.ToArray()

    # Clear the phase only if no debt is open. The interest charge above can
    # have opened a NEW one against the creditor - the cascade case - and
    # resetting the phase unconditionally would silently swallow it.
    if ($State.Turn.Phase -eq 'AwaitDebt' -and $null -eq $State.Turn.Debt) {
        $State.Turn.Phase = 'Resolving'
    }
}
