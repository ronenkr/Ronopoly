#
# Ronopoly - game construction, derived queries and the invariant checker.
#

# Players is an array of @{ Name; Kind; AiProfile; Token }.
# Seed 0 means "pick one" - the chosen value is stored so any game, including
# one that crashed 800 turns deep in the simulator, can be reproduced exactly.
function New-RonGame {
    param(
        [Parameter(Mandatory)][object[]]$Players,
        [int]$Seed = 0,
        [hashtable]$Rules = $null,
        [switch]$RandomiseOrder
    )
    if ($Players.Count -lt 2) { throw "New-RonGame: need at least 2 players, got $($Players.Count)" }
    if ($Players.Count -gt 8) { throw "New-RonGame: at most 8 players, got $($Players.Count)" }

    $board = Get-RonBoard
    if ($Seed -eq 0) { $Seed = [int](Get-Random -Minimum 1 -Maximum 2147483647) }
    if ($null -eq $Rules) { $Rules = Get-RonDefaultRules }

    $g = [GameState]::new()
    $g.GameId  = New-RonId
    $g.Seed    = $Seed
    $g.Rng     = [RonRng]::new($Seed)
    $g.Rules   = $Rules
    $g.Version = 0

    $ps = New-Object 'PlayerState[]' $Players.Count
    for ($i = 0; $i -lt $Players.Count; $i++) {
        $spec = $Players[$i]
        $p = [PlayerState]::new()
        $p.Id       = $i
        $p.Name     = [string]$spec.Name
        $p.Kind     = [string]$spec.Kind
        $p.Cash     = [int]$board.StartingCash
        $p.Position = [int]$board.GoIndex
        if ($null -ne $spec.AiProfile) { $p.AiProfile = [string]$spec.AiProfile }
        if ($null -ne $spec.Token)     { $p.Token     = [string]$spec.Token }
        # A Remote seat is one nobody has claimed YET. Marking it Connected here
        # would make Get-RonFreeSeat think it was already taken and turn every
        # joiner away as "game full".
        if ($p.Kind -eq 'Remote')      { $p.ConnectionState = 'Disconnected' }
        $ps[$i] = $p
    }
    $g.Players = $ps

    $seats = New-Object 'int[]' $Players.Count
    for ($i = 0; $i -lt $Players.Count; $i++) { $seats[$i] = $i }
    if ($RandomiseOrder) { $seats = $g.Rng.Shuffle($seats) }
    $g.Order = $seats

    $deeds = New-Object 'PropertyState[]' $board.SpaceCount
    for ($i = 0; $i -lt $board.SpaceCount; $i++) { $deeds[$i] = [PropertyState]::new($i) }
    $g.Properties = $deeds

    $g.Bank = [BankState]::new()
    $g.Bank.HousesAvailable = [int]$board.TotalHouses
    $g.Bank.HotelsAvailable = [int]$board.TotalHotels

    $cards = Get-RonCards
    $chanceIds = New-Object 'int[]' $cards.Chance.Count
    for ($i = 0; $i -lt $cards.Chance.Count; $i++) { $chanceIds[$i] = [int]$cards.Chance[$i].Id }
    $chestIds = New-Object 'int[]' $cards.Chest.Count
    for ($i = 0; $i -lt $cards.Chest.Count; $i++) { $chestIds[$i] = [int]$cards.Chest[$i].Id }
    $g.Chance = [DeckState]::new('Chance', $g.Rng.Shuffle($chanceIds))
    $g.Chest  = [DeckState]::new('Chest',  $g.Rng.Shuffle($chestIds))

    $g.Turn = [TurnState]::new()
    $g.Turn.CurrentPlayerId = $g.Order[0]
    $g.Turn.Phase = 'AwaitRoll'
    $g.Turn.TurnNumber = 1

    $g.MoneyInPlay = [int]$board.StartingCash * $Players.Count
    return $g
}

# --- derived queries -------------------------------------------------------

function Get-RonOwnedIndices {
    param([GameState]$State, [int]$PlayerId)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    $props = $State.Properties
    $deeds = $bi.Deeds
    $out = New-Object "int[]" $deeds.Length
    $n = 0
    foreach ($i in $deeds) {
        if ($props[$i].OwnerId -eq $PlayerId) { $out[$n] = $i; $n++ }
    }
    $exact = New-Object "int[]" $n
    [System.Array]::Copy($out, $exact, $n)
    return $exact
}

