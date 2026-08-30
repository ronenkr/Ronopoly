#
# Ronopoly - auctions.
#
# Turn-order raise-or-pass; passing is permanent. Two edge cases that naive
# implementations get wrong, both handled explicitly here:
#
#   * EVERYONE passes without bidding -> the deed is simply not sold and stays
#     with the bank. (An "end when one bidder remains" loop hangs forever here.)
#   * The last remaining bidder has not actually bid yet -> they still get the
#     chance to bid the minimum or pass, rather than winning for nothing.
#

function Start-RonAuction {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$SpaceIndex,
        [System.Collections.ArrayList]$Events = $null,
        [int]$FirstBidderId = -1,
        [switch]$IsEstate
    )
    $bidders = New-Object System.Collections.ArrayList
    foreach ($p in $State.ActivePlayers()) { [void]$bidders.Add($p.Id) }

    if ($bidders.Count -eq 0) {
        # No solvent players at all: nothing to auction.
        Complete-RonAuction -State $State -Events $Events -Unsold
        return
    }

    $a = [AuctionState]::new()
    $a.SpaceIndex      = $SpaceIndex
    $a.CurrentBid      = 0
    $a.HighBidderId    = -1
    $a.ActiveBidders   = [int[]]$bidders.ToArray()
    $a.MinIncrement    = $State.RuleInt('MinBidIncrement', 10)
    $a.IsEstateAuction = [bool]$IsEstate

    $a.TurnIdx = 0
    if ($FirstBidderId -ge 0) {
        for ($i = 0; $i -lt $a.ActiveBidders.Length; $i++) {
            if ($a.ActiveBidders[$i] -eq $FirstBidderId) { $a.TurnIdx = $i; break }
        }
    }

    $State.Turn.Auction = $a
    $State.Turn.Phase   = 'AwaitAuction'
    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'AuctionStarted' @{ S = $SpaceIndex; Bidders = $a.ActiveBidders }))
    }
}

function Get-RonMinimumBid {
    param([Parameter(Mandatory)][GameState]$State)
    $a = $State.Turn.Auction
    if ($null -eq $a) { return 0 }
    if ($a.HighBidderId -lt 0) { return $a.MinIncrement }
    return $a.CurrentBid + $a.MinIncrement
}

function Test-RonCanBid {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [Parameter(Mandatory)][int]$Amount,
        [ref]$Reason = ([ref]$script:RonReasonSink)
    )
    $a = $State.Turn.Auction
    if ($null -eq $a)                            { return (Set-RonReason $Reason 'Error.WrongPhase' $State.Turn.Phase) }
    if ($a.CurrentBidderId() -ne $PlayerId)      { return (Set-RonReason $Reason 'Error.NotYourTurn') }
    if ($a.ActiveBidders -notcontains $PlayerId) { return (Set-RonReason $Reason 'Error.NotInAuction') }
    if ($Amount -lt (Get-RonMinimumBid -State $State)) { return (Set-RonReason $Reason 'Error.BidTooLow' $a.CurrentBid) }

    # By default a bid must be covered by cash in hand. AllowBidToRaiseFunds
    # relaxes this to everything the player could liquidate.
    $ceiling = $State.GetPlayer($PlayerId).Cash
    if ($State.RuleOn('AllowBidToRaiseFunds')) {
        $ceiling = Get-RonLiquidatableCash -State $State -PlayerId $PlayerId
    }
    if ($Amount -gt $ceiling) { return (Set-RonReason $Reason 'Error.BidTooHigh') }
    return $true
}

