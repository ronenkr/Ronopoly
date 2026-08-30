#
# Ronopoly - the turn state machine.
#
# There is no game loop anywhere in this project. The engine only ever answers
# "what may happen next" and "apply this"; something else - a click, an AI
# timer tick, or a network message - supplies the action.
#
# 'Resolving' is an internal phase meaning "the last thing finished, decide
# what is next". Step-RonTurn converts it into a real phase and it is never
# visible to a player.
#

# Whose decision the engine is waiting for. NOT always the current player: a
# rent payer can be bankrupted mid-turn, and an auction or a trade answer moves
# the decision to someone else entirely.
function Get-RonActingPlayerId {
    param([Parameter(Mandatory)][GameState]$State)
    switch ($State.Turn.Phase) {
        'AwaitDebt'          { if ($null -ne $State.Turn.Debt)  { return $State.Turn.Debt.DebtorId } }
        'AwaitAuction'       { if ($null -ne $State.Turn.Auction) { return $State.Turn.Auction.CurrentBidderId() } }
        'AwaitTradeResponse' { if ($null -ne $State.Turn.Trade) { return $State.Turn.Trade.ToId } }
    }
    return $State.Turn.CurrentPlayerId
}

function Start-RonTurn {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [System.Collections.ArrayList]$Events = $null
    )
    $p = $State.CurrentPlayer()
    $State.Turn.LastRoll     = @()
    $State.Turn.RollCount    = 0
    $State.Turn.ExtraTurn    = $false
    $State.Turn.PendingSpaceIndex = -1
    $State.Turn.TradesProposed = 0
    $p.DoublesCount = 0

    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'TurnStarted' @{ P = $p.Id; N = $State.Turn.TurnNumber }))
    }
    if ($p.InJail) { $State.Turn.Phase = 'AwaitJailChoice' } else { $State.Turn.Phase = 'AwaitRoll' }
}

function Invoke-RonRoll {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [System.Collections.ArrayList]$Events = $null
    )
    $p  = $State.CurrentPlayer()
    $d1 = $State.Rng.RollDie()
    $d2 = $State.Rng.RollDie()
    $State.Turn.LastRoll  = @($d1, $d2)
    $State.Turn.RollCount += 1
    $doubles = ($d1 -eq $d2)

    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'Rolled' @{ P = $p.Id; D1 = $d1; D2 = $d2 }))
    }

    if ($State.RuleOn('SnakeEyesBonus') -and $d1 -eq 1 -and $d2 -eq 1) {
        $bonus = $State.RuleInt('SnakeEyesAmount', 500)
        Add-RonCash -State $State -PlayerId $p.Id -Amount $bonus
        if ($null -ne $Events) {
            [void]$Events.Add((New-RonEvent 'SnakeEyes' @{ P = $p.Id; A = $bonus }))
        }
    }

    if ($doubles) {
        $p.DoublesCount += 1
        if ($p.DoublesCount -ge 3) {
            # Straight to jail without moving and without the Go salary.
            if ($null -ne $Events) {
                [void]$Events.Add((New-RonEvent 'ThreeDoubles' @{ P = $p.Id }))
            }
            Send-RonPlayerToJail -State $State -PlayerId $p.Id -Events $Events -Reason 'doubles'
            $State.Turn.Phase = 'Resolving'
            Step-RonTurn -State $State -Events $Events
            return
        }
        $State.Turn.ExtraTurn = $true
    }
    else {
        $State.Turn.ExtraTurn = $false
    }

    [void](Move-RonPlayer -State $State -PlayerId $p.Id -Steps ($d1 + $d2) -Events $Events)
    $State.Turn.Phase = 'Resolving'
    Resolve-RonLanding -State $State -PlayerId $p.Id -Events $Events -DiceTotal ($d1 + $d2)
    Step-RonTurn -State $State -Events $Events
}

# --- jail ------------------------------------------------------------------

