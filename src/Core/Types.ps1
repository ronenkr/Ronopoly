# Ronopoly - Core type definitions
#
# EVERY PowerShell class in the project lives in this one file, in dependency
# order (a type must be defined above its first use as a type literal).
#
# Constraints proven on this machine (see plan):
#   * Classes MUST be dot-sourced. Import-Module + a type literal fails with
#     "Unable to find type". Never convert this file to a .psm1.
#   * PS 5.1 fails to parse semicolon-separated class MEMBERS when the class
#     also declares a constructor. One member per line, always.
#   * Declaring any constructor suppresses the implicit parameterless one, so
#     every class here declares its own explicitly (FromData needs it).
#
# Deserialisation contract: every FromData([object]) accepts EITHER a hashtable
# or a PSCustomObject, because dotted member access works uniformly on both and
# ConvertFrom-Json only ever yields the latter.


# ---------------------------------------------------------------------------
# RonData - static conversion helpers, kept as a class (not functions) so class
# methods can call them without depending on script-scope function resolution.
# ---------------------------------------------------------------------------
class RonData {

    # ConvertFrom-Json collapses single-element arrays to scalars and returns
    # $null for absent members. This always yields a real array.
    static [object[]] AsArray([object]$v) {
        if ($null -eq $v) { return @() }
        return @($v)
    }

    static [int[]] AsIntArray([object]$v) {
        $src = [RonData]::AsArray($v)
        $out = New-Object 'int[]' $src.Length
        for ($i = 0; $i -lt $src.Length; $i++) { $out[$i] = [int]$src[$i] }
        return $out
    }

    static [int] AsInt([object]$v, [int]$fallback) {
        if ($null -eq $v) { return $fallback }
        return [int]$v
    }

    static [bool] AsBool([object]$v, [bool]$fallback) {
        if ($null -eq $v) { return $fallback }
        return [bool]$v
    }

    static [string] AsString([object]$v, [string]$fallback) {
        if ($null -eq $v) { return $fallback }
        return [string]$v
    }

    # Recursively normalise PSCustomObject / OrderedDictionary graphs into plain
    # hashtables. Used for the Rules bag, which is free-form by design.
    static [hashtable] AsHashtable([object]$v) {
        $h = @{}
        if ($null -eq $v) { return $h }
        if ($v -is [System.Collections.IDictionary]) {
            foreach ($k in $v.Keys) { $h[[string]$k] = [RonData]::Normalise($v[$k]) }
            return $h
        }
        if ($v -is [psobject]) {
            foreach ($p in $v.PSObject.Properties) { $h[$p.Name] = [RonData]::Normalise($p.Value) }
            return $h
        }
        return $h
    }

    static [object] Normalise([object]$v) {
        if ($null -eq $v) { return $null }
        if ($v -is [string] -or $v -is [int] -or $v -is [bool] -or $v -is [double] -or $v -is [long]) { return $v }
        if ($v -is [System.Collections.IDictionary]) { return [RonData]::AsHashtable($v) }
        if ($v -is [object[]]) {
            $out = @()
            foreach ($item in $v) { $out += ,([RonData]::Normalise($item)) }
            return $out
        }
        if ($v -is [psobject]) { return [RonData]::AsHashtable($v) }
        return $v
    }
}


# ---------------------------------------------------------------------------
# RonRng - deterministic, fully serialisable PRNG.
#
# System.Random is deliberately NOT used: its internal state cannot be captured,
# so a mid-game save or a LAN resync could not reproduce the same dice. This is
# a 31-bit LCG whose entire state is one int, and every intermediate product is
# computed in Int64 where it provably cannot overflow
# (2^31 * 1103515245 ~= 2.4e18 < Int64.MaxValue ~= 9.2e18).
#
# Only the top 15 bits of the state are consumed: the low-order bits of an LCG
# have short periods (bit k repeats every 2^(k+1)) and would produce visibly
# patterned dice.
# ---------------------------------------------------------------------------
class RonRng {
    [int]$Seed
    [int]$State
    [int]$Count