# A monopoly is defined by OWNERSHIP in the printed rules; mortgage status is
# handled separately, via MonopolyDoubleRequiresUnmortgagedGroup.
function Test-RonHasMonopoly {
    param([GameState]$State, [int]$PlayerId, [string]$Group)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    if (-not $bi.Groups.ContainsKey($Group)) { return $false }
    $props = $State.Properties
    foreach ($i in $bi.Groups[$Group]) {
        if ($props[$i].OwnerId -ne $PlayerId) { return $false }
    }
    return $true
}

# Same test keyed by a space rather than a group name, so callers that already
# have an index skip the group lookup entirely.
function Test-RonSpaceInMonopoly {
    param([GameState]$State, [int]$PlayerId, [int]$SpaceIndex)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    $members = $bi.GroupOf[$SpaceIndex]
    if ($members.Length -eq 0) { return $false }
    $props = $State.Properties
    foreach ($i in $members) {
        if ($props[$i].OwnerId -ne $PlayerId) { return $false }
    }
    return $true
}

function Test-RonGroupHasBuildings {
    param([GameState]$State, [string]$Group)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    if (-not $bi.Groups.ContainsKey($Group)) { return $false }
    $props = $State.Properties
    foreach ($i in $bi.Groups[$Group]) {
        if ($props[$i].Houses -gt 0) { return $true }
    }
    return $false
}

function Get-RonNetWorth {
    param([GameState]$State, [int]$PlayerId)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    $props = $State.Properties
    $total = $State.Players[$PlayerId].Cash
    foreach ($i in $bi.Deeds) {
        $deed = $props[$i]
        if ($deed.OwnerId -ne $PlayerId) { continue }
        if ($deed.Mortgaged) { $total += $bi.Mortgage[$i] } else { $total += $bi.Price[$i] }
        # Buildings liquidate at half cost, so that is their worth in the only
        # situation where net worth actually matters.
        if ($deed.Houses -gt 0) { $total += [int]($deed.Houses * $bi.HouseCost[$i] / 2) }
    }
    return $total
}

# Cash a player could raise right now without trading: cash in hand, plus
# half-price building sales, plus mortgage values. Drives both the debt UI and
# the AI's "can I survive this?" check.
function Get-RonLiquidatableCash {
    param([GameState]$State, [int]$PlayerId)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    $props = $State.Properties
    $total = $State.Players[$PlayerId].Cash
    foreach ($i in $bi.Deeds) {
        $deed = $props[$i]
        if ($deed.OwnerId -ne $PlayerId) { continue }
        if ($deed.Houses -gt 0)   { $total += [int]($deed.Houses * $bi.HouseCost[$i] / 2) }
        if (-not $deed.Mortgaged) { $total += $bi.Mortgage[$i] }
    }
    return $total
}

# --- invariants ------------------------------------------------------------
#
# Run after every event under -AssertInvariants in the simulator. A few hundred
# integer operations, so it can stay on for a full 1000-game run.