function Invoke-RonJailRoll {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [System.Collections.ArrayList]$Events = $null
    )
    $p  = $State.CurrentPlayer()
    $d1 = $State.Rng.RollDie()
    $d2 = $State.Rng.RollDie()
    $State.Turn.LastRoll  = @($d1, $d2)
    $State.Turn.RollCount += 1
    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'Rolled' @{ P = $p.Id; D1 = $d1; D2 = $d2; InJail = $true }))
    }

    if ($d1 -eq $d2) {
        # Doubles free you - but they do NOT earn another turn. This is the
        # single most commonly mis-implemented jail rule.
        Set-RonPlayerFreeFromJail -State $State -PlayerId $p.Id -Events $Events -Method 'doubles'
        $p.DoublesCount = 0
        $State.Turn.ExtraTurn = $false
        [void](Move-RonPlayer -State $State -PlayerId $p.Id -Steps ($d1 + $d2) -Events $Events)
        $State.Turn.Phase = 'Resolving'
        Resolve-RonLanding -State $State -PlayerId $p.Id -Events $Events -DiceTotal ($d1 + $d2)
        Step-RonTurn -State $State -Events $Events
        return
    }

    $p.JailTurns += 1
    $maxTurns = [int](Get-RonBoard).MaxJailTurns
    if ($p.JailTurns -lt $maxTurns) {
        # Still inside; the turn simply ends.
        $State.Turn.Phase = 'Resolving'
        Step-RonTurn -State $State -Events $Events
        return
    }

    # Third failure: the fine becomes compulsory, then the player moves the
    # amount just rolled.
    $fine  = [int](Get-RonBoard).JailFine
    $toPot = Test-RonFinesGoToPot -State $State
    $State.Turn.PendingJailMove = $d1 + $d2
    if (Request-RonPayment -State $State -DebtorId $p.Id -CreditorId -1 -Amount $fine -Reason 'jail' -Events $Events -ToPot:$toPot) {
        if ($null -ne $Events) {
            [void]$Events.Add((New-RonEvent 'JailFinePaid' @{ P = $p.Id; A = $fine }))
        }
        Complete-RonJailRelease -State $State -Events $Events
        Step-RonTurn -State $State -Events $Events
    }
    # If the fine opened a debt, the move waits in PendingJailMove and
    # Step-RonTurn performs it once the debt is settled.
}

# Performs the deferred move that follows the compulsory third-turn jail fine.
function Complete-RonJailRelease {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [System.Collections.ArrayList]$Events = $null
    )
    $steps = $State.Turn.PendingJailMove
    $State.Turn.PendingJailMove = 0
    if ($steps -le 0) { return }
    $p = $State.CurrentPlayer()
    if ($p.IsBankrupt) { return }
    Set-RonPlayerFreeFromJail -State $State -PlayerId $p.Id -Events $Events -Method 'fine'
    [void](Move-RonPlayer -State $State -PlayerId $p.Id -Steps $steps -Events $Events)
    $State.Turn.Phase = 'Resolving'
    Resolve-RonLanding -State $State -PlayerId $p.Id -Events $Events -DiceTotal $steps
}

function Invoke-RonPayJailFine {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [System.Collections.ArrayList]$Events = $null
    )
    $p     = $State.CurrentPlayer()
    $fine  = [int](Get-RonBoard).JailFine
    $toPot = Test-RonFinesGoToPot -State $State
    if (Request-RonPayment -State $State -DebtorId $p.Id -CreditorId -1 -Amount $fine -Reason 'jail' -Events $Events -ToPot:$toPot) {
        if ($null -ne $Events) {
            [void]$Events.Add((New-RonEvent 'JailFinePaid' @{ P = $p.Id; A = $fine }))
        }
        Set-RonPlayerFreeFromJail -State $State -PlayerId $p.Id -Events $Events -Method 'fine'
        $State.Turn.Phase = 'AwaitRoll'
    }
}

function Invoke-RonUseJailCard {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [System.Collections.ArrayList]$Events = $null
    )
    $p = $State.CurrentPlayer()
    Use-RonJailCard -State $State -PlayerId $p.Id -Events $Events
    $State.Turn.Phase = 'AwaitRoll'
}

