. (Join-Path (Split-Path -Parent $PSCommandPath) '_Common.ps1')

# The dice come from the game's seeded RNG, so tests that need a specific roll
# steer the RNG state rather than mocking it.
function Set-TestNextRoll {
    param([GameState]$State, [int]$Die1, [int]$Die2)
    for ($seed = 1; $seed -lt 20000; $seed++) {
        $probe = [RonRng]::new($seed)
        if ($probe.RollDie() -eq $Die1 -and $probe.RollDie() -eq $Die2) {
            $State.Rng = [RonRng]::new($seed)
            return
        }
    }
    throw "Set-TestNextRoll: no seed found producing $Die1,$Die2"
}

Describe 'Jail' {

    It 'sends a player to jail on the third consecutive double' {
        $g = New-TestGame
        $g.GetPlayer(0).DoublesCount = 2
        Set-TestNextRoll -State $g -Die1 4 -Die2 4
        $events = New-Object System.Collections.ArrayList
        Invoke-RonRoll -State $g -Events $events
        $p = $g.GetPlayer(0)
        Assert-True $p.InJail
        Assert-Equal 10 $p.Position 'jail, without passing Go'
        Assert-Equal 1500 $p.Cash 'no Go salary on the way'
        Assert-True (@($events | Where-Object { $_.T -eq 'ThreeDoubles' }).Count -eq 1)
    }

    It 'does NOT grant another turn when doubles free you from jail' {
        # The most commonly mis-implemented jail rule in Monopoly clones.
        $g = New-TestGame
        $p = $g.GetPlayer(0)
        $p.InJail = $true
        $p.Position = 10
        Set-TestPhase -State $g -Phase 'AwaitJailChoice'
        Set-TestNextRoll -State $g -Die1 3 -Die2 3
        Invoke-RonJailRoll -State $g
        Assert-False $p.InJail 'doubles let you out'
        Assert-Equal 16 $p.Position '10 + 6'
        Assert-False $g.Turn.ExtraTurn 'but they earn no extra roll'
    }

    It 'keeps you in for two failed attempts, then forces the fine on the third' {
        $g = New-TestGame
        $p = $g.GetPlayer(0)
        $p.InJail = $true
        $p.Position = 10
        for ($attempt = 1; $attempt -le 2; $attempt++) {
            Set-TestPhase -State $g -Phase 'AwaitJailChoice'
            Set-TestNextRoll -State $g -Die1 2 -Die2 5
            Invoke-RonJailRoll -State $g
            Assert-True $p.InJail "still inside after attempt $attempt"
            Assert-Equal $attempt $p.JailTurns
        }
        # 2+6 lands on Marlborough Street, an unowned deed, so nothing else
        # touches the player's cash and the fine is the only movement. (2+5
        # would land on Community Chest and draw a card worth 100.)
        Set-TestPhase -State $g -Phase 'AwaitJailChoice'
        Set-TestNextRoll -State $g -Die1 2 -Die2 6
        Invoke-RonJailRoll -State $g
        Assert-False $p.InJail 'the third failure forces release'
        Assert-Equal 1450 $p.Cash 'and the 50 fine is compulsory'
        Assert-Equal 18 $p.Position '10 + 8'
        Assert-Equal 'AwaitBuyDecision' $g.Turn.Phase
        Assert-RonInvariant -State $g
    }

    It 'lets a player pay the fine and then roll normally' {
        $g = New-TestGame
        $p = $g.GetPlayer(0)
        $p.InJail = $true
        $p.Position = 10
        Set-TestPhase -State $g -Phase 'AwaitJailChoice'
        Invoke-RonPayJailFine -State $g
        Assert-False $p.InJail
        Assert-Equal 1450 $p.Cash
        Assert-Equal 'AwaitRoll' $g.Turn.Phase
        Assert-RonInvariant -State $g
    }

    It 'spends a Get Out of Jail Free card and returns it to its deck' {
        $g = New-TestGame
        $p = $g.GetPlayer(0)
        $p.InJail = $true
        $p.Position = 10
        # Take the card out of the Chance deck by hand, as a draw would.
        $cards = Get-RonCards
        $jailId = -1
        foreach ($c in $cards.Chance) { if ($c.Kind -eq 'GetOutOfJailFree') { $jailId = [int]$c.Id } }
        $kept = New-Object System.Collections.ArrayList
        foreach ($id in $g.Chance.Cards) { if ($id -ne $jailId) { [void]$kept.Add($id) } }
        $g.Chance.Cards = [int[]]$kept.ToArray()
        $p.JailCards = 1
        Assert-RonInvariant -State $g

        Set-TestPhase -State $g -Phase 'AwaitJailChoice'
        Invoke-RonUseJailCard -State $g
        Assert-False $p.InJail
        Assert-Equal 0 $p.JailCards
        Assert-Equal 1500 $p.Cash 'the card costs nothing'
        Assert-Equal 16 $g.Chance.Count() 'the card went back to the bottom'
        Assert-RonInvariant -State $g
    }

    It 'still collects rent for a jailed owner under the official rules' {
        $g = New-TestGame
        Set-TestOwner -State $g -PlayerId 1 -Indices @(39)
        $g.GetPlayer(1).InJail = $true
        Assert-Equal 50 (Get-RonRent -State $g -SpaceIndex 39)
    }
}

exit (Complete-RonTests)
