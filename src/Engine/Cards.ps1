#
# Ronopoly - Chance and Community Chest.
#
# Effects are data-driven (see Cards.uk.psd1); this file is the dispatcher.
# The two Get Out of Jail Free cards leave the deck while held and return to
# the bottom when used or sold, which is why decks are queues.
#

function Get-RonCardDefinition {
    param(
        [Parameter(Mandatory)][ValidateSet('Chance','Chest')][string]$Deck,
        [Parameter(Mandatory)][int]$CardId
    )
    $cards = Get-RonCards
    if ($Deck -eq 'Chance') { return $cards.Chance[$CardId] }
    return $cards.Chest[$CardId]
}

function Invoke-RonDrawCard {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [Parameter(Mandatory)][ValidateSet('Chance','Chest')][string]$Deck,
        [System.Collections.ArrayList]$Events = $null,
        [int]$Depth = 0
    )
    if ($Deck -eq 'Chance') { $deckState = $State.Chance } else { $deckState = $State.Chest }
    if ($deckState.Count() -eq 0) {
        # Unreachable with 16-card decks, but fail loudly rather than silently
        # doing nothing if that ever stops being true.
        throw "Invoke-RonDrawCard: the $Deck deck is empty"
    }

    $cardId = $deckState.Draw()
    $card   = Get-RonCardDefinition -Deck $Deck -CardId $cardId
    $State.Turn.PendingCardId   = $cardId
    $State.Turn.PendingCardDeck = $Deck

    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'CardDrawn' @{ P = $PlayerId; Deck = $Deck; CardId = $cardId; Text = [string]$card.Text }))
    }

    # A kept jail card stays out of the deck; everything else goes to the bottom.
    if ($card.Kind -eq 'GetOutOfJailFree') { $State.GetPlayer($PlayerId).JailCards += 1 }
    else { $deckState.Enqueue($cardId) }

    Invoke-RonCardEffect -State $State -PlayerId $PlayerId -Deck $Deck -CardId $cardId -Events $Events -Depth $Depth
    return $cardId
}

function Invoke-RonCardEffect {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [Parameter(Mandatory)][ValidateSet('Chance','Chest')][string]$Deck,
        [Parameter(Mandatory)][int]$CardId,
        [System.Collections.ArrayList]$Events = $null,
        [int]$Depth = 0
    )
    $card  = Get-RonCardDefinition -Deck $Deck -CardId $CardId
    $toPot = Test-RonFinesGoToPot -State $State
    $dice  = $State.Turn.DiceTotal()

    switch ([string]$card.Kind) {

        'AdvanceTo' {
            [void](Move-RonPlayerTo -State $State -PlayerId $PlayerId -Target ([int]$card.Target) -Events $Events)
            Resolve-RonLanding -State $State -PlayerId $PlayerId -Events $Events -DiceTotal $dice -Depth ($Depth + 1)
        }

        'AdvanceSpaces' {
            # "Go back three spaces" never collects the Go salary, even when the
            # backwards move wraps past Go.
            [void](Move-RonPlayer -State $State -PlayerId $PlayerId -Steps ([int]$card.Delta) -Events $Events -NoGoSalary)
            Resolve-RonLanding -State $State -PlayerId $PlayerId -Events $Events -DiceTotal $dice -Depth ($Depth + 1)
        }

        'AdvanceToNearestStation' {
            $target = Get-RonNextSpaceOfType -From $State.GetPlayer($PlayerId).Position -Type 'Station'
            [void](Move-RonPlayerTo -State $State -PlayerId $PlayerId -Target $target -Events $Events)
            # The card doubles the station rent otherwise due: 50/100/200/400.
            Resolve-RonLanding -State $State -PlayerId $PlayerId -Events $Events -DiceTotal $dice -RentMultiplier 2 -Depth ($Depth + 1)
        }

        'AdvanceToNearestUtility' {
            $target = Get-RonNextSpaceOfType -From $State.GetPlayer($PlayerId).Position -Type 'Utility'
            [void](Move-RonPlayerTo -State $State -PlayerId $PlayerId -Target $target -Events $Events)
            # A FRESH roll, and 10x regardless of how many utilities the owner
            # holds. The most commonly mis-implemented rule on the board.
            $d1 = $State.Rng.RollDie()
            $d2 = $State.Rng.RollDie()
            if ($null -ne $Events) {
                [void]$Events.Add((New-RonEvent 'Rolled' @{ P = $PlayerId; D1 = $d1; D2 = $d2; ForCard = $true }))
            }
            Resolve-RonLanding -State $State -PlayerId $PlayerId -Events $Events -DiceTotal ($d1 + $d2) -ForceUtilityTenX -Depth ($Depth + 1)
        }

        'GoToJail' { Send-RonPlayerToJail -State $State -PlayerId $PlayerId -Events $Events -Reason 'card' }

        'CollectFromBank' { Add-RonCash -State $State -PlayerId $PlayerId -Amount ([int]$card.Amount) }

        'PayBank' {
            [void](Request-RonPayment -State $State -DebtorId $PlayerId -CreditorId -1 -Amount ([int]$card.Amount) -Reason 'card' -Events $Events -ToPot:$toPot)
        }

        'CollectFromEachPlayer' {
            foreach ($other in $State.ActivePlayers()) {
                if ($other.Id -eq $PlayerId) { continue }
                Add-RonPendingPayment -State $State -DebtorId $other.Id -CreditorId $PlayerId -Amount ([int]$card.Amount) -Reason 'card'
            }
            [void](Resolve-RonPendingPayment -State $State -Events $Events)
        }

        'PayEachPlayer' {
            foreach ($other in $State.ActivePlayers()) {
                if ($other.Id -eq $PlayerId) { continue }
                Add-RonPendingPayment -State $State -DebtorId $PlayerId -CreditorId $other.Id -Amount ([int]$card.Amount) -Reason 'card'
            }
            [void](Resolve-RonPendingPayment -State $State -Events $Events)
        }

        'GetOutOfJailFree' { }   # already granted by Invoke-RonDrawCard

        'StreetRepairs' {
            $counts = Get-RonBuildingCount -State $State -PlayerId $PlayerId
            $total  = ($counts.Houses * [int]$card.PerHouse) + ($counts.Hotels * [int]$card.PerHotel)
            if ($total -gt 0) {
                [void](Request-RonPayment -State $State -DebtorId $PlayerId -CreditorId -1 -Amount $total -Reason 'repairs' -Events $Events -ToPot:$toPot)
            }
        }

        default { throw "Invoke-RonCardEffect: unknown card kind '$($card.Kind)'" }
    }
}

