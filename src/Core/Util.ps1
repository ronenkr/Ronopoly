#
# Ronopoly - shared helpers: JSON discipline, static-data loading, formatting.
#
# Every JSON call in the project goes through ConvertTo-RonJson /
# ConvertFrom-RonJson. Nothing calls ConvertTo-Json directly, because its
# default -Depth of 2 silently replaces anything deeper with the literal
# string "System.Object[]" - a corruption that produces no error and would
# only surface as a broken save or a desynced LAN client.
#

$script:RonDataCache = @{}

function Get-RonRoot {
    if ($null -ne $script:RonRoot) { return $script:RonRoot }
    throw 'Get-RonRoot: Ronopoly has not been bootstrapped. Dot-source src\Bootstrap.ps1 first.'
}

function Get-RonPath {
    param([Parameter(Mandatory)][string]$Relative)
    return (Join-Path (Get-RonRoot) $Relative)
}

# --- JSON ------------------------------------------------------------------

function ConvertTo-RonJson {
    param(
        [Parameter(Mandatory, ValueFromPipeline)][object]$InputObject,
        [switch]$Pretty
    )
    process {
        if ($Pretty) { return ($InputObject | ConvertTo-Json -Depth 24) }
        return ($InputObject | ConvertTo-Json -Depth 24 -Compress)
    }
}

function ConvertFrom-RonJson {
    param([Parameter(Mandatory, ValueFromPipeline)][string]$Json)
    process { return ($Json | ConvertFrom-Json) }
}

# --- Static data -----------------------------------------------------------
#
# Cached on first use. Import-PowerShellDataFile parses literals only and
# executes nothing, which is what makes these safe to load under a Restricted
# execution policy.

function Import-RonData {
    param(
        [Parameter(Mandatory)][string]$Name,       # cache key
        [Parameter(Mandatory)][string]$FileName    # under src\Data
    )
    if ($script:RonDataCache.ContainsKey($Name)) { return $script:RonDataCache[$Name] }
    $path = Get-RonPath (Join-Path 'src\Data' $FileName)
    if (-not (Test-Path -LiteralPath $path)) { throw "Import-RonData: missing data file '$path'" }
    $data = Import-PowerShellDataFile -LiteralPath $path
    $script:RonDataCache[$Name] = $data
    return $data
}

function Get-RonBoard   { return (Import-RonData -Name 'Board'   -FileName 'Board.uk.psd1') }
function Get-RonCards   { return (Import-RonData -Name 'Cards'   -FileName 'Cards.uk.psd1') }
function Get-RonTokens  { return (Import-RonData -Name 'Tokens'  -FileName 'Tokens.psd1') }
function Get-RonStrings { return (Import-RonData -Name 'Strings' -FileName 'Strings.en-GB.psd1') }

# Returns a fresh mutable copy every call - the caller stores it on GameState
# and the settings screen mutates it, so handing out the cached instance would
# leak one game's house rules into the next.
function Get-RonDefaultRules {
    $src = Import-RonData -Name 'Rules' -FileName 'Rules.default.psd1'
    $copy = @{}
    foreach ($k in $src.Keys) { $copy[$k] = $src[$k] }
    return $copy
}

function Clear-RonDataCache { $script:RonDataCache = @{} }

# --- Formatting ------------------------------------------------------------

function Get-RonCurrencySymbol {
    $board = Get-RonBoard
    if ($board.Currency -eq 'GBP') { return ([char]0x00A3) }
    if ($board.Currency -eq 'USD') { return '$' }
    if ($board.Currency -eq 'EUR') { return ([char]0x20AC) }
    return ''
}

# Data files are ASCII (see Cards.uk.psd1); {C} marks where the symbol goes.
function Expand-RonCurrency {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    return $Text.Replace('{C}', (Get-RonCurrencySymbol))
}

function Format-RonMoney {
    param(
        [Parameter(Mandatory)][int]$Amount,
        [switch]$NoSymbol
    )
    $n = '{0:N0}' -f [math]::Abs($Amount)
    $sign = ''
    if ($Amount -lt 0) { $sign = '-' }
    if ($NoSymbol) { return ($sign + $n) }
    return ($sign + (Get-RonCurrencySymbol) + $n)
}

# Get-RonString Event.Bought 'Ann' 'Mayfair' 400
function Get-RonString {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(ValueFromRemainingArguments)][object[]]$FormatArgs
    )
    $node = Get-RonStrings
    foreach ($part in $Key.Split('.')) {
        if ($null -eq $node -or -not $node.ContainsKey($part)) { return "!$Key!" }
        $node = $node[$part]
    }
    $text = Expand-RonCurrency ([string]$node)
    if ($null -eq $FormatArgs -or $FormatArgs.Count -eq 0) { return $text }
    return ($text -f $FormatArgs)
}

# --- Misc ------------------------------------------------------------------

function New-RonId {
    return ([guid]::NewGuid().ToString('N').Substring(0, 12))
}

# Official rounding for lifting a mortgage: the printed rules charge 10%
# interest, and every board price is even so the half never appears; Ceiling
# keeps odd house rules (e.g. a 15% variant) from ever favouring the player.
function Get-RonInterest {
    param(
        [Parameter(Mandatory)][int]$Principal,
        [Parameter(Mandatory)][int]$Percent
    )
    return [int][math]::Ceiling($Principal * $Percent / 100.0)
}

# Discard target for validators called without a -Reason. A [ref] parameter
# cannot take $null as a default, and binding a [ref] to an [object] parameter
# silently UNWRAPS it to the value - so every reason parameter in the project is
# [ref]-typed with this sink as its default, and [ref] to [ref] pass-through
# then works all the way down.
$script:RonReasonSink = ''

# Validator convention: set an optional [ref] out-parameter to a localised
# reason and return $false, so every rule check reads as
#     if (bad) { return (Set-RonReason $Reason 'Error.NotEnoughCash') }
# and the caller may pass no [ref] at all when it only wants the boolean.
function Set-RonReason {
    param(
        [Parameter(Position = 0)][ref]$Reason = ([ref]$script:RonReasonSink),
        [Parameter(Position = 1)][string]$Key,
        [Parameter(ValueFromRemainingArguments)][object[]]$FormatArgs
    )
    if ($null -eq $FormatArgs -or $FormatArgs.Count -eq 0) { $Reason.Value = Get-RonString $Key }
    else { $Reason.Value = Get-RonString $Key @FormatArgs }
    return $false
}

# Folds any number of values into a seed that always fits in an Int32.
#
# Deriving a seed by hand - "seed * 31 + playerId" - overflows the moment the
# game seed is large, and New-RonGame picks one anywhere up to 2^31. PowerShell
# silently widens the product to a double rather than wrapping, and the failure
# only surfaces later as "Cannot convert value ... to type System.Int32", from
# whatever constructor happened to receive it. Every derived seed in the project
# goes through here instead.
function Get-RonSeedMix {
    param([Parameter(ValueFromRemainingArguments)][long[]]$Parts)
    $mix = [long]2166136261                      # FNV-ish starting offset
    foreach ($p in $Parts) {
        $mix = (($mix * 31) + $p) -band 0x7FFFFFFF
    }
    if ($mix -eq 0) { $mix = 12345 }
    return [int]$mix
}
