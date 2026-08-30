. (Join-Path (Split-Path -Parent $PSCommandPath) '_Common.ps1')

# Puts a chosen card on top of a deck so an effect can be tested directly.
function Set-TestTopCard {
    param([GameState]$State, [ValidateSet('Chance','Chest')][string]$Deck, [int]$CardId)
    if ($Deck -eq 'Chance') { $d = $State.Chance } else { $d = $State.Chest }
    $rest = New-Object System.Collections.ArrayList
    [void]$rest.Add($CardId)
    foreach ($id in $d.Cards) { if ($id -ne $CardId) { [void]$rest.Add($id) } }
    $d.Cards = [int[]]$rest.ToArray()
}

function Get-TestCardId {
    param([ValidateSet('Chance','Chest')][string]$Deck, [string]$Kind, [int]$Skip = 0)
    $cards = Get-RonCards
    if ($Deck -eq 'Chance') { $list = $cards.Chance } else { $list = $cards.Chest }
    $seen = 0
    foreach ($c in $list) {
        if ($c.Kind -eq $Kind) {
            if ($seen -eq $Skip) { return [int]$c.Id }
            $seen++
        }
    }
    throw "no $Kind card in $Deck"
}

Describe 'Cards' {

    It 'has 16 cards in each deck with sequential ids' {
        $cards = Get-RonCards
        Assert-Equal 16 $cards.Chance.Count
        Assert-Equal 16 $cards.Chest.Count
        for ($i = 0; $i -lt 16; $i++) {
            Assert-Equal $i ([int]$cards.Chance[$i].Id) "Chance id $i"
            Assert-Equal $i ([int]$cards.Chest[$i].Id)  "Chest id $i"
        }
    }

    It 'has exactly one Get Out of Jail Free card in each deck' {
        $cards = Get-RonCards
        Assert-Equal 1 @($cards.Chance | Where-Object { $_.Kind -eq 'GetOutOfJailFree' }).Count
        Assert-Equal 1 @($cards.Chest  | Where-Object { $_.Kind -eq 'GetOutOfJailFree' }).Count
    }

    It 'collects the Go salary when an Advance-To card passes Go' {
        $g = New-TestGame
        $g.GetPlayer(0).Position = 30
        Set-TestTopCard -State $g -Deck 'Chance' -CardId 0
        Invoke-RonDrawCard -State $g -PlayerId 0 -Deck 'Chance' | Out-Null
        Assert-Equal 0 $g.GetPlayer(0).Position 'card 0 advances to Go'
        Assert-Equal 1700 $g.GetPlayer(0).Cash 'and collects the 200'
        Assert-RonInvariant -State $g
    }

    It 'never pays the salary for Go Back Three Spaces, even wrapping past Go' {
        $g = New-TestGame
        $g.GetPlayer(0).Position = 1
        Set-TestTopCard -State $g -Deck 'Chance' -CardId (Get-TestCardId -Deck 'Chance' -Kind 'AdvanceSpaces')
        Invoke-RonDrawCard -State $g -PlayerId 0 -Deck 'Chance' | Out-Null
        Assert-Equal 38 $g.GetPlayer(0).Position '1 - 3 wraps back to Super Tax'
        Assert-Equal 1400 $g.GetPlayer(0).Cash 'the 100 tax, and no salary'
        Assert-RonInvariant -State $g
    }

    It 'charges DOUBLE station rent on Advance To Nearest Station' {
        $g = New-TestGame
        Set-TestOwner -State $g -PlayerId 1 -Indices @(5, 15)   # two stations
        $g.GetPlayer(0).Position = 7                             # next station is 15
        Set-TestTopCard -State $g -Deck 'Chance' -CardId (Get-TestCardId -Deck 'Chance' -Kind 'AdvanceToNearestStation')
        Invoke-RonDrawCard -State $g -PlayerId 0 -Deck 'Chance' | Out-Null
        Assert-Equal 15 $g.GetPlayer(0).Position
        # Two stations is 50 normally; the card doubles it to 100.
        Assert-Equal 1400 $g.GetPlayer(0).Cash
        Assert-Equal 1600 $g.GetPlayer(1).Cash
        Assert-RonInvariant -State $g
    }

    It 'charges 10x a fresh roll on Advance To Nearest Utility, with only one owned' {
        $g = New-TestGame
        Set-TestOwner -State $g -PlayerId 1 -Indices @(12)       # Electric Company only
        $g.GetPlayer(0).Position = 7                             # next utility is 12
        Set-TestTopCard -State $g -Deck 'Chance' -CardId (Get-TestCardId -Deck 'Chance' -Kind 'AdvanceToNearestUtility')
        Invoke-RonDrawCard -State $g -PlayerId 0 -Deck 'Chance' | Out-Null
        Assert-Equal 12 $g.GetPlayer(0).Position
        $paid = 1500 - $g.GetPlayer(0).Cash
        # 10x a 2..12 roll - never the 4x a single utility would normally charge.
        Assert-True ($paid -ge 20 -and $paid -le 120) "paid $paid"
        Assert-Equal 0 ($paid % 10) "should be 10x a dice total, got $paid"
        Assert-RonInvariant -State $g
    }

    It 'charges street repairs per house and per hotel' {
        $g = New-TestGame
        Set-TestOwner -State $g -PlayerId 0 -Indices @(1) -Houses 3
        Set-TestOwner -State $g -PlayerId 0 -Indices @(3) -Houses 5
        $id   = Get-TestCardId -Deck 'Chance' -Kind 'StreetRepairs'
        $card = (Get-RonCards).Chance[$id]
        Set-TestTopCard -State $g -Deck 'Chance' -CardId $id
        Invoke-RonDrawCard -State $g -PlayerId 0 -Deck 'Chance' | Out-Null
        $expected = (3 * [int]$card.PerHouse) + (1 * [int]$card.PerHotel)
        Assert-Equal (1500 - $expected) $g.GetPlayer(0).Cash
        Assert-RonInvariant -State $g
    }

    It 'collects from every other player on a birthday' {
        $g = New-TestGame -Players 4
        Set-TestTopCard -State $g -Deck 'Chest' -CardId (Get-TestCardId -Deck 'Chest' -Kind 'CollectFromEachPlayer')
        Invoke-RonDrawCard -State $g -PlayerId 0 -Deck 'Chest' | Out-Null
        Assert-Equal 1530 $g.GetPlayer(0).Cash '3 x 10 in'
        Assert-Equal 1490 $g.GetPlayer(1).Cash
        Assert-RonInvariant -State $g
    }

    It 'pays every other player as Chairman of the Board' {
        $g = New-TestGame -Players 4
        Set-TestTopCard -State $g -Deck 'Chance' -CardId (Get-TestCardId -Deck 'Chance' -Kind 'PayEachPlayer')
        Invoke-RonDrawCard -State $g -PlayerId 0 -Deck 'Chance' | Out-Null
        Assert-Equal 1350 $g.GetPlayer(0).Cash '3 x 50 out'
        Assert-Equal 1550 $g.GetPlayer(1).Cash
        Assert-RonInvariant -State $g
    }

    It 'keeps a Get Out of Jail Free card out of the deck while it is held' {
        $g = New-TestGame
        Set-TestTopCard -State $g -Deck 'Chance' -CardId (Get-TestCardId -Deck 'Chance' -Kind 'GetOutOfJailFree')
        Invoke-RonDrawCard -State $g -PlayerId 0 -Deck 'Chance' | Out-Null
        Assert-Equal 1 $g.GetPlayer(0).JailCards
        Assert-Equal 15 $g.Chance.Count() 'it did not go back to the bottom'
        Assert-RonInvariant -State $g
    }

    It 'sends a player to jail without the Go salary' {
        $g = New-TestGame
        $g.GetPlayer(0).Position = 36
        Set-TestTopCard -State $g -Deck 'Chance' -CardId (Get-TestCardId -Deck 'Chance' -Kind 'GoToJail')
        Invoke-RonDrawCard -State $g -PlayerId 0 -Deck 'Chance' | Out-Null
        Assert-True  $g.GetPlayer(0).InJail
        Assert-Equal 10 $g.GetPlayer(0).Position
        Assert-Equal 1500 $g.GetPlayer(0).Cash
    }

    It 'cycles an ordinary used card to the bottom of its deck' {
        $g = New-TestGame
        Set-TestTopCard -State $g -Deck 'Chest' -CardId (Get-TestCardId -Deck 'Chest' -Kind 'CollectFromBank')
        $top = $g.Chest.Cards[0]
        Invoke-RonDrawCard -State $g -PlayerId 0 -Deck 'Chest' | Out-Null
        Assert-Equal 16 $g.Chest.Count()
        Assert-Equal $top $g.Chest.Cards[15] 'it went to the bottom'
    }

    It 'runs every card effect in both decks without error' {
        # Blanket coverage: any unhandled Kind, bad index or arithmetic slip in
        # a card shows up here rather than 400 turns into a simulation.
        foreach ($deck in @('Chance','Chest')) {
            $list = (Get-RonCards).$deck
            foreach ($c in $list) {
                $g = New-TestGame -Players 3
                Set-TestOwner -State $g -PlayerId 0 -Indices @(1, 3) -Houses 2
                Set-TestOwner -State $g -PlayerId 1 -Indices @(5, 15, 12, 28)
                $g.GetPlayer(0).Position = 22
                $g.Turn.LastRoll = @(3, 4)
                Set-TestTopCard -State $g -Deck $deck -CardId ([int]$c.Id)
                Invoke-RonDrawCard -State $g -PlayerId 0 -Deck $deck | Out-Null
                Step-RonTurn -State $g
                Assert-RonInvariant -State $g
            }
        }
    }
}

exit (Complete-RonTests)
