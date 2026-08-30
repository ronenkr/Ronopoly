#
# Ronopoly - the event vocabulary.
#
# Every mutation the engine performs also emits an event. Events drive three
# consumers: the on-screen game log, the animation queue, and the LAN clients.
#
# DESIGN NOTE (deviation from the original plan, deliberate): events are NOT
# replayed by clients to mutate a local replica. The host sends the full
# authoritative state alongside each event batch. A snapshot is ~20 KB and
# ~2 ms to build, which is nothing on a LAN, and it removes the single largest
# correctness risk in the whole networking layer - an Apply-Event that has to
# mirror the rules engine exactly and silently desyncs when it does not.
# Events stay the vocabulary for animation and logging only.
#
# Field conventions, kept short because they cross the wire:
#   T   event type        P   player id        P2  other player id
#   S   space index       A   amount           N   count
#

function New-RonEvent {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Type,
        [Parameter(Position = 1)][hashtable]$Data = @{}
    )
    $h = @{ T = $Type }
    foreach ($k in $Data.Keys) { $h[$k] = $Data[$k] }
    return [pscustomobject]$h
}

# Rendered into the on-screen log. Unknown types degrade to the raw type name
# rather than throwing - a missing log line must never break a game.
function Format-RonEvent {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][object]$Event
    )
    $e = $Event
    $who = ''
    if ($null -ne $e.PSObject.Properties['P'] -and $e.P -ge 0) { $who = $State.GetPlayer($e.P).Name }

    switch ($e.T) {
        'Rolled' {
            if ($e.D1 -eq $e.D2) { return (Get-RonString 'Event.RolledDoubles' $who $e.D1) }
            return (Get-RonString 'Event.Rolled' $who $e.D1 $e.D2)
        }
        'Moved'          { return (Get-RonString 'Event.Moved' $who (Get-RonSpaceName $e.S)) }
        'PassedGo'       { return (Get-RonString 'Event.PassedGo' $who $e.A) }
        'Bought'         { return (Get-RonString 'Event.Bought' $who (Get-RonSpaceName $e.S) $e.A) }
        'RentPaid'       { return (Get-RonString 'Event.PaidRent' $who $State.GetPlayer($e.P2).Name $e.A) }
        'TaxPaid'        { return (Get-RonString 'Event.PaidTax' $who $e.A) }
        'CardDrawn'      { return (Get-RonString 'Event.DrewCard' $who $e.Deck (Expand-RonCurrency $e.Text)) }
        'JailEntered'    { return (Get-RonString 'Event.WentToJail' $who) }
        'ThreeDoubles'   { return (Get-RonString 'Event.ThreeDoubles' $who) }
        'JailLeft'       { return (Get-RonString 'Event.LeftJail' $who) }
        'JailFinePaid'   { return (Get-RonString 'Event.JailFinePaid' $who $e.A) }
        'AuctionStarted' { return (Get-RonString 'Event.AuctionStarted' '' (Get-RonSpaceName $e.S)) }
        'AuctionBid'     { return (Get-RonString 'Event.AuctionBid' $who $e.A) }
        'AuctionPassed'  { return (Get-RonString 'Event.AuctionPassed' $who) }
        'AuctionWon'     { return (Get-RonString 'Event.AuctionWon' $who (Get-RonSpaceName $e.S) $e.A) }
        'AuctionUnsold'  { return (Get-RonString 'Event.AuctionUnsold' (Get-RonSpaceName $e.S)) }
        'BuildingBuilt'  {
            if ($e.N -eq 5) { return (Get-RonString 'Event.BuiltHotel' $who (Get-RonSpaceName $e.S)) }
            return (Get-RonString 'Event.BuiltHouse' $who (Get-RonSpaceName $e.S))
        }
        'BuildingSold'   { return (Get-RonString 'Event.SoldBuilding' $who (Get-RonSpaceName $e.S) $e.A) }
        'Mortgaged'      { return (Get-RonString 'Event.Mortgaged' $who (Get-RonSpaceName $e.S) $e.A) }
        'Unmortgaged'    { return (Get-RonString 'Event.Unmortgaged' $who (Get-RonSpaceName $e.S) $e.A) }
        'MortgageInterest' { return (Get-RonString 'Event.MortgageInterest' $who $e.A) }
        'TradeOffered'   { return (Get-RonString 'Event.TradeOffered' $who $State.GetPlayer($e.P2).Name) }
        'TradeCountered' { return (Get-RonString 'Event.TradeCountered' $who $State.GetPlayer($e.P2).Name) }
        'TradeExecuted'  { return (Get-RonString 'Event.TradeAccepted' $who $State.GetPlayer($e.P2).Name) }
        'TradeRejected'  { return (Get-RonString 'Event.TradeRejected' $who $State.GetPlayer($e.P2).Name) }
        'Bankrupt'       {
            if ($e.P2 -ge 0) { return (Get-RonString 'Event.BankruptTo' $who $State.GetPlayer($e.P2).Name) }
            return (Get-RonString 'Event.Bankrupt' $who)
        }
        'GameOver'       {
            if ($e.P -ge 0) { return (Get-RonString 'Event.GameWon' $who) }
            return (Get-RonString 'Event.TurnLimitReached')
        }
        default          { return '' }
    }
    return ''
}

# The subset the animator actually has to wait for; everything else renders
# instantly. Kept here so the UI never hard-codes event type names.
$script:RonAnimatedEvents = @('Rolled','Moved','CardDrawn','JailEntered','BuildingBuilt','BuildingSold','Bankrupt','GameOver')

function Test-RonEventIsAnimated {
    param([Parameter(Mandatory)][object]$Event)
    return ($script:RonAnimatedEvents -contains $Event.T)
}