    RonRng() {
        $this.Seed = 0
        $this.State = 12345
        $this.Count = 0
    }

    RonRng([int]$seed) {
        $this.Seed = $seed
        $this.State = [int]((([int64]$seed * 2654435761) + 1013904223) -band 0x7FFFFFFF)
        if ($this.State -eq 0) { $this.State = 12345 }
        $this.Count = 0
    }

    hidden [int] Advance() {
        $this.State = [int]((([int64]$this.State * 1103515245) + 12345) -band 0x7FFFFFFF)
        $this.Count = $this.Count + 1
        return $this.State
    }

    # 0 .. maxExclusive-1
    [int] NextInt([int]$maxExclusive) {
        if ($maxExclusive -le 0) { throw "RonRng.NextInt: maxExclusive must be greater than 0 (got $maxExclusive)" }
        $hi = $this.Advance() -shr 16
        return [int](([int64]$hi * $maxExclusive) -shr 15)
    }

    [int] NextRange([int]$minInclusive, [int]$maxInclusive) {
        return $minInclusive + $this.NextInt($maxInclusive - $minInclusive + 1)
    }

    [double] NextDouble() {
        return ($this.Advance() / 2147483648.0)
    }

    [int] RollDie() {
        return $this.NextInt(6) + 1
    }

    [int[]] Shuffle([int[]]$items) {
        $a = New-Object 'int[]' $items.Length
        [System.Array]::Copy($items, $a, $items.Length)
        for ($i = $a.Length - 1; $i -gt 0; $i--) {
            $j = $this.NextInt($i + 1)
            $t = $a[$i]
            $a[$i] = $a[$j]
            $a[$j] = $t
        }
        return $a
    }

    [RonRng] Clone() {
        $c = [RonRng]::new()
        $c.Seed = $this.Seed
        $c.State = $this.State
        $c.Count = $this.Count
        return $c
    }

    [hashtable] ToData() {
        return @{
            Seed  = $this.Seed
            State = $this.State
            Count = $this.Count
        }
    }

    static [RonRng] FromData([object]$o) {
        $r = [RonRng]::new()
        $r.Seed  = [RonData]::AsInt($o.Seed, 0)
        $r.State = [RonData]::AsInt($o.State, 12345)
        $r.Count = [RonData]::AsInt($o.Count, 0)
        return $r
    }
}


# ---------------------------------------------------------------------------
# PlayerState
# ---------------------------------------------------------------------------
class PlayerState {
    [int]$Id
    [string]$Name
    [string]$Kind             # Human | AI | Remote
    [string]$AiProfile        # Easy | Normal | Hard | Expert | ''
    [string]$Token            # token id from Tokens.psd1
    [int]$Cash
    [int]$Position
    [bool]$InJail
    [int]$JailTurns           # failed escape attempts so far, 0..3
    [int]$JailCards
    [int]$DoublesCount        # consecutive doubles this turn
    [bool]$IsBankrupt
    [int]$BankruptTurn
    [string]$ConnectionState  # Local | Connected | Disconnected | AiTakeover
    [string]$SessionToken

    PlayerState() {
        $this.Id = -1
        $this.Name = ''
        $this.Kind = 'Human'
        $this.AiProfile = ''
        $this.Token = ''
        $this.Cash = 0
        $this.Position = 0
        $this.InJail = $false
        $this.JailTurns = 0
        $this.JailCards = 0
        $this.DoublesCount = 0
        $this.IsBankrupt = $false
        $this.BankruptTurn = -1
        $this.ConnectionState = 'Local'
        $this.SessionToken = ''
    }

    # True when this seat's decisions are produced by the AI module, whether it
    # was created as a bot or taken over after a disconnect.
    [bool] IsAiControlled() {
        if ($this.Kind -eq 'AI') { return $true }
        return ($this.ConnectionState -eq 'AiTakeover')
    }

    [PlayerState] Clone() {
        return [PlayerState]::FromData($this.ToData())
    }