# --- the FSM driver --------------------------------------------------------
#
# Converts the internal 'Resolving' phase into whatever the game is actually
# waiting for. Loops because settling one thing can uncover the next: a debt
# settles, which frees a jailed player, who lands on a card, which charges
# them again.
function Step-RonTurn {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [System.Collections.ArrayList]$Events = $null
    )
    if ($State.IsOver) { return }

    for ($guard = 0; $guard -lt 64; $guard++) {

        # A phase that is waiting on a player stays put.
        if ($State.Turn.Phase -ne 'Resolving') {
            if ($State.Turn.Phase -eq 'AwaitDebt') {
                # The debtor may have been given enough cash by something else
                # (a trade, a completed auction) since the debt was opened.
                if (Step-RonDebt -State $State -Events $Events) { continue }
            }
            return
        }

        # 1. An open debt outranks everything.
        if ($null -ne $State.Turn.Debt) {
            if (-not (Step-RonDebt -State $State -Events $Events)) {
                $State.Turn.Phase = 'AwaitDebt'
                return
            }
            continue
        }

        # 2. Queued obligations from a single card or trade.
        if (@($State.Turn.Pending).Count -gt 0) {
            if (-not (Resolve-RonPendingPayment -State $State -Events $Events)) {
                $State.Turn.Phase = 'AwaitDebt'
                return
            }
            continue
        }

        # 3. A jail release deferred by the compulsory fine.
        if ($State.Turn.PendingJailMove -gt 0) {
            Complete-RonJailRelease -State $State -Events $Events
            continue
        }

        # 4. Lots from a bankrupt estate, auctioned one at a time.
        if (@($State.Turn.EstateQueue).Count -gt 0) {
            $q    = @($State.Turn.EstateQueue)
            $next = [int]$q[0]
            $rest = @()
            if ($q.Count -gt 1) { $rest = $q[1..($q.Count - 1)] }
            $State.Turn.EstateQueue = [int[]]$rest
            Start-RonAuction -State $State -SpaceIndex $next -Events $Events -IsEstate
            if ($State.Turn.Phase -eq 'AwaitAuction') { return }
            continue
        }

        # 5. Is the game finished?
        if (Test-RonGameOver -State $State) {
            Complete-RonGame -State $State -Events $Events
            return
        }

        # 6. Nothing pending: either roll again on doubles, or offer to end.
        $current = $State.CurrentPlayer()
        if ($current.IsBankrupt) {
            Complete-RonTurn -State $State -Events $Events
            return
        }

        # 6a. An INTERRUPTED decision is still outstanding.
        #
        # Mortgaging and trading are legal while a buy decision or a jail
        # choice is on the table, and a trade parks the game at
        # AwaitTradeResponse and returns here through 'Resolving' once it is
        # answered. Without this the pending decision would simply evaporate:
        # the deed would sit unowned and never go to auction, and a player who
        # traded from inside jail would lose their whole turn.
        $pending = $State.Turn.PendingSpaceIndex
        if ($pending -ge 0 -and $State.Properties[$pending].OwnerId -lt 0) {
            $State.Turn.Phase = 'AwaitBuyDecision'
            return
        }
        # RollCount is what separates "still deciding how to get out" from
        # "was sent here by this turn's roll": anything that jails a player
        # mid-turn has already rolled at least once.
        if ($current.InJail -and $State.Turn.RollCount -eq 0) {
            $State.Turn.Phase = 'AwaitJailChoice'
            return
        }

        if ($State.Turn.ExtraTurn -and -not $current.InJail) {
            $State.Turn.ExtraTurn = $false
            $State.Turn.Phase = 'AwaitRoll'
            return
        }
        $State.Turn.Phase = 'AwaitEndTurn'
        return
    }
    throw "Step-RonTurn: the FSM failed to settle after 64 iterations (seed $($State.Seed), version $($State.Version))"
}

function Complete-RonTurn {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [System.Collections.ArrayList]$Events = $null
    )
    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'TurnEnded' @{ P = $State.Turn.CurrentPlayerId }))
    }

    if (Test-RonGameOver -State $State) {
        Complete-RonGame -State $State -Events $Events
        return
    }

    # Advance to the next solvent seat. Bankrupt players are skipped rather
    # than removed, so seating order and player ids stay stable all game.
    $order = @($State.Order)
    $at = 0
    for ($i = 0; $i -lt $order.Count; $i++) {
        if ($order[$i] -eq $State.Turn.CurrentPlayerId) { $at = $i; break }
    }
    for ($step = 1; $step -le $order.Count; $step++) {
        $candidate = $order[($at + $step) % $order.Count]
        if (-not $State.GetPlayer($candidate).IsBankrupt) {
            $State.Turn.CurrentPlayerId = $candidate
            break
        }
    }

    $State.Turn.TurnNumber += 1
    $limit = $State.RuleInt('TurnLimit', 0)
    if ($limit -gt 0 -and $State.Turn.TurnNumber -gt $limit) {
        Complete-RonGame -State $State -Events $Events -ByTurnLimit
        return
    }

    Start-RonTurn -State $State -Events $Events
}

function Test-RonGameOver {
    param([Parameter(Mandatory)][GameState]$State)
    if ($State.IsOver) { return $true }
    return ($State.ActivePlayers().Count -le 1)
}

function Complete-RonGame {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [System.Collections.ArrayList]$Events = $null,
        [switch]$ByTurnLimit
    )
    if ($State.IsOver) { return }
    $State.IsOver = $true
    $State.Turn.Phase = 'GameOver'

    $survivors = $State.ActivePlayers()
    if ($survivors.Count -eq 1) {
        $State.WinnerId = $survivors[0].Id
    }
    elseif ($survivors.Count -gt 1) {
        # Turn limit, or a draw: richest net worth takes it.
        $best = -1
        $bestWorth = [int]::MinValue
        foreach ($p in $survivors) {
            $worth = Get-RonNetWorth -State $State -PlayerId $p.Id
            if ($worth -gt $bestWorth) { $bestWorth = $worth; $best = $p.Id }
        }
        $State.WinnerId = $best
    }
    else {
        $State.WinnerId = -1
    }

    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'GameOver' @{ P = $State.WinnerId; ByTurnLimit = [bool]$ByTurnLimit }))
    }
}