# Spending a held card returns it to the bottom of the deck it came from. The
# deck is identified by which one is currently MISSING its jail card, so a card
# that changed hands in a trade still goes back to the right place.
function Use-RonJailCard {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [System.Collections.ArrayList]$Events = $null
    )
    $p = $State.GetPlayer($PlayerId)
    if ($p.JailCards -le 0) { throw "Use-RonJailCard: $($p.Name) holds no jail card" }
    $p.JailCards -= 1
    Restore-RonJailCardToDeck -State $State
    Set-RonPlayerFreeFromJail -State $State -PlayerId $PlayerId -Events $Events -Method 'card'
}

function Restore-RonJailCardToDeck {
    param([Parameter(Mandatory)][GameState]$State)
    $cards = Get-RonCards
    $chanceJail = -1
    foreach ($c in $cards.Chance) { if ($c.Kind -eq 'GetOutOfJailFree') { $chanceJail = [int]$c.Id } }
    $chestJail = -1
    foreach ($c in $cards.Chest)  { if ($c.Kind -eq 'GetOutOfJailFree') { $chestJail  = [int]$c.Id } }

    if ($chanceJail -ge 0 -and ($State.Chance.Cards -notcontains $chanceJail)) { $State.Chance.Enqueue($chanceJail); return }
    if ($chestJail  -ge 0 -and ($State.Chest.Cards  -notcontains $chestJail))  { $State.Chest.Enqueue($chestJail);  return }
    throw 'Restore-RonJailCardToDeck: both jail cards are already in their decks'
}

# --- the pending obligation queue -----------------------------------------
#
# A single card can create several payments at once ("pay each player 50"),
# but only one debt may be open at a time. They queue here and are drained one
# at a time, so a player who is bankrupted by the second of four payments is
# handled exactly like any other bankruptcy.

function Add-RonPendingPayment {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$DebtorId,
        [Parameter(Mandatory)][int]$CreditorId,
        [Parameter(Mandatory)][int]$Amount,
        [string]$Reason = ''
    )
    if ($Amount -le 0) { return }
    $q = @($State.Turn.Pending)
    $q += ,@{ D = $DebtorId; C = $CreditorId; A = $Amount; R = $Reason }
    $State.Turn.Pending = $q
}

# Drains the queue until it is empty or one payment opens a debt. Returns
# $true when the queue is fully settled.
function Resolve-RonPendingPayment {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [System.Collections.ArrayList]$Events = $null
    )
    while ($true) {
        $q = @($State.Turn.Pending)
        if ($q.Count -eq 0) { return $true }

        $next = $q[0]
        $rest = @()
        if ($q.Count -gt 1) { $rest = $q[1..($q.Count - 1)] }
        $State.Turn.Pending = $rest

        $debtor = $State.GetPlayer([int]$next.D)
        # A player bankrupted by an earlier item in the same batch owes nothing.
        if ($debtor.IsBankrupt) { continue }

        $settled = Request-RonPayment -State $State -DebtorId ([int]$next.D) -CreditorId ([int]$next.C) `
            -Amount ([int]$next.A) -Reason ([string]$next.R) -Events $Events
        if (-not $settled) { return $false }
    }
}