    [hashtable] ToData() {
        return @{
            Id              = $this.Id
            Name            = $this.Name
            Kind            = $this.Kind
            AiProfile       = $this.AiProfile
            Token           = $this.Token
            Cash            = $this.Cash
            Position        = $this.Position
            InJail          = $this.InJail
            JailTurns       = $this.JailTurns
            JailCards       = $this.JailCards
            DoublesCount    = $this.DoublesCount
            IsBankrupt      = $this.IsBankrupt
            BankruptTurn    = $this.BankruptTurn
            ConnectionState = $this.ConnectionState
            SessionToken    = $this.SessionToken
        }
    }

    static [PlayerState] FromData([object]$o) {
        $p = [PlayerState]::new()
        $p.Id              = [RonData]::AsInt($o.Id, -1)
        $p.Name            = [RonData]::AsString($o.Name, '')
        $p.Kind            = [RonData]::AsString($o.Kind, 'Human')
        $p.AiProfile       = [RonData]::AsString($o.AiProfile, '')
        $p.Token           = [RonData]::AsString($o.Token, '')
        $p.Cash            = [RonData]::AsInt($o.Cash, 0)
        $p.Position        = [RonData]::AsInt($o.Position, 0)
        $p.InJail          = [RonData]::AsBool($o.InJail, $false)
        $p.JailTurns       = [RonData]::AsInt($o.JailTurns, 0)
        $p.JailCards       = [RonData]::AsInt($o.JailCards, 0)
        $p.DoublesCount    = [RonData]::AsInt($o.DoublesCount, 0)
        $p.IsBankrupt      = [RonData]::AsBool($o.IsBankrupt, $false)
        $p.BankruptTurn    = [RonData]::AsInt($o.BankruptTurn, -1)
        $p.ConnectionState = [RonData]::AsString($o.ConnectionState, 'Local')
        $p.SessionToken    = [RonData]::AsString($o.SessionToken, '')
        return $p
    }
}


# ---------------------------------------------------------------------------
# PropertyState - per-space ownership. Exists for all 40 indices (non-deed
# spaces simply stay owner -1 / 0 houses), so lookups never need bounds logic.
# ---------------------------------------------------------------------------
class PropertyState {
    [int]$Index
    [int]$OwnerId             # -1 = bank
    [int]$Houses              # 0..4, 5 = hotel
    [bool]$Mortgaged

    PropertyState() {
        $this.Index = -1
        $this.OwnerId = -1
        $this.Houses = 0
        $this.Mortgaged = $false
    }

    PropertyState([int]$index) {
        $this.Index = $index
        $this.OwnerId = -1
        $this.Houses = 0
        $this.Mortgaged = $false
    }

    [bool] HasHotel() {
        return ($this.Houses -eq 5)
    }

    [hashtable] ToData() {
        return @{
            Index     = $this.Index
            OwnerId   = $this.OwnerId
            Houses    = $this.Houses
            Mortgaged = $this.Mortgaged
        }
    }

    static [PropertyState] FromData([object]$o) {
        $p = [PropertyState]::new()
        $p.Index     = [RonData]::AsInt($o.Index, -1)
        $p.OwnerId   = [RonData]::AsInt($o.OwnerId, -1)
        $p.Houses    = [RonData]::AsInt($o.Houses, 0)
        $p.Mortgaged = [RonData]::AsBool($o.Mortgaged, $false)
        return $p
    }
}


# ---------------------------------------------------------------------------
# BankState - the finite building supply is a real rule, not decoration:
# building a hotel returns 4 houses to the bank, which is what makes the
# 32-house shortage strategically live.
# ---------------------------------------------------------------------------
class BankState {
    [int]$HousesAvailable
    [int]$HotelsAvailable
    [int]$FreeParkingPot      # only accumulates under the FreeParkingJackpot rule

    BankState() {
        $this.HousesAvailable = 32
        $this.HotelsAvailable = 12
        $this.FreeParkingPot = 0
    }

