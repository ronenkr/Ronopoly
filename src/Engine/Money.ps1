#
# Ronopoly - cash primitives.
#
# Every money movement in the game goes through exactly one of these four
# functions, which is what makes the MoneyInPlay invariant meaningful:
#
#   Add-RonCash     bank    -> player   MoneyInPlay grows
#   Remove-RonCash  player  -> bank     MoneyInPlay shrinks
#   Move-RonCash    player  -> player   MoneyInPlay unchanged
#   Move-RonCashToPot / Move-RonPotToPlayer    unchanged (the pot is in play)
#
# Nothing else may assign to PlayerState.Cash. If a bug ever makes the sum of
# cash disagree with MoneyInPlay, Assert-RonInvariant names it immediately.

function Add-RonCash {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [Parameter(Mandatory)][int]$Amount
    )
    if ($Amount -lt 0) { throw "Add-RonCash: amount must not be negative ($Amount)" }
    if ($Amount -eq 0) { return }
    $p = $State.GetPlayer($PlayerId)
    $p.Cash += $Amount
    $State.MoneyInPlay += $Amount
}

# The caller MUST have established the player can afford this (normally via
# Request-RonPayment). Going negative is an engine bug, not a game state.
function Remove-RonCash {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [Parameter(Mandatory)][int]$Amount
    )
    if ($Amount -lt 0) { throw "Remove-RonCash: amount must not be negative ($Amount)" }
    if ($Amount -eq 0) { return }
    $p = $State.GetPlayer($PlayerId)
    if ($p.Cash -lt $Amount) {
        throw "Remove-RonCash: $($p.Name) has $($p.Cash) but $Amount was taken - the caller skipped Request-RonPayment"
    }
    $p.Cash -= $Amount
    $State.MoneyInPlay -= $Amount
}

function Move-RonCash {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$FromId,
        [Parameter(Mandatory)][int]$ToId,
        [Parameter(Mandatory)][int]$Amount
    )
    if ($Amount -lt 0) { throw "Move-RonCash: amount must not be negative ($Amount)" }
    if ($Amount -eq 0) { return }
    $from = $State.GetPlayer($FromId)
    $to   = $State.GetPlayer($ToId)
    if ($from.Cash -lt $Amount) {
        throw "Move-RonCash: $($from.Name) has $($from.Cash) but $Amount was taken - the caller skipped Request-RonPayment"
    }
    $from.Cash -= $Amount
    $to.Cash   += $Amount
}

function Move-RonCashToPot {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [Parameter(Mandatory)][int]$Amount
    )
    if ($Amount -le 0) { return }
    $p = $State.GetPlayer($PlayerId)
    if ($p.Cash -lt $Amount) { throw "Move-RonCashToPot: $($p.Name) cannot afford $Amount" }
    $p.Cash -= $Amount
    $State.Bank.FreeParkingPot += $Amount
}

function Move-RonPotToPlayer {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId
    )
    $amount = $State.Bank.FreeParkingPot
    if ($amount -le 0) { return 0 }
    $State.Bank.FreeParkingPot = 0
    $State.GetPlayer($PlayerId).Cash += $amount
    return $amount
}

# Where fines and taxes go. Only meaningful when FreeParkingJackpot is on;
# under official rules they are simply destroyed (returned to the bank).
function Test-RonFinesGoToPot {
    param([Parameter(Mandatory)][GameState]$State)
    return ($State.RuleOn('FreeParkingJackpot') -and $State.RuleOn('TaxesToFreeParking'))
}

# --- the payment gate ------------------------------------------------------
#
# THE entry point for any obligation. Returns $true if it was settled outright.
# If not, it opens a DebtContext and moves the FSM to AwaitDebt, where the
# debtor - human, AI or remote alike - must mortgage, sell buildings, or
# declare bankruptcy. All three are ordinary actions, so there is exactly one
# implementation of forced liquidation for all three kinds of player.
#
# CreditorId -1 means the bank.
function Request-RonPayment {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$DebtorId,
        [Parameter(Mandatory)][int]$CreditorId,
        [Parameter(Mandatory)][int]$Amount,
        [Parameter(Mandatory)][string]$Reason,
        [System.Collections.ArrayList]$Events = $null,
        [switch]$ToPot,
        [int]$Depth = 0
    )
    if ($Amount -le 0) { return $true }
    $debtor = $State.GetPlayer($DebtorId)

    if ($debtor.Cash -ge $Amount) {
        if ($CreditorId -ge 0)  { Move-RonCash -State $State -FromId $DebtorId -ToId $CreditorId -Amount $Amount }
        elseif ($ToPot)         { Move-RonCashToPot -State $State -PlayerId $DebtorId -Amount $Amount }
        else                    { Remove-RonCash -State $State -PlayerId $DebtorId -Amount $Amount }
        return $true
    }

    $debt = [DebtContext]::new()
    $debt.DebtorId   = $DebtorId
    $debt.CreditorId = $CreditorId
    $debt.Amount     = $Amount
    $debt.Reason     = $Reason
    $debt.Depth      = $Depth
    $State.Turn.Debt  = $debt
    $State.Turn.Phase = 'AwaitDebt'
    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'DebtOpened' @{ P = $DebtorId; P2 = $CreditorId; A = $Amount; Reason = $Reason }))
    }
    return $false
}
