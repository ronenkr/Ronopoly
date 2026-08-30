#
# Ronopoly - movement and landing resolution.
#
# Resolve-RonLanding is re-entrant: a Chance card can move you onto another
# card space ("go back three" from 36 lands on Community Chest at 33), so it
# carries a depth guard. Two hops is the deepest the printed decks can go.
#

function Move-RonPlayer {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [Parameter(Mandatory)][int]$Steps,
        [System.Collections.ArrayList]$Events = $null,
        [switch]$NoGoSalary
    )
    $size  = Get-RonBoardSize
    $p     = $State.GetPlayer($PlayerId)
    $from  = $p.Position
    $to    = ((($from + $Steps) % $size) + $size) % $size

    # Going backwards never collects the salary, and never counts as passing Go.
    $passedGo = $false
    if ($Steps -gt 0 -and $to -lt $from) { $passedGo = $true }
    if ($Steps -gt 0 -and $Steps -ge $size) { $passedGo = $true }

    $p.Position = $to
    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'Moved' @{ P = $PlayerId; S = $to; From = $from }))
    }
    if ($passedGo -and -not $NoGoSalary) { Add-RonGoSalary -State $State -PlayerId $PlayerId -Events $Events }
    return $to
}

# Forward-only advance to a named space, as every "Advance to..." card means.
function Move-RonPlayerTo {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [Parameter(Mandatory)][int]$Target,
        [System.Collections.ArrayList]$Events = $null,
        [switch]$NoGoSalary
    )
    $p = $State.GetPlayer($PlayerId)
    $steps = Get-RonForwardDistance -From $p.Position -To $Target
    if ($steps -eq 0) { $steps = Get-RonBoardSize }
    return (Move-RonPlayer -State $State -PlayerId $PlayerId -Steps $steps -Events $Events -NoGoSalary:$NoGoSalary)
}

function Add-RonGoSalary {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [System.Collections.ArrayList]$Events = $null
    )
    $board  = Get-RonBoard
    $amount = [int]$board.GoSalary
    if ($State.RuleOn('DoubleSalaryOnExactGo') -and $State.GetPlayer($PlayerId).Position -eq [int]$board.GoIndex) {
        $amount = $amount * 2
    }
    Add-RonCash -State $State -PlayerId $PlayerId -Amount $amount
    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'PassedGo' @{ P = $PlayerId; A = $amount }))
    }
    return $amount
}

# Jail is entered without passing Go and without any doubles credit: the
# doubles counter is cleared so the player cannot roll again on release.
function Send-RonPlayerToJail {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [System.Collections.ArrayList]$Events = $null,
        [string]$Reason = 'space'
    )
    $p = $State.GetPlayer($PlayerId)
    $p.Position     = [int](Get-RonBoard).JailIndex
    $p.InJail       = $true
    $p.JailTurns    = 0
    $p.DoublesCount = 0
    $State.Turn.ExtraTurn = $false
    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'JailEntered' @{ P = $PlayerId; Reason = $Reason }))
    }
}

function Set-RonPlayerFreeFromJail {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [System.Collections.ArrayList]$Events = $null,
        [string]$Method = 'fine'
    )
    $p = $State.GetPlayer($PlayerId)
    $p.InJail    = $false
    $p.JailTurns = 0
    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'JailLeft' @{ P = $PlayerId; Method = $Method }))
    }
}

# --- landing resolution ----------------------------------------------------
#
# Applies whatever the space the player is now standing on does. Re-entrant:
# an "Advance to..." card lands them somewhere new, which resolves in turn.
#
# On exit the phase is one of:
#   AwaitBuyDecision  landed on an unowned deed
#   AwaitDebt         an obligation could not be met from cash
#   Resolving         nothing further is pending; Turn.ps1 decides what next
function Resolve-RonLanding {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [System.Collections.ArrayList]$Events = $null,
        [int]$DiceTotal = 0,
        [int]$RentMultiplier = 1,
        [switch]$ForceUtilityTenX,
        [int]$Depth = 0
    )
    if ($Depth -gt 4) { throw "Resolve-RonLanding: card chain exceeded depth 4 - probable rule loop" }

    $p     = $State.GetPlayer($PlayerId)
    $index = $p.Position
    $space = Get-RonSpace $index

    switch ([string]$space.Type) {

        'Go'   { }
        'Jail' { }   # just visiting

        'FreeParking' {
            if ($State.RuleOn('FreeParkingJackpot')) {
                $won = Move-RonPotToPlayer -State $State -PlayerId $PlayerId
                if ($won -gt 0 -and $null -ne $Events) {
                    [void]$Events.Add((New-RonEvent 'FreeParkingWon' @{ P = $PlayerId; A = $won }))
                }
            }
        }

        'GoToJail' {
            Send-RonPlayerToJail -State $State -PlayerId $PlayerId -Events $Events -Reason 'space'
        }

        'Tax' {
            $amount = [int]$space.Amount
            $toPot  = Test-RonFinesGoToPot -State $State
            if (Request-RonPayment -State $State -DebtorId $PlayerId -CreditorId -1 -Amount $amount -Reason 'tax' -Events $Events -ToPot:$toPot) {
                if ($null -ne $Events) {
                    [void]$Events.Add((New-RonEvent 'TaxPaid' @{ P = $PlayerId; A = $amount; S = $index }))
                }
            }
        }

        'Chance' { [void](Invoke-RonDrawCard -State $State -PlayerId $PlayerId -Deck 'Chance' -Events $Events -Depth $Depth) }
        'Chest'  { [void](Invoke-RonDrawCard -State $State -PlayerId $PlayerId -Deck 'Chest'  -Events $Events -Depth $Depth) }

        default {
            # Street, Station or Utility.
            $deed = $State.Properties[$index]

            if ($deed.OwnerId -lt 0) {
                $State.Turn.Phase             = 'AwaitBuyDecision'
                $State.Turn.PendingSpaceIndex = $index
                return
            }
            if ($deed.OwnerId -eq $PlayerId) { return }

            $rent = Get-RonRent -State $State -SpaceIndex $index -DiceTotal $DiceTotal `
                -RentMultiplier $RentMultiplier -ForceUtilityTenX:$ForceUtilityTenX
            if ($rent -le 0) { return }

            if (Request-RonPayment -State $State -DebtorId $PlayerId -CreditorId $deed.OwnerId -Amount $rent -Reason 'rent' -Events $Events) {
                if ($null -ne $Events) {
                    [void]$Events.Add((New-RonEvent 'RentPaid' @{ P = $PlayerId; P2 = $deed.OwnerId; A = $rent; S = $index }))
                }
            }
        }
    }
}