    [hashtable] ToData() {
        return @{
            HousesAvailable = $this.HousesAvailable
            HotelsAvailable = $this.HotelsAvailable
            FreeParkingPot  = $this.FreeParkingPot
        }
    }

    static [BankState] FromData([object]$o) {
        $b = [BankState]::new()
        $b.HousesAvailable = [RonData]::AsInt($o.HousesAvailable, 32)
        $b.HotelsAvailable = [RonData]::AsInt($o.HotelsAvailable, 12)
        $b.FreeParkingPot  = [RonData]::AsInt($o.FreeParkingPot, 0)
        return $b
    }
}


# ---------------------------------------------------------------------------
# DeckState - a plain queue of card ids, front at index 0.
#
# Modelled as a queue rather than "shuffled order + draw pointer" because the
# two Get Out of Jail Free cards LEAVE the deck while held and return to the
# bottom when used or sold - which a fixed order plus pointer cannot express.
# Array rebuilds use Array.Copy rather than $a[1..($n-1)] because that range
# operator silently REVERSES when the array has a single element.
# ---------------------------------------------------------------------------
class DeckState {
    [string]$Name
    [int[]]$Cards

    DeckState() {
        $this.Name = ''
        $this.Cards = @()
    }

    DeckState([string]$name, [int[]]$cards) {
        $this.Name = $name
        $this.Cards = $cards
    }

    [int] Count() {
        return $this.Cards.Length
    }

    [int] Draw() {
        if ($this.Cards.Length -eq 0) { throw "DeckState.Draw: deck '$($this.Name)' is empty" }
        $id = $this.Cards[0]
        $rest = New-Object 'int[]' ($this.Cards.Length - 1)
        if ($rest.Length -gt 0) { [System.Array]::Copy($this.Cards, 1, $rest, 0, $rest.Length) }
        $this.Cards = $rest
        return $id
    }

    [void] Enqueue([int]$id) {
        $n = New-Object 'int[]' ($this.Cards.Length + 1)
        [System.Array]::Copy($this.Cards, 0, $n, 0, $this.Cards.Length)
        $n[$this.Cards.Length] = $id
        $this.Cards = $n
    }

    [hashtable] ToData() {
        return @{
            Name  = $this.Name
            Cards = $this.Cards
        }
    }

    static [DeckState] FromData([object]$o) {
        $d = [DeckState]::new()
        $d.Name  = [RonData]::AsString($o.Name, '')
        $d.Cards = [RonData]::AsIntArray($o.Cards)
        return $d
    }
}


# ---------------------------------------------------------------------------
# AuctionState
# ---------------------------------------------------------------------------
class AuctionState {
    [int]$SpaceIndex
    [int]$CurrentBid
    [int]$HighBidderId        # -1 = no bid yet
    [int[]]$ActiveBidders     # player ids still in, in turn order
    [int]$TurnIdx             # index into ActiveBidders
    [int]$MinIncrement
    [bool]$IsEstateAuction    # bankrupt-to-bank estate liquidation

    AuctionState() {
        $this.SpaceIndex = -1
        $this.CurrentBid = 0
        $this.HighBidderId = -1
        $this.ActiveBidders = @()
        $this.TurnIdx = 0
        $this.MinIncrement = 1
        $this.IsEstateAuction = $false
    }

    [int] CurrentBidderId() {
        if ($this.ActiveBidders.Length -eq 0) { return -1 }
        return $this.ActiveBidders[$this.TurnIdx % $this.ActiveBidders.Length]
    }

    [hashtable] ToData() {
        return @{
            SpaceIndex      = $this.SpaceIndex
            CurrentBid      = $this.CurrentBid
            HighBidderId    = $this.HighBidderId
            ActiveBidders   = $this.ActiveBidders
            TurnIdx         = $this.TurnIdx
            MinIncrement    = $this.MinIncrement
            IsEstateAuction = $this.IsEstateAuction
        }
    }

