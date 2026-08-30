#
# Ronopoly - rule flags.
#
# Defaults are STRICT OFFICIAL RULES: every house rule below is off. The
# settings screen flips these; the engine only ever reads them through
# GameState.RuleOn() / RuleInt(), never hard-codes a variant.
#
@{
    # --- House rules (all default OFF = official play) ---------------------

    # Fines and taxes accumulate on Free Parking and are paid to whoever
    # lands there. The single most common house rule, and the one that most
    # lengthens games by injecting money the official rules never create.
    FreeParkingJackpot = $false

    # Declining to buy leaves the deed with the bank instead of triggering an
    # auction. Also lengthens games considerably.
    DisableAuctions = $false

    # Ignore the 32 house / 12 hotel supply limit. Removes the building
    # shortage as a strategic weapon.
    UnlimitedBuildings = $false

    # Landing exactly on Go pays double salary.
    DoubleSalaryOnExactGo = $false

    # Owners in jail collect no rent.
    NoRentInJail = $false

    # Income Tax and Super Tax feed the Free Parking pot rather than the bank.
    # Only meaningful together with FreeParkingJackpot.
    TaxesToFreeParking = $false

    # Rolling double one pays a bonus from the bank.
    SnakeEyesBonus = $false
    SnakeEyesAmount = 500

    # Lifting a mortgage costs the mortgage value with no 10% interest.
    MortgageInterestFree = $false

    # A bidder may mortgage and sell buildings mid-auction to fund a bid.
    AllowBidToRaiseFunds = $false

    # --- Official-rule switches (defaults match the printed rules) ---------

    # When a player goes bankrupt owing the BANK, their estate is auctioned to
    # the survivors. This is a real printed rule that most clones skip.
    AuctionBankruptEstate = $true

    # Whether a mortgaged sibling breaks the double-rent bonus on an
    # undeveloped site. The printed rules define the monopoly by OWNERSHIP,
    # so this is off.
    MonopolyDoubleRequiresUnmortgagedGroup = $false

    # --- Session limits ----------------------------------------------------

    # Hard cap so a stalemate cannot run forever. At the cap the richest
    # player by net worth wins. 0 disables the cap.
    TurnLimit = 0

    # Auction bidding increment in pounds.
    MinBidIncrement = 10

    # Seconds a disconnected LAN player is held before the AI takes over.
    DisconnectGraceSeconds = 30
}
