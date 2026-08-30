#
# Ronopoly - AI valuation.
#
# Every AI decision reduces to one primitive: what is this deed worth TO ME,
# right now, in pounds. Buying, bidding, building, mortgaging and trading are
# then all comparisons against that number.
#

$script:RonReserveCacheKey   = ''
$script:RonReserveCacheValue = 0

# Landing frequency and payback period, not price. The orange and red groups
# sit one to two dice rolls past Jail - the most-visited region of the board -
# and comfortably out-earn the dark blues despite costing far less.
$script:RonGroupDesirability = @{
    Orange    = 1.30
    Red       = 1.22
    LightBlue = 1.18
    Yellow    = 1.12
    Pink      = 1.10
    DarkBlue  = 1.00
    Green     = 0.92
    Brown     = 0.85
    Station   = 1.05
    Utility   = 0.70
}

function Get-RonGroupDesirability {
    param([string]$Group)
    if ([string]::IsNullOrEmpty($Group)) { return 1.0 }
    if (-not $script:RonGroupDesirability.ContainsKey($Group)) { return 1.0 }
    return [double]$script:RonGroupDesirability[$Group]
}

function Get-RonPropertyValue {
    param([GameState]$State, [int]$PlayerId, [int]$SpaceIndex)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    if (-not $bi.IsDeed[$SpaceIndex]) { return 0 }

    $group   = $bi.Group[$SpaceIndex]
    $members = $bi.GroupOf[$SpaceIndex]
    $groupSize = $members.Length
    if ($groupSize -eq 0) { $groupSize = 1 }

    $props = $State.Properties
    $mine = 0
    $bestOpponent = 0
    $opponentCounts = @{}
    foreach ($i in $members) {
        $owner = $props[$i].OwnerId
        if ($owner -eq $PlayerId) { $mine++ }
        elseif ($owner -ge 0) {
            if (-not $opponentCounts.ContainsKey($owner)) { $opponentCounts[$owner] = 0 }
            $opponentCounts[$owner] += 1
            if ($opponentCounts[$owner] -gt $bestOpponent) { $bestOpponent = $opponentCounts[$owner] }
        }
    }

    $value = [double]$bi.Price[$SpaceIndex]
    if ($script:RonGroupDesirability.ContainsKey($group)) { $value *= [double]$script:RonGroupDesirability[$group] }
    # Each deed already held in the group makes the next one worth more.
    $value *= (1.0 + (0.6 * $mine / $groupSize))

    # Completing a monopoly is the single biggest swing in the game.
    if ($mine -eq ($groupSize - 1)) { $value *= 2.5 }

    # Denying an opponent who is one deed short is worth nearly as much.
    if ($bestOpponent -eq ($groupSize - 1)) { $value *= 1.8 }

    if ($props[$SpaceIndex].Mortgaged) { $value *= 0.55 }

    return [int][math]::Round($value)
}

# How much cash this player should keep in hand: an estimate of what one
# unlucky lap could cost them. Gates buying, building and bidding, and is the
# main thing separating a bot that survives from one that goes broke on turn 30.
function Get-RonCashReserveTarget {
    param([GameState]$State, [int]$PlayerId)
    # Memoised per state version: the AI asks for this several times while
    # deciding a single action, and it is a full board scan each time.
    $key = "$($State.GameId):$($State.Version):$PlayerId"
    if ($script:RonReserveCacheKey -eq $key) { return $script:RonReserveCacheValue }

    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    $props = $State.Properties

    $exposure = 0
    foreach ($i in $bi.Deeds) {
        $deed = $props[$i]
        if ($deed.OwnerId -lt 0 -or $deed.OwnerId -eq $PlayerId) { continue }
        if ($deed.Mortgaged) { continue }
        # 7 is the modal two-dice total, so it stands in for "a typical roll".
        $rent = Get-RonRent -State $State -SpaceIndex $i -DiceTotal 7
        if ($rent -gt $exposure) { $exposure = $rent }
    }
    # Enough for the worst single rent on the board, plus a small buffer.
    $target = [int]($exposure * 1.4) + 50

    $profile = Get-RonAiProfile $State.Players[$PlayerId].AiProfile
    $result = [int]($target * [double]$profile.ReserveFactor)

    $script:RonReserveCacheKey   = $key
    $script:RonReserveCacheValue = $result
    return $result
}

# How dangerous the board has become. Low early (nothing is built, walking the
# board is profitable), high late (jail is a shelter).
function Get-RonDevelopedRentDensity {
    param([GameState]$State, [int]$PlayerId)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    $props = $State.Properties
    $developed = 0
    foreach ($i in $bi.Deeds) {
        $deed = $props[$i]
        if ($deed.OwnerId -ge 0 -and $deed.OwnerId -ne $PlayerId -and $deed.Houses -gt 0) { $developed++ }
    }
    if ($bi.Deeds.Length -eq 0) { return 0.0 }
    return ([double]$developed / [double]$bi.Deeds.Length)
}

# Fraction of ownable deeds still with the bank - the "is it still worth
# walking the board" signal.
function Get-RonUnownedFraction {
    param([GameState]$State)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    $props = $State.Properties
    $free = 0
    foreach ($i in $bi.Deeds) {
        if ($props[$i].OwnerId -lt 0) { $free++ }
    }
    if ($bi.Deeds.Length -eq 0) { return 0.0 }
    return ([double]$free / [double]$bi.Deeds.Length)
}

# Extra rent per pound spent, used to rank building targets. This naturally
# reproduces the classic result that the third house is the sharpest jump, so
# every group reaches 3 before any reaches 4.
function Get-RonBuildPriority {
    param([GameState]$State, [int]$SpaceIndex)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    if (-not $bi.IsStreet[$SpaceIndex]) { return 0.0 }
    $cost = $bi.HouseCost[$SpaceIndex]
    if ($cost -le 0) { return 0.0 }

    $houses = $State.Properties[$SpaceIndex].Houses
    if ($houses -ge 5) { return 0.0 }
    $table = $bi.Rent[$SpaceIndex]
    $current = $table[$houses]
    if ($houses -eq 0) { $current = $current * 2 }   # a monopoly site already pays double
    $gain = $table[$houses + 1] - $current
    if ($gain -le 0) { return 0.0 }

    $desire = 1.0
    $group = $bi.Group[$SpaceIndex]
    if ($script:RonGroupDesirability.ContainsKey($group)) { $desire = [double]$script:RonGroupDesirability[$group] }
    return (([double]$gain / [double]$cost) * $desire)
}