    static [AuctionState] FromData([object]$o) {
        $a = [AuctionState]::new()
        if ($null -eq $o) { return $a }
        $a.SpaceIndex      = [RonData]::AsInt($o.SpaceIndex, -1)
        $a.CurrentBid      = [RonData]::AsInt($o.CurrentBid, 0)
        $a.HighBidderId    = [RonData]::AsInt($o.HighBidderId, -1)
        $a.ActiveBidders   = [RonData]::AsIntArray($o.ActiveBidders)
        $a.TurnIdx         = [RonData]::AsInt($o.TurnIdx, 0)
        $a.MinIncrement    = [RonData]::AsInt($o.MinIncrement, 1)
        $a.IsEstateAuction = [RonData]::AsBool($o.IsEstateAuction, $false)
        return $a
    }
}


# ---------------------------------------------------------------------------
# TradeOffer - "Give" is always from the proposer's point of view.
# ---------------------------------------------------------------------------
class TradeOffer {
    [int]$FromId
    [int]$ToId
    [int[]]$GiveProperties
    [int[]]$GetProperties
    [int]$GiveCash
    [int]$GetCash
    [int]$GiveJailCards
    [int]$GetJailCards

    TradeOffer() {
        $this.FromId = -1
        $this.ToId = -1
        $this.GiveProperties = @()
        $this.GetProperties = @()
        $this.GiveCash = 0
        $this.GetCash = 0
        $this.GiveJailCards = 0
        $this.GetJailCards = 0
    }

    [bool] IsEmpty() {
        if ($this.GiveProperties.Length -gt 0) { return $false }
        if ($this.GetProperties.Length -gt 0) { return $false }
        if ($this.GiveCash -ne 0) { return $false }
        if ($this.GetCash -ne 0) { return $false }
        if ($this.GiveJailCards -ne 0) { return $false }
        if ($this.GetJailCards -ne 0) { return $false }
        return $true
    }

    [hashtable] ToData() {
        return @{
            FromId         = $this.FromId
            ToId           = $this.ToId
            GiveProperties = $this.GiveProperties
            GetProperties  = $this.GetProperties
            GiveCash       = $this.GiveCash
            GetCash        = $this.GetCash
            GiveJailCards  = $this.GiveJailCards
            GetJailCards   = $this.GetJailCards
        }
    }

    static [TradeOffer] FromData([object]$o) {
        $t = [TradeOffer]::new()
        if ($null -eq $o) { return $t }
        $t.FromId         = [RonData]::AsInt($o.FromId, -1)
        $t.ToId           = [RonData]::AsInt($o.ToId, -1)
        $t.GiveProperties = [RonData]::AsIntArray($o.GiveProperties)
        $t.GetProperties  = [RonData]::AsIntArray($o.GetProperties)
        $t.GiveCash       = [RonData]::AsInt($o.GiveCash, 0)
        $t.GetCash        = [RonData]::AsInt($o.GetCash, 0)
        $t.GiveJailCards  = [RonData]::AsInt($o.GiveJailCards, 0)
        $t.GetJailCards   = [RonData]::AsInt($o.GetJailCards, 0)
        return $t
    }
}


# ---------------------------------------------------------------------------
# DebtContext - an unpaid obligation that blocks the turn until resolved.
# Depth guards the bankruptcy cascade (a creditor can be bankrupted by the
# forced 10% interest on mortgaged property they just received).
# ---------------------------------------------------------------------------
class DebtContext {
    [int]$DebtorId
    [int]$CreditorId          # -1 = bank
    [int]$Amount
    [string]$Reason
    [int]$Depth

    DebtContext() {
        $this.DebtorId = -1
        $this.CreditorId = -1
        $this.Amount = 0
        $this.Reason = ''
        $this.Depth = 0
    }

    [hashtable] ToData() {
        return @{
            DebtorId   = $this.DebtorId
            CreditorId = $this.CreditorId
            Amount     = $this.Amount
            Reason     = $this.Reason
            Depth      = $this.Depth
        }
    }