function Assert-RonInvariant {
    param([Parameter(Mandatory)][GameState]$State)
    $board = Get-RonBoard
    $bad = New-Object System.Collections.ArrayList

    # 1. Money conservation. The highest-value check in the whole suite: it
    #    catches double-payments, missed debits and phantom money in bankruptcy
    #    transfers without anyone having had to predict those bugs.
    $cash = 0
    foreach ($p in $State.Players) { $cash += $p.Cash }
    $cash += $State.Bank.FreeParkingPot
    if ($cash -ne $State.MoneyInPlay) {
        [void]$bad.Add("money: players+pot = $cash but MoneyInPlay = $($State.MoneyInPlay)")
    }

    # 2. Building supply is conserved (a hotel is 1 hotel, not 5 houses).
    if (-not $State.RuleOn('UnlimitedBuildings')) {
        $houses = 0
        $hotels = 0
        foreach ($i in (Get-RonDeedIndices)) {
            $h = $State.Properties[$i].Houses
            if ($h -eq 5) { $hotels++ } elseif ($h -gt 0) { $houses += $h }
        }
        if (($houses + $State.Bank.HousesAvailable) -ne [int]$board.TotalHouses) {
            [void]$bad.Add("houses: $houses on board + $($State.Bank.HousesAvailable) in bank <> $($board.TotalHouses)")
        }
        if (($hotels + $State.Bank.HotelsAvailable) -ne [int]$board.TotalHotels) {
            [void]$bad.Add("hotels: $hotels on board + $($State.Bank.HotelsAvailable) in bank <> $($board.TotalHotels)")
        }
    }

    # 3. Exactly two Get Out of Jail Free cards exist, held or in a deck.
    $held = 0
    foreach ($p in $State.Players) { $held += $p.JailCards }
    $inDecks = 0
    $cards = Get-RonCards
    foreach ($id in $State.Chance.Cards) { if ($cards.Chance[$id].Kind -eq 'GetOutOfJailFree') { $inDecks++ } }
    foreach ($id in $State.Chest.Cards)  { if ($cards.Chest[$id].Kind  -eq 'GetOutOfJailFree') { $inDecks++ } }
    if (($held + $inDecks) -ne 2) {
        [void]$bad.Add("jail cards: $held held + $inDecks in decks <> 2")
    }

    # 4. Structural sanity.
    # Players[i].Id must equal i: the hot paths index the array by player id
    # directly instead of paying for GetPlayer's linear search.
    for ($i = 0; $i -lt $State.Players.Length; $i++) {
        if ($State.Players[$i].Id -ne $i) { [void]$bad.Add("Players[$i].Id is $($State.Players[$i].Id)") }
    }
    foreach ($p in $State.Players) {
        if ($p.Cash -lt 0)                            { [void]$bad.Add("$($p.Name) has negative cash $($p.Cash)") }
        if ($p.Position -lt 0 -or $p.Position -ge 40) { [void]$bad.Add("$($p.Name) is off the board at $($p.Position)") }
        if ($p.IsBankrupt -and $p.Cash -ne 0)         { [void]$bad.Add("bankrupt $($p.Name) still holds $($p.Cash)") }
    }
    for ($i = 0; $i -lt $board.SpaceCount; $i++) {
        $deed = $State.Properties[$i]
        if ($deed.Index -ne $i) { [void]$bad.Add("property $i has Index $($deed.Index)") }
        if ($deed.Houses -gt 0) {
            if (-not (Test-RonIsStreet $i)) { [void]$bad.Add("buildings on non-street $i") }
            if ($deed.Mortgaged)            { [void]$bad.Add("$(Get-RonSpaceName $i) is mortgaged but developed") }
        }
        if ($deed.OwnerId -ge 0 -and $State.GetPlayer($deed.OwnerId).IsBankrupt) {
            [void]$bad.Add("bankrupt player still owns $(Get-RonSpaceName $i)")
        }
    }

    if ($bad.Count -gt 0) {
        throw ("Invariant violation (seed $($State.Seed), version $($State.Version)):" +
               [Environment]::NewLine + ($bad.ToArray() -join [Environment]::NewLine))
    }
}

# --- save and load ---------------------------------------------------------
#
# Straight over the serialisation the Serialization tests already cover, so a
# saved game restores the RNG stream too: reload a save and the dice come up
# exactly as they would have.

function Save-RonGame {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][string]$Path
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $payload = [pscustomobject]@{
        SavedUtc = (Get-Date).ToUniversalTime().ToString('o')
        Turn     = $State.Turn.TurnNumber
        Players  = @($State.Players | ForEach-Object { $_.Name })
        State    = $State.ToData()
    }
    # -Encoding utf8 is mandatory: Set-Content defaults to the system ANSI
    # codepage on 5.1 and would mangle any non-ASCII player name.
    Set-Content -LiteralPath $Path -Value (ConvertTo-RonJson $payload) -Encoding utf8
    return $Path
}

function Import-RonSavedGame {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Import-RonSavedGame: no save at '$Path'" }
    $payload = ConvertFrom-RonJson (Get-Content -LiteralPath $Path -Raw -Encoding UTF8)
    if ($null -eq $payload.State) { throw "Import-RonSavedGame: '$Path' is not a Ronopoly save" }
    return [GameState]::FromData($payload.State)
}

# Newest first, with just enough detail for a picker.
function Get-RonSavedGames {
    $dir = Get-RonPath 'Saves'
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    $out = New-Object System.Collections.ArrayList
    foreach ($file in (Get-ChildItem -LiteralPath $dir -Filter '*.json' -File | Sort-Object LastWriteTime -Descending)) {
        $summary = ''
        $turn = 0
        try {
            $payload = ConvertFrom-RonJson (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8)
            $turn = [int]$payload.Turn
            $summary = (@($payload.Players) -join ', ')
        }
        catch { $summary = '(unreadable)' }
        [void]$out.Add([pscustomobject]@{
            Path    = $file.FullName
            Name    = $file.BaseName
            When    = $file.LastWriteTime
            Turn    = $turn
            Players = $summary
        })
    }
    return $out.ToArray()
}
