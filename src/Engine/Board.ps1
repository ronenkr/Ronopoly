#
# Ronopoly - static board queries. Pure functions of Board.uk.psd1; none of
# them look at GameState, so the asset generator and the simulator can use them
# without a game in progress.
#
# PERFORMANCE NOTE. Profiling showed the engine spending its time in call
# OVERHEAD, not arithmetic: a PowerShell 5.1 advanced-function call costs ~25
# microseconds, while an array index inside a function body is effectively
# free. Get-RonBoardIndex therefore flattens the board into parallel arrays
# once, and every hot path (rent, build legality, valuation) indexes those
# arrays directly rather than calling an accessor per lookup. The accessors
# below still exist, for readable non-hot code.
#

$script:RonBoardIndex = $null

function Get-RonBoardIndex {
    if ($null -ne $script:RonBoardIndex) { return $script:RonBoardIndex }
    $board = Get-RonBoard
    $n = [int]$board.SpaceCount

    $byIndex   = New-Object 'object[]' $n
    $type      = New-Object 'string[]' $n
    $group     = New-Object 'string[]' $n
    $price     = New-Object 'int[]' $n
    $houseCost = New-Object 'int[]' $n
    $mortgage  = New-Object 'int[]' $n
    $rent      = New-Object 'object[]' $n
    $isDeed    = New-Object 'bool[]' $n
    $isStreet  = New-Object 'bool[]' $n

    $groups   = @{}
    $deeds    = New-Object System.Collections.ArrayList
    $stations = New-Object System.Collections.ArrayList
    $utils    = New-Object System.Collections.ArrayList

    foreach ($s in $board.Spaces) {
        $i = [int]$s.I
        $byIndex[$i] = $s
        $type[$i]    = [string]$s.Type
        $group[$i]   = ''
        if ($s.ContainsKey('Group')) {
            $group[$i] = [string]$s.Group
            if (-not $groups.ContainsKey($s.Group)) { $groups[$s.Group] = New-Object System.Collections.ArrayList }
            [void]$groups[$s.Group].Add($i)
        }
        if ($s.ContainsKey('Price')) {
            $price[$i]    = [int]$s.Price
            $mortgage[$i] = [int]([int]$s.Price / 2)
        }
        if ($s.ContainsKey('House')) { $houseCost[$i] = [int]$s.House }
        if ($s.ContainsKey('Rent'))  { $rent[$i] = [int[]]$s.Rent }

        $isDeed[$i]   = ($s.Type -eq 'Street' -or $s.Type -eq 'Station' -or $s.Type -eq 'Utility')
        $isStreet[$i] = ($s.Type -eq 'Street')
        if ($isDeed[$i])           { [void]$deeds.Add($i) }
        if ($s.Type -eq 'Station') { [void]$stations.Add($i) }
        if ($s.Type -eq 'Utility') { [void]$utils.Add($i) }
    }

    $groupArrays = @{}
    foreach ($g in $groups.Keys) { $groupArrays[$g] = [int[]]$groups[$g].ToArray() }

    # GroupOf[i] is the member list of i's OWN group, so a monopoly check needs
    # neither a group-name lookup nor a second array lookup.
    $groupOf = New-Object 'object[]' $n
    for ($i = 0; $i -lt $n; $i++) {
        if ($group[$i] -and $groupArrays.ContainsKey($group[$i])) { $groupOf[$i] = $groupArrays[$group[$i]] }
        else { $groupOf[$i] = [int[]]@() }
    }

    $script:RonBoardIndex = @{
        Board     = $board
        Size      = $n
        ByIndex   = $byIndex
        Type      = $type
        Group     = $group
        GroupOf   = $groupOf
        Price     = $price
        HouseCost = $houseCost
        Mortgage  = $mortgage
        Rent      = $rent
        IsDeed    = $isDeed
        IsStreet  = $isStreet
        Groups    = $groupArrays
        Deeds     = [int[]]$deeds.ToArray()
        Stations  = [int[]]$stations.ToArray()
        Utilities = [int[]]$utils.ToArray()
        StationBaseRent = [int]$board.StationBaseRent
        UtilityOne      = [int]$board.UtilityOneMultiplier
        UtilityBoth     = [int]$board.UtilityBothMultiplier
        MortgageRate    = [int]$board.MortgageRate
        GoIndex         = [int]$board.GoIndex
        JailIndex       = [int]$board.JailIndex
        GoSalary        = [int]$board.GoSalary
        JailFine        = [int]$board.JailFine
        MaxJailTurns    = [int]$board.MaxJailTurns
    }
    return $script:RonBoardIndex
}

function Reset-RonBoardIndex { $script:RonBoardIndex = $null }