    static [DebtContext] FromData([object]$o) {
        $d = [DebtContext]::new()
        if ($null -eq $o) { return $d }
        $d.DebtorId   = [RonData]::AsInt($o.DebtorId, -1)
        $d.CreditorId = [RonData]::AsInt($o.CreditorId, -1)
        $d.Amount     = [RonData]::AsInt($o.Amount, 0)
        $d.Reason     = [RonData]::AsString($o.Reason, '')
        $d.Depth      = [RonData]::AsInt($o.Depth, 0)
        return $d
    }
}


# ---------------------------------------------------------------------------
# TurnState - the FSM cursor. Phase is the single source of truth for what the
# engine will accept next; Get-LegalActions is derived entirely from it.
#
# Phases:
#   AwaitRoll          current player may roll (or manage / trade / build)
#   AwaitJailChoice    in jail: pay, use card, or roll for doubles
#   AwaitBuyDecision   landed on an unowned deed
#   AwaitAuction       auction in progress
#   AwaitDebt          an obligation must be settled or bankruptcy declared
#   AwaitTradeResponse an offer is pending with another player
#   AwaitEndTurn       everything resolved; may end turn or keep managing
#   GameOver           terminal
# ---------------------------------------------------------------------------
class TurnState {
    [int]$CurrentPlayerId
    [string]$Phase
    [int[]]$LastRoll
    [int]$RollCount           # rolls taken this turn (doubles chains)
    [string]$PendingDecision  # free-form tag for the UI overlay to show
    [int]$PendingSpaceIndex
    [int]$TurnNumber
    [bool]$ExtraTurn          # rolled doubles: roll again after resolving
    [DebtContext]$Debt
    [AuctionState]$Auction
    [TradeOffer]$Trade
    [int]$PendingCardId
    [string]$PendingCardDeck

    # Obligations still to settle from one card or rent event. A card like
    # "pay each player 50" creates N payments at once, but only ONE debt can be
    # open at a time, so the rest queue here and are drained by
    # Resolve-RonPendingPayments after each settlement.
    # Elements are @{ D = debtor, C = creditor (-1 bank), A = amount, R = reason }.
    [object[]]$Pending

    # Deeds from a bankrupt-to-bank estate still to be auctioned, one lot at a
    # time. It lives on the TURN rather than on AuctionState so that a winner
    # who has to liquidate mid-estate (and thus opens a debt) does not lose the
    # remaining lots.
    [int[]]$EstateQueue

    # Dice total a jailed player must still move after the compulsory third-turn
    # fine. Held here because paying that fine can open a debt, and the move has
    # to survive the liquidation that follows. 0 means nothing pending.
    [int]$PendingJailMove

    # Trade offers this player has made this turn. Capped by the AI so a bot
    # cannot loop forever re-proposing a deal that keeps being refused, and
    # used by the UI to grey out the trade button.
    [int]$TradesProposed

    TurnState() {
        $this.CurrentPlayerId = -1
        $this.Phase = 'AwaitRoll'
        $this.LastRoll = @()
        $this.RollCount = 0
        $this.PendingDecision = ''
        $this.PendingSpaceIndex = -1
        $this.TurnNumber = 0
        $this.ExtraTurn = $false
        $this.Debt = $null
        $this.Auction = $null
        $this.Trade = $null
        $this.PendingCardId = -1
        $this.PendingCardDeck = ''
        $this.Pending = @()
        $this.EstateQueue = @()
        $this.PendingJailMove = 0
        $this.TradesProposed = 0
    }

    [int] DiceTotal() {
        $t = 0
        foreach ($d in $this.LastRoll) { $t += $d }
        return $t
    }

    [bool] IsDoubles() {
        if ($this.LastRoll.Length -ne 2) { return $false }
        return ($this.LastRoll[0] -eq $this.LastRoll[1])
    }

