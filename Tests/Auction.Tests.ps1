. (Join-Path (Split-Path -Parent $PSCommandPath) '_Common.ps1')

Describe 'Auction' {

    It 'sells to the last bidder standing' {
        $g = New-TestGame -Players 3
        Start-RonAuction -State $g -SpaceIndex 39 -FirstBidderId 0
        Assert-Equal 'AwaitAuction' $g.Turn.Phase
        Invoke-RonAuctionBid  -State $g -PlayerId 0 -Amount 100
        Invoke-RonAuctionBid  -State $g -PlayerId 1 -Amount 150
        Invoke-RonAuctionPass -State $g -PlayerId 2
        Invoke-RonAuctionPass -State $g -PlayerId 0
        Assert-Equal 1 $g.Properties[39].OwnerId 'Bob had the high bid'
        Assert-Equal (1500 - 150) $g.GetPlayer(1).Cash
        Assert-RonInvariant -State $g
    }

    It 'leaves the deed with the bank when everyone passes' {
        # The case a naive "loop until one bidder remains" hangs on forever.
        $g = New-TestGame -Players 3
        Start-RonAuction -State $g -SpaceIndex 39 -FirstBidderId 0
        Invoke-RonAuctionPass -State $g -PlayerId 0
        Invoke-RonAuctionPass -State $g -PlayerId 1
        Invoke-RonAuctionPass -State $g -PlayerId 2
        Assert-Equal -1 $g.Properties[39].OwnerId
        Assert-Null $g.Turn.Auction
        Assert-RonInvariant -State $g
    }

    It 'still offers the last bidder a turn when they have not yet bid' {
        $g = New-TestGame -Players 3
        Start-RonAuction -State $g -SpaceIndex 39 -FirstBidderId 0
        Invoke-RonAuctionPass -State $g -PlayerId 0
        Invoke-RonAuctionPass -State $g -PlayerId 1
        Assert-Equal 'AwaitAuction' $g.Turn.Phase 'Cat has not bid, so it is not over'
        Assert-Equal 2 $g.Turn.Auction.CurrentBidderId()
        Invoke-RonAuctionBid -State $g -PlayerId 2 -Amount 10
        Assert-Equal 2 $g.Properties[39].OwnerId
        Assert-Equal (1500 - 10) $g.GetPlayer(2).Cash 'a deed worth 400 for 10'
    }

    It 'rejects a bid larger than the bidder can pay' {
        $g = New-TestGame -Players 2
        Set-TestCash -State $g -PlayerId 0 -Cash 90
        Start-RonAuction -State $g -SpaceIndex 39 -FirstBidderId 0
        $why = ''
        Assert-False (Test-RonCanBid -State $g -PlayerId 0 -Amount 100 -Reason ([ref]$why))
        Assert-Equal (Get-RonString 'Error.BidTooHigh') $why
        Assert-True (Test-RonCanBid -State $g -PlayerId 0 -Amount 90)
    }

    It 'rejects a bid that does not beat the standing one' {
        $g = New-TestGame -Players 2
        Start-RonAuction -State $g -SpaceIndex 39 -FirstBidderId 0
        Invoke-RonAuctionBid -State $g -PlayerId 0 -Amount 100
        $why = ''
        Assert-False (Test-RonCanBid -State $g -PlayerId 1 -Amount 100 -Reason ([ref]$why))
        Assert-Equal (Get-RonString 'Error.BidTooLow' 100) $why
        Assert-True (Test-RonCanBid -State $g -PlayerId 1 -Amount 110) 'the minimum increment is 10'
    }

    It 'refuses a bid out of turn' {
        $g = New-TestGame -Players 3
        Start-RonAuction -State $g -SpaceIndex 39 -FirstBidderId 0
        $why = ''
        Assert-False (Test-RonCanBid -State $g -PlayerId 2 -Amount 100 -Reason ([ref]$why))
        Assert-Equal (Get-RonString 'Error.NotYourTurn') $why
    }

    Context 'through the action seam' {
        It 'starts an auction when the lander declines' {
            $g = New-TestGame -Players 3
            $g.Turn.Phase = 'AwaitBuyDecision'
            $g.Turn.PendingSpaceIndex = 39
            $r = Invoke-RonAction -State $g -Action @{ Kind = 'DeclineProperty'; PlayerId = 0; SpaceIndex = 39 }
            Assert-True $r.Ok
            Assert-Equal 'AwaitAuction' $g.Turn.Phase
            Assert-Equal 1 $g.Turn.Auction.CurrentBidderId() 'bidding opens on the decliner left'
        }

        It 'leaves it with the bank instead, under DisableAuctions' {
            $g = New-TestGame -Players 3 -RuleOverrides @{ DisableAuctions = $true }
            $g.Turn.Phase = 'AwaitBuyDecision'
            $g.Turn.PendingSpaceIndex = 39
            $r = Invoke-RonAction -State $g -Action @{ Kind = 'DeclineProperty'; PlayerId = 0; SpaceIndex = 39 }
            Assert-True $r.Ok
            Assert-NotEqual 'AwaitAuction' $g.Turn.Phase
            Assert-Equal -1 $g.Properties[39].OwnerId
        }
    }
}

exit (Complete-RonTests)