# --- accessors -------------------------------------------------------------
#
# The one-line "$bi = $script:RonBoardIndex; if null then build" preamble costs
# a single null test and keeps every accessor safe to call before any game has
# started.

function Get-RonSpace {
    param([int]$Index)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    if ($Index -lt 0 -or $Index -ge $bi.Size) { throw "Get-RonSpace: index $Index is outside 0..$($bi.Size - 1)" }
    return $bi.ByIndex[$Index]
}

function Get-RonBoardSize {
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    return $bi.Size
}

function Get-RonSpaceName {
    param([int]$Index)
    return (Get-RonSpace $Index).Name
}

function Get-RonGroupIndices {
    param([string]$Group)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    if (-not $bi.Groups.ContainsKey($Group)) { return ([int[]]@()) }
    return $bi.Groups[$Group]
}

# The colour group (or Station / Utility set) containing a space; '' for Go,
# taxes, card spaces and corners.
function Get-RonSpaceGroup {
    param([int]$Index)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    return $bi.Group[$Index]
}

function Get-RonDeedIndices    { $bi = $script:RonBoardIndex; if ($null -eq $bi) { $bi = Get-RonBoardIndex }; return $bi.Deeds }
function Get-RonStationIndices { $bi = $script:RonBoardIndex; if ($null -eq $bi) { $bi = Get-RonBoardIndex }; return $bi.Stations }
function Get-RonUtilityIndices { $bi = $script:RonBoardIndex; if ($null -eq $bi) { $bi = Get-RonBoardIndex }; return $bi.Utilities }

# A "deed" is anything ownable: street, station or utility.
function Test-RonIsDeed {
    param([int]$Index)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    return $bi.IsDeed[$Index]
}

function Test-RonIsStreet {
    param([int]$Index)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    return $bi.IsStreet[$Index]
}

function Get-RonSpacePrice {
    param([int]$Index)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    return $bi.Price[$Index]
}

function Get-RonHouseCost {
    param([int]$Index)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    return $bi.HouseCost[$Index]
}

# Always exactly half the price; every price on this board is even.
function Get-RonMortgageValue {
    param([int]$Index)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    return $bi.Mortgage[$Index]
}

# Mortgage value plus the board's interest rate, unless the house rule waives it.
function Get-RonUnmortgageCost {
    param([int]$Index, [hashtable]$Rules = $null)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    $m = $bi.Mortgage[$Index]
    if ($null -ne $Rules -and $Rules.ContainsKey('MortgageInterestFree') -and $Rules['MortgageInterestFree']) { return $m }
    return $m + [int][math]::Ceiling($m * $bi.MortgageRate / 100.0)
}

# --- movement geometry -----------------------------------------------------

function Get-RonForwardDistance {
    param([int]$From, [int]$To)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    return ((($To - $From) % $bi.Size) + $bi.Size) % $bi.Size
}

# Cards say "advance to the NEAREST station/utility", which in the printed
# rules means the next one going FORWARD, wrapping past Go.
function Get-RonNextSpaceOfType {
    param([int]$From, [ValidateSet('Station','Utility')][string]$Type)
    $bi = $script:RonBoardIndex
    if ($null -eq $bi) { $bi = Get-RonBoardIndex }
    if ($Type -eq 'Station') { $candidates = $bi.Stations } else { $candidates = $bi.Utilities }
    $best = -1
    $bestDist = [int]::MaxValue
    foreach ($c in $candidates) {
        $d = ((($c - $From) % $bi.Size) + $bi.Size) % $bi.Size
        if ($d -eq 0) { $d = $bi.Size }   # already standing on one: go all the way round
        if ($d -lt $bestDist) { $bestDist = $d; $best = $c }
    }
    return $best
}

# --- board geometry (shared by the UI grid and the asset generator) --------
#
# 11x11 grid, corners at the four extremes:
#   0-10  bottom, right to left      11-19 left,  bottom to top
#   20-30 top,    left to right      31-39 right, top to bottom
#
# Rotation is clockwise degrees for a tile authored upright (colour bar at the
# top), so every bar ends up facing the centre of the board.
function Get-RonBoardCell {
    param([int]$Index)
    if ($Index -le 10) { return @{ Row = 10;          Col = 10 - $Index; Side = 'Bottom'; Rotation = 0 } }
    if ($Index -le 19) { return @{ Row = 20 - $Index; Col = 0;           Side = 'Left';   Rotation = 90 } }
    if ($Index -le 30) { return @{ Row = 0;           Col = $Index - 20; Side = 'Top';    Rotation = 180 } }
    return                      @{ Row = $Index - 30; Col = 10;          Side = 'Right';  Rotation = 270 }
}

function Test-RonIsCorner {
    param([int]$Index)
    return ($Index -eq 0 -or $Index -eq 10 -or $Index -eq 20 -or $Index -eq 30)
}