    [hashtable] ToData() {
        $h = @{
            CurrentPlayerId   = $this.CurrentPlayerId
            Phase             = $this.Phase
            LastRoll          = $this.LastRoll
            RollCount         = $this.RollCount
            PendingDecision   = $this.PendingDecision
            PendingSpaceIndex = $this.PendingSpaceIndex
            TurnNumber        = $this.TurnNumber
            ExtraTurn         = $this.ExtraTurn
            PendingCardId     = $this.PendingCardId
            PendingCardDeck   = $this.PendingCardDeck
            Pending           = $this.Pending
            EstateQueue       = $this.EstateQueue
            PendingJailMove   = $this.PendingJailMove
            TradesProposed    = $this.TradesProposed
            Debt              = $null
            Auction           = $null
            Trade             = $null
        }
        if ($null -ne $this.Debt)    { $h.Debt    = $this.Debt.ToData() }
        if ($null -ne $this.Auction) { $h.Auction = $this.Auction.ToData() }
        if ($null -ne $this.Trade)   { $h.Trade   = $this.Trade.ToData() }
        return $h
    }

    static [TurnState] FromData([object]$o) {
        $t = [TurnState]::new()
        $t.CurrentPlayerId   = [RonData]::AsInt($o.CurrentPlayerId, -1)
        $t.Phase             = [RonData]::AsString($o.Phase, 'AwaitRoll')
        $t.LastRoll          = [RonData]::AsIntArray($o.LastRoll)
        $t.RollCount         = [RonData]::AsInt($o.RollCount, 0)
        $t.PendingDecision   = [RonData]::AsString($o.PendingDecision, '')
        $t.PendingSpaceIndex = [RonData]::AsInt($o.PendingSpaceIndex, -1)
        $t.TurnNumber        = [RonData]::AsInt($o.TurnNumber, 0)
        $t.ExtraTurn         = [RonData]::AsBool($o.ExtraTurn, $false)
        $t.PendingCardId     = [RonData]::AsInt($o.PendingCardId, -1)
        $t.PendingCardDeck   = [RonData]::AsString($o.PendingCardDeck, '')
        $t.Pending           = [RonData]::AsArray($o.Pending)
        $t.EstateQueue       = [RonData]::AsIntArray($o.EstateQueue)
        $t.PendingJailMove   = [RonData]::AsInt($o.PendingJailMove, 0)
        $t.TradesProposed    = [RonData]::AsInt($o.TradesProposed, 0)
        if ($null -ne $o.Debt)    { $t.Debt    = [DebtContext]::FromData($o.Debt) }
        if ($null -ne $o.Auction) { $t.Auction = [AuctionState]::FromData($o.Auction) }
        if ($null -ne $o.Trade)   { $t.Trade   = [TradeOffer]::FromData($o.Trade) }
        return $t
    }
}


# ---------------------------------------------------------------------------
# GameState - the whole game. Passed explicitly to every engine function;
# the engine holds no ambient state of its own.
#
# Version increments once per applied action and is what LAN clients use to
# detect a gap and request a resync.
# ---------------------------------------------------------------------------
class GameState {
    [int]$SchemaVersion
    [string]$GameId
    [int]$Seed
    [int]$Version
    [hashtable]$Rules
    [RonRng]$Rng
    [PlayerState[]]$Players
    [PropertyState[]]$Properties
    [BankState]$Bank
    [DeckState]$Chance
    [DeckState]$Chest
    [TurnState]$Turn
    [int[]]$Order             # player ids in seating order
    [bool]$IsOver
    [int]$WinnerId

    # Cash held by players plus the Free Parking pot. Maintained ONLY by
    # Add-RonBankMoney / Remove-RonBankMoney; player-to-player transfers leave
    # it untouched. Assert-RonInvariant checks it against the actual sum after
    # every event in simulation mode, which is what catches double-payments,
    # missed debits and phantom money in bankruptcy transfers.
    [int]$MoneyInPlay

    GameState() {
        $this.SchemaVersion = 1
        $this.GameId = ''
        $this.Seed = 0
        $this.Version = 0
        $this.Rules = @{}
        $this.Rng = [RonRng]::new()
        $this.Players = @()
        $this.Properties = @()
        $this.Bank = [BankState]::new()
        $this.Chance = [DeckState]::new()
        $this.Chest = [DeckState]::new()
        $this.Turn = [TurnState]::new()
        $this.Order = @()
        $this.IsOver = $false
        $this.WinnerId = -1
        $this.MoneyInPlay = 0
    }

