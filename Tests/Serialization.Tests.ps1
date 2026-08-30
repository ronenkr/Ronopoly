. (Join-Path (Split-Path -Parent $PSCommandPath) '_Common.ps1')

# Plays a fixed game far enough to produce a rich, awkward state: owned deeds,
# buildings, mortgages, a drawn deck and a non-trivial turn.
function New-TestPlayedGame {
    param([int]$Seed = 314, [int]$Turns = 60)
    $g = New-RonGame -Players @(
        @{ Name = 'Ann'; Kind = 'AI'; AiProfile = 'Expert'; Token = 'hat' },
        @{ Name = 'Bob'; Kind = 'AI'; AiProfile = 'Hard';   Token = 'car' },
        @{ Name = 'Cat'; Kind = 'AI'; AiProfile = 'Normal'; Token = 'dog' }
    ) -Seed $Seed
    while (-not $g.IsOver -and $g.Turn.TurnNumber -le $Turns) {
        $a = Get-RonAiAction -State $g
        if ($null -eq $a) { break }
        $r = Invoke-RonAction -State $g -Action $a
        if (-not $r.Ok) { break }
    }
    return $g
}

Describe 'Serialization' {

    It 'round-trips a played game through JSON with no loss' {
        $g = New-TestPlayedGame
        $json = ConvertTo-RonJson $g.ToData()
        $back = [GameState]::FromData((ConvertFrom-RonJson $json))

        Assert-Equal $g.GameId  $back.GameId
        Assert-Equal $g.Seed    $back.Seed
        Assert-Equal $g.Version $back.Version
        Assert-Equal $g.MoneyInPlay $back.MoneyInPlay
        Assert-Equal $g.Players.Length $back.Players.Length
        Assert-Equal $g.Properties.Length $back.Properties.Length

        for ($i = 0; $i -lt $g.Players.Length; $i++) {
            Assert-Equal $g.Players[$i].Name       $back.Players[$i].Name
            Assert-Equal $g.Players[$i].Cash       $back.Players[$i].Cash
            Assert-Equal $g.Players[$i].Position   $back.Players[$i].Position
            Assert-Equal $g.Players[$i].InJail     $back.Players[$i].InJail
            Assert-Equal $g.Players[$i].JailCards  $back.Players[$i].JailCards
            Assert-Equal $g.Players[$i].IsBankrupt $back.Players[$i].IsBankrupt
        }
        for ($i = 0; $i -lt 40; $i++) {
            Assert-Equal $g.Properties[$i].OwnerId   $back.Properties[$i].OwnerId   "owner of space $i"
            Assert-Equal $g.Properties[$i].Houses    $back.Properties[$i].Houses    "houses on space $i"
            Assert-Equal $g.Properties[$i].Mortgaged $back.Properties[$i].Mortgaged "mortgage on space $i"
        }
        Assert-Equal $g.Bank.HousesAvailable $back.Bank.HousesAvailable
        Assert-Equal $g.Bank.HotelsAvailable $back.Bank.HotelsAvailable
        Assert-Sequence $g.Chance.Cards $back.Chance.Cards
        Assert-Sequence $g.Chest.Cards  $back.Chest.Cards
        Assert-Sequence $g.Order        $back.Order
        Assert-Equal $g.Turn.Phase           $back.Turn.Phase
        Assert-Equal $g.Turn.CurrentPlayerId $back.Turn.CurrentPlayerId
        Assert-Equal $g.Turn.TurnNumber      $back.Turn.TurnNumber
        Assert-RonInvariant -State $back
    }

    It 'preserves the RNG stream exactly across a round trip' {
        # If this fails, a saved game or a LAN resync would silently diverge.
        $g = New-TestPlayedGame -Turns 20
        $back = [GameState]::FromData((ConvertFrom-RonJson (ConvertTo-RonJson $g.ToData())))
        $a = @()
        $b = @()
        for ($i = 0; $i -lt 50; $i++) { $a += $g.Rng.RollDie(); $b += $back.Rng.RollDie() }
        Assert-Sequence $a $b
    }

    It 'survives a round trip mid-auction' {
        $g = New-TestGame -Players 3
        Start-RonAuction -State $g -SpaceIndex 39 -FirstBidderId 0
        Invoke-RonAuctionBid -State $g -PlayerId 0 -Amount 120
        $back = [GameState]::FromData((ConvertFrom-RonJson (ConvertTo-RonJson $g.ToData())))
        Assert-NotNull $back.Turn.Auction
        Assert-Equal 39  $back.Turn.Auction.SpaceIndex
        Assert-Equal 120 $back.Turn.Auction.CurrentBid
        Assert-Equal 0   $back.Turn.Auction.HighBidderId
        Assert-Sequence $g.Turn.Auction.ActiveBidders $back.Turn.Auction.ActiveBidders
        Assert-Equal $g.Turn.Auction.CurrentBidderId() $back.Turn.Auction.CurrentBidderId()
    }

    It 'survives a round trip mid-debt' {
        $g = New-TestGame
        Set-TestCash -State $g -PlayerId 0 -Cash 10
        [void](Request-RonPayment -State $g -DebtorId 0 -CreditorId 1 -Amount 500 -Reason 'rent')
        $back = [GameState]::FromData((ConvertFrom-RonJson (ConvertTo-RonJson $g.ToData())))
        Assert-Equal 'AwaitDebt' $back.Turn.Phase
        Assert-NotNull $back.Turn.Debt
        Assert-Equal 0   $back.Turn.Debt.DebtorId
        Assert-Equal 1   $back.Turn.Debt.CreditorId
        Assert-Equal 500 $back.Turn.Debt.Amount
        Assert-Equal 0   (Get-RonActingPlayerId -State $back)
    }

    It 'survives a round trip with a pending trade' {
        $g = New-TestGame
        Set-TestOwner -State $g -PlayerId 1 -Indices @(3)
        $o = [TradeOffer]::new()
        $o.FromId = 0
        $o.ToId = 1
        $o.GetProperties = @(3)
        $o.GiveCash = 150
        Set-TestPhase -State $g -Phase 'AwaitEndTurn'
        Start-RonTradeOffer -State $g -Offer $o
        $back = [GameState]::FromData((ConvertFrom-RonJson (ConvertTo-RonJson $g.ToData())))
        Assert-Equal 'AwaitTradeResponse' $back.Turn.Phase
        Assert-NotNull $back.Turn.Trade
        Assert-Equal 150 $back.Turn.Trade.GiveCash
        Assert-Sequence @(3) $back.Turn.Trade.GetProperties
        Assert-Equal 1 (Get-RonActingPlayerId -State $back)
    }

    It 'keeps a single-element array an array after a round trip' {
        # ConvertFrom-Json collapses one-element arrays to a scalar, which would
        # break every .Length and foreach in the engine if it leaked through.
        $g = New-TestGame
        $g.Turn.LastRoll = @(4)
        $g.Turn.EstateQueue = @(39)
        $back = [GameState]::FromData((ConvertFrom-RonJson (ConvertTo-RonJson $g.ToData())))
        Assert-Equal 1 $back.Turn.LastRoll.Length
        Assert-Equal 4 $back.Turn.LastRoll[0]
        Assert-Equal 1 $back.Turn.EstateQueue.Length
        Assert-Equal 39 $back.Turn.EstateQueue[0]
    }

    It 'keeps an empty array an array after a round trip' {
        $g = New-TestGame
        $g.Turn.LastRoll = @()
        $back = [GameState]::FromData((ConvertFrom-RonJson (ConvertTo-RonJson $g.ToData())))
        Assert-Equal 0 $back.Turn.LastRoll.Length
        Assert-Equal 0 $back.Turn.DiceTotal()
    }

    It 'produces byte-identical play from the same seed' {
        $a = New-TestPlayedGame -Seed 4242 -Turns 40
        $b = New-TestPlayedGame -Seed 4242 -Turns 40
        # GameId is a fresh GUID per game by design, so it is the one field
        # that is meant to differ.
        $da = $a.ToData(); $da.GameId = ''
        $db = $b.ToData(); $db.GameId = ''
        Assert-Equal (ConvertTo-RonJson $da) (ConvertTo-RonJson $db) 'determinism'
    }

    It 'diverges from a different seed' {
        $a = New-TestPlayedGame -Seed 1 -Turns 40
        $b = New-TestPlayedGame -Seed 2 -Turns 40
        Assert-NotEqual (ConvertTo-RonJson $a.ToData()) (ConvertTo-RonJson $b.ToData())
    }

    It 'stays under a sane size on the wire' {
        # The LAN design sends a full snapshot with every event batch, so this
        # number is a real budget, not trivia.
        $g = New-TestPlayedGame
        $bytes = [Text.Encoding]::UTF8.GetByteCount((ConvertTo-RonJson $g.ToData()))
        Assert-True ($bytes -lt 40000) "snapshot is $bytes bytes"
    }
}

exit (Complete-RonTests)