function Invoke-RonAuctionBid {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [Parameter(Mandatory)][int]$Amount,
        [System.Collections.ArrayList]$Events = $null
    )
    $why = ''
    if (-not (Test-RonCanBid -State $State -PlayerId $PlayerId -Amount $Amount -Reason ([ref]$why))) {
        throw "Invoke-RonAuctionBid: $why"
    }
    $a = $State.Turn.Auction
    $a.CurrentBid   = $Amount
    $a.HighBidderId = $PlayerId
    $a.TurnIdx      = ($a.TurnIdx + 1) % $a.ActiveBidders.Length
    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'AuctionBid' @{ P = $PlayerId; A = $Amount; S = $a.SpaceIndex }))
    }
    Step-RonAuction -State $State -Events $Events
}

function Invoke-RonAuctionPass {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [System.Collections.ArrayList]$Events = $null
    )
    $a = $State.Turn.Auction
    if ($null -eq $a) { throw 'Invoke-RonAuctionPass: no auction in progress' }
    if ($a.CurrentBidderId() -ne $PlayerId) { throw "Invoke-RonAuctionPass: it is not $($State.GetPlayer($PlayerId).Name)'s turn to bid" }

    $kept = New-Object System.Collections.ArrayList
    foreach ($id in $a.ActiveBidders) { if ($id -ne $PlayerId) { [void]$kept.Add($id) } }
    $removedAt = $a.TurnIdx
    $a.ActiveBidders = [int[]]$kept.ToArray()

    # Removing the player at TurnIdx shifts everyone after them down one, so
    # TurnIdx already points at the next bidder - just wrap it.
    if ($a.ActiveBidders.Length -gt 0) { $a.TurnIdx = $removedAt % $a.ActiveBidders.Length } else { $a.TurnIdx = 0 }

    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'AuctionPassed' @{ P = $PlayerId; S = $a.SpaceIndex }))
    }
    Step-RonAuction -State $State -Events $Events
}

# Called after every bid and pass. Decides whether the auction is over.
function Step-RonAuction {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [System.Collections.ArrayList]$Events = $null
    )
    $a = $State.Turn.Auction
    if ($null -eq $a) { return }

    # Nobody left at all: either sold to the last bidder standing, or unsold
    # because every player passed without bidding.
    if ($a.ActiveBidders.Length -eq 0) {
        if ($a.HighBidderId -ge 0) { Complete-RonAuction -State $State -Events $Events }
        else                       { Complete-RonAuction -State $State -Events $Events -Unsold }
        return
    }

    # Exactly one bidder left AND they already hold the high bid: everyone else
    # has passed, so it is theirs. If they have NOT bid yet they still get a
    # turn to bid the minimum or pass.
    if ($a.ActiveBidders.Length -eq 1 -and $a.HighBidderId -eq $a.ActiveBidders[0]) {
        Complete-RonAuction -State $State -Events $Events
        return
    }
}

function Complete-RonAuction {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [System.Collections.ArrayList]$Events = $null,
        [switch]$Unsold
    )
    $a = $State.Turn.Auction
    if ($null -eq $a) { return }
    $spaceIndex = $a.SpaceIndex
    $winner     = $a.HighBidderId
    $price      = $a.CurrentBid
    $State.Turn.Auction = $null

    if ($Unsold -or $winner -lt 0) {
        if ($null -ne $Events) {
            [void]$Events.Add((New-RonEvent 'AuctionUnsold' @{ S = $spaceIndex }))
        }
        $State.Turn.Phase = 'Resolving'
        return
    }

    # Hand over the deed first, then charge for it. Under the default rules a
    # bid is capped at cash in hand so this always settles outright; with
    # AllowBidToRaiseFunds on, the winner may have to liquidate, which opens a
    # debt - and they must already own the lot for that to be survivable.
    $State.Properties[$spaceIndex].OwnerId = $winner
    if ($null -ne $Events) {
        [void]$Events.Add((New-RonEvent 'AuctionWon' @{ P = $winner; S = $spaceIndex; A = $price }))
    }
    if (Request-RonPayment -State $State -DebtorId $winner -CreditorId -1 -Amount $price -Reason 'auction' -Events $Events) {
        $State.Turn.Phase = 'Resolving'
    }
}