    [PlayerState] GetPlayer([int]$id) {
        foreach ($p in $this.Players) {
            if ($p.Id -eq $id) { return $p }
        }
        throw "GameState.GetPlayer: no player with id $id"
    }

    [PlayerState] CurrentPlayer() {
        return $this.GetPlayer($this.Turn.CurrentPlayerId)
    }

    [PropertyState] GetProperty([int]$index) {
        return $this.Properties[$index]
    }

    [PlayerState[]] ActivePlayers() {
        $out = @()
        foreach ($id in $this.Order) {
            $p = $this.GetPlayer($id)
            if (-not $p.IsBankrupt) { $out += $p }
        }
        return $out
    }

    [bool] RuleOn([string]$name) {
        if (-not $this.Rules.ContainsKey($name)) { return $false }
        return [bool]$this.Rules[$name]
    }

    [int] RuleInt([string]$name, [int]$fallback) {
        if (-not $this.Rules.ContainsKey($name)) { return $fallback }
        return [int]$this.Rules[$name]
    }

    [GameState] Clone() {
        return [GameState]::FromData($this.ToData())
    }

    [hashtable] ToData() {
        $pl = @()
        foreach ($p in $this.Players) { $pl += ,$p.ToData() }
        $pr = @()
        foreach ($p in $this.Properties) { $pr += ,$p.ToData() }
        return @{
            SchemaVersion = $this.SchemaVersion
            GameId        = $this.GameId
            Seed          = $this.Seed
            Version       = $this.Version
            Rules         = $this.Rules
            Rng           = $this.Rng.ToData()
            Players       = $pl
            Properties    = $pr
            Bank          = $this.Bank.ToData()
            Chance        = $this.Chance.ToData()
            Chest         = $this.Chest.ToData()
            Turn          = $this.Turn.ToData()
            Order         = $this.Order
            IsOver        = $this.IsOver
            WinnerId      = $this.WinnerId
            MoneyInPlay   = $this.MoneyInPlay
        }
    }

    static [GameState] FromData([object]$o) {
        $g = [GameState]::new()
        $g.SchemaVersion = [RonData]::AsInt($o.SchemaVersion, 1)
        $g.GameId        = [RonData]::AsString($o.GameId, '')
        $g.Seed          = [RonData]::AsInt($o.Seed, 0)
        $g.Version       = [RonData]::AsInt($o.Version, 0)
        $g.Rules         = [RonData]::AsHashtable($o.Rules)
        $g.Rng           = [RonRng]::FromData($o.Rng)

        $src = [RonData]::AsArray($o.Players)
        $arrPlayers = New-Object 'PlayerState[]' $src.Length
        for ($i = 0; $i -lt $src.Length; $i++) { $arrPlayers[$i] = [PlayerState]::FromData($src[$i]) }
        $g.Players = $arrPlayers

        $src = [RonData]::AsArray($o.Properties)
        $arrProps = New-Object 'PropertyState[]' $src.Length
        for ($i = 0; $i -lt $src.Length; $i++) { $arrProps[$i] = [PropertyState]::FromData($src[$i]) }
        $g.Properties = $arrProps

        $g.Bank     = [BankState]::FromData($o.Bank)
        $g.Chance   = [DeckState]::FromData($o.Chance)
        $g.Chest    = [DeckState]::FromData($o.Chest)
        $g.Turn     = [TurnState]::FromData($o.Turn)
        $g.Order    = [RonData]::AsIntArray($o.Order)
        $g.IsOver   = [RonData]::AsBool($o.IsOver, $false)
        $g.WinnerId = [RonData]::AsInt($o.WinnerId, -1)
        $g.MoneyInPlay = [RonData]::AsInt($o.MoneyInPlay, 0)
        return $g
    }
}
