#
# Ronopoly - user-visible strings.
#
# ASCII only (see Cards.uk.psd1 for why). {C} expands to the currency symbol,
# {0}..{n} are -f format placeholders.
#
@{
    App = @{
        Title      = 'Ronopoly'
        Tagline    = 'London edition'
    }

    Phase = @{
        AwaitRoll          = 'Roll the dice'
        AwaitJailChoice    = 'You are in jail'
        AwaitBuyDecision   = 'Buy or auction?'
        AwaitAuction       = 'Auction in progress'
        AwaitDebt          = 'Settle your debt'
        AwaitTradeResponse = 'Trade offered'
        AwaitEndTurn       = 'End your turn'
        GameOver           = 'Game over'
    }

    Action = @{
        Roll         = 'Roll dice'
        Buy          = 'Buy for {C}{0}'
        Decline      = 'Auction it'
        EndTurn      = 'End turn'
        Bid          = 'Bid {C}{0}'
        Pass         = 'Pass'
        PayFine      = 'Pay {C}{0} fine'
        UseJailCard  = 'Use jail card'
        RollForDoubles = 'Roll for doubles'
        Build        = 'Build'
        SellBuilding = 'Sell building'
        Mortgage     = 'Mortgage'
        Unmortgage   = 'Unmortgage for {C}{0}'
        Trade        = 'Propose trade'
        Accept       = 'Accept'
        Reject       = 'Reject'
        Counter      = 'Counter-offer'
        Bankrupt     = 'Declare bankruptcy'
    }

    Event = @{
        Rolled            = '{0} rolled {1} and {2}'
        RolledDoubles     = '{0} rolled double {1}'
        Moved             = '{0} moved to {1}'
        PassedGo          = '{0} passed Go and collected {C}{1}'
        Bought            = '{0} bought {1} for {C}{2}'
        PaidRent          = '{0} paid {C}{2} rent to {1}'
        PaidTax           = '{0} paid {C}{1} tax'
        DrewCard          = '{0} drew {1}: {2}'
        WentToJail        = '{0} was sent to jail'
        LeftJail          = '{0} left jail'
        JailFinePaid      = '{0} paid the {C}{1} fine'
        ThreeDoubles      = '{0} rolled three doubles and was sent to jail'
        AuctionStarted    = '{1} goes to auction'
        AuctionBid        = '{0} bid {C}{1}'
        AuctionPassed     = '{0} passed'
        AuctionWon        = '{0} won {1} for {C}{2}'
        AuctionUnsold     = '{0} went unsold'
        BuiltHouse        = '{0} built a house on {1}'
        BuiltHotel        = '{0} built a hotel on {1}'
        SoldBuilding      = '{0} sold a building on {1} for {C}{2}'
        Mortgaged         = '{0} mortgaged {1} for {C}{2}'
        Unmortgaged       = '{0} lifted the mortgage on {1} for {C}{2}'
        MortgageInterest  = '{0} paid {C}{1} mortgage interest'
        TradeOffered      = '{0} offered {1} a trade'
        TradeCountered    = '{0} countered {1}'
        TradeAccepted     = '{0} and {1} agreed a trade'
        TradeRejected     = '{1} rejected the trade'
        Bankrupt          = '{0} went bankrupt'
        BankruptTo        = '{0} went bankrupt against {1}'
        GameWon           = '{0} wins!'
        TurnLimitReached  = 'Turn limit reached - richest player wins'
    }

    Error = @{
        NotYourTurn       = 'It is not your turn'
        WrongPhase        = 'That is not allowed right now ({0})'
        NotEnoughCash     = 'Not enough cash'
        NotOwner          = 'You do not own that'
        NotAMonopoly      = 'You need every site in the colour group'
        GroupMortgaged    = 'A site in that group is mortgaged'
        UnevenBuild       = 'Houses must be built evenly across the group'
        UnevenSell        = 'Houses must be sold evenly across the group'
        NoHousesLeft      = 'The bank has no houses left'
        NoHotelsLeft      = 'The bank has no hotels left'
        CannotBreakHotel  = 'The bank needs 4 houses to break that hotel'
        AlreadyMortgaged  = 'That property is already mortgaged'
        HasBuildings      = 'Sell the buildings on that colour group first'
        BidTooLow         = 'Bid must exceed {C}{0}'
        BidTooHigh        = 'You cannot bid more cash than you hold'
        NotInAuction      = 'You have already passed'
        NothingToSettle   = 'You have no debt to settle'
        TradeInvalid      = 'That trade is not legal'
        SelfTrade         = 'You cannot trade with yourself'
        TradeChainTooLong = 'This offer has been round enough times - take it or leave it'
    }

    Ui = @{
        Cash          = 'Cash'
        NetWorth      = 'Net worth'
        Properties    = 'Properties'
        Houses        = 'Houses'
        Hotels        = 'Hotels'
        Bank          = 'Bank'
        FreeParking   = 'Free Parking pot'
        InJail        = 'In jail'
        Bankrupt      = 'Bankrupt'
        JailCards     = 'Jail cards'
        Chance        = 'Chance'
        Chest         = 'Community Chest'
        TitleDeed     = 'Title Deed'
        RentSite      = 'Rent'
        RentWithHouses = 'With {0} house(s)'
        RentWithHotel = 'With hotel'
        HouseCost     = 'Houses cost {C}{0} each'
        HotelCost     = 'Hotels, {C}{0} plus 4 houses'
        MortgageValue = 'Mortgage value {C}{0}'
        Waiting       = 'Waiting for {0}...'
        Reconnecting  = 'Reconnecting...'
        AiTakeover    = '{0} disconnected - the AI has taken over'
    }
}
