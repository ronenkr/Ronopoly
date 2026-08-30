#
# Ronopoly - UK / London board definition.
#
# Loaded with Import-PowerShellDataFile: literals only, no expressions, and
# nothing here executes - which is why it is safe under a Restricted policy.
#
# Rent arrays are indexed by house count: [0]=site only, [1..4]=houses, [5]=hotel.
# A site in a complete, unmortgaged colour group pays DOUBLE Rent[0]; that
# doubling lives in the engine, not in this table.
#
# All money is integer pounds. Mortgage is always Price/2 and every price on
# this board is even, so the halving is exact.
#
@{
    Name       = 'London'
    Currency   = 'GBP'
    SpaceCount = 40

    GoIndex          = 0
    JailIndex        = 10
    FreeParkingIndex = 20
    GoToJailIndex    = 30

    GoSalary     = 200
    JailFine     = 50
    MaxJailTurns = 3
    StartingCash = 1500
    TotalHouses  = 32
    TotalHotels  = 12
    MortgageRate = 10

    StationBaseRent       = 25
    UtilityOneMultiplier  = 4
    UtilityBothMultiplier = 10

    GroupOrder = @('Brown','LightBlue','Pink','Orange','Red','Yellow','Green','DarkBlue','Station','Utility')

    GroupColours = @{
        Brown     = '#8B5A2B'
        LightBlue = '#AAE0FA'
        Pink      = '#D93A96'
        Orange    = '#F7941D'
        Red       = '#ED1B24'
        Yellow    = '#FEF200'
        Green     = '#1FB25A'
        DarkBlue  = '#0072BB'
        Station   = '#2F3437'
        Utility   = '#5B6770'
    }

    Spaces = @(
        @{ I = 0;  Name = 'Go';                       Short = 'GO';           Type = 'Go' }
        @{ I = 1;  Name = 'Old Kent Road';            Short = 'Old Kent';     Type = 'Street';  Group = 'Brown';     Price = 60;  House = 50;  Rent = @(2, 10, 30, 90, 160, 250) }
        @{ I = 2;  Name = 'Community Chest';          Short = 'Chest';        Type = 'Chest' }
        @{ I = 3;  Name = 'Whitechapel Road';         Short = 'Whitechapel';  Type = 'Street';  Group = 'Brown';     Price = 60;  House = 50;  Rent = @(4, 20, 60, 180, 320, 450) }
        @{ I = 4;  Name = 'Income Tax';               Short = 'Income Tax';   Type = 'Tax';     Amount = 200 }
        @{ I = 5;  Name = 'Kings Cross Station';      Short = 'Kings Cross';  Type = 'Station'; Group = 'Station';   Price = 200 }
        @{ I = 6;  Name = 'The Angel Islington';      Short = 'The Angel';    Type = 'Street';  Group = 'LightBlue'; Price = 100; House = 50;  Rent = @(6, 30, 90, 270, 400, 550) }
        @{ I = 7;  Name = 'Chance';                   Short = 'Chance';       Type = 'Chance' }
        @{ I = 8;  Name = 'Euston Road';              Short = 'Euston Rd';    Type = 'Street';  Group = 'LightBlue'; Price = 100; House = 50;  Rent = @(6, 30, 90, 270, 400, 550) }
        @{ I = 9;  Name = 'Pentonville Road';         Short = 'Pentonville';  Type = 'Street';  Group = 'LightBlue'; Price = 120; House = 50;  Rent = @(8, 40, 100, 300, 450, 600) }
        @{ I = 10; Name = 'Jail / Just Visiting';     Short = 'Jail';         Type = 'Jail' }
        @{ I = 11; Name = 'Pall Mall';                Short = 'Pall Mall';    Type = 'Street';  Group = 'Pink';      Price = 140; House = 100; Rent = @(10, 50, 150, 450, 625, 750) }
        @{ I = 12; Name = 'Electric Company';         Short = 'Electric Co';  Type = 'Utility'; Group = 'Utility';   Price = 150 }
        @{ I = 13; Name = 'Whitehall';                Short = 'Whitehall';    Type = 'Street';  Group = 'Pink';      Price = 140; House = 100; Rent = @(10, 50, 150, 450, 625, 750) }
        @{ I = 14; Name = 'Northumberland Avenue';    Short = 'Northumb Ave'; Type = 'Street';  Group = 'Pink';      Price = 160; House = 100; Rent = @(12, 60, 180, 500, 700, 900) }
        @{ I = 15; Name = 'Marylebone Station';       Short = 'Marylebone';   Type = 'Station'; Group = 'Station';   Price = 200 }
        @{ I = 16; Name = 'Bow Street';               Short = 'Bow St';       Type = 'Street';  Group = 'Orange';    Price = 180; House = 100; Rent = @(14, 70, 200, 550, 750, 950) }
        @{ I = 17; Name = 'Community Chest';          Short = 'Chest';        Type = 'Chest' }
        @{ I = 18; Name = 'Marlborough Street';       Short = 'Marlborough';  Type = 'Street';  Group = 'Orange';    Price = 180; House = 100; Rent = @(14, 70, 200, 550, 750, 950) }
        @{ I = 19; Name = 'Vine Street';              Short = 'Vine St';      Type = 'Street';  Group = 'Orange';    Price = 200; House = 100; Rent = @(16, 80, 220, 600, 800, 1000) }
        @{ I = 20; Name = 'Free Parking';             Short = 'Free Parking'; Type = 'FreeParking' }
        @{ I = 21; Name = 'Strand';                   Short = 'Strand';       Type = 'Street';  Group = 'Red';       Price = 220; House = 150; Rent = @(18, 90, 250, 700, 875, 1050) }
        @{ I = 22; Name = 'Chance';                   Short = 'Chance';       Type = 'Chance' }
        @{ I = 23; Name = 'Fleet Street';             Short = 'Fleet St';     Type = 'Street';  Group = 'Red';       Price = 220; House = 150; Rent = @(18, 90, 250, 700, 875, 1050) }
        @{ I = 24; Name = 'Trafalgar Square';         Short = 'Trafalgar';    Type = 'Street';  Group = 'Red';       Price = 240; House = 150; Rent = @(20, 100, 300, 750, 925, 1100) }
        @{ I = 25; Name = 'Fenchurch St Station';     Short = 'Fenchurch';    Type = 'Station'; Group = 'Station';   Price = 200 }
        @{ I = 26; Name = 'Leicester Square';         Short = 'Leicester';    Type = 'Street';  Group = 'Yellow';    Price = 260; House = 150; Rent = @(22, 110, 330, 800, 975, 1150) }
        @{ I = 27; Name = 'Coventry Street';          Short = 'Coventry';     Type = 'Street';  Group = 'Yellow';    Price = 260; House = 150; Rent = @(22, 110, 330, 800, 975, 1150) }
        @{ I = 28; Name = 'Water Works';              Short = 'Water Works';  Type = 'Utility'; Group = 'Utility';   Price = 150 }
        @{ I = 29; Name = 'Piccadilly';               Short = 'Piccadilly';   Type = 'Street';  Group = 'Yellow';    Price = 280; House = 150; Rent = @(24, 120, 360, 850, 1025, 1200) }
        @{ I = 30; Name = 'Go To Jail';               Short = 'Go To Jail';   Type = 'GoToJail' }
        @{ I = 31; Name = 'Regent Street';            Short = 'Regent St';    Type = 'Street';  Group = 'Green';     Price = 300; House = 200; Rent = @(26, 130, 390, 900, 1100, 1275) }
        @{ I = 32; Name = 'Oxford Street';            Short = 'Oxford St';    Type = 'Street';  Group = 'Green';     Price = 300; House = 200; Rent = @(26, 130, 390, 900, 1100, 1275) }
        @{ I = 33; Name = 'Community Chest';          Short = 'Chest';        Type = 'Chest' }
        @{ I = 34; Name = 'Bond Street';              Short = 'Bond St';      Type = 'Street';  Group = 'Green';     Price = 320; House = 200; Rent = @(28, 150, 450, 1000, 1200, 1400) }
        @{ I = 35; Name = 'Liverpool Street Station'; Short = 'Liverpool St'; Type = 'Station'; Group = 'Station';   Price = 200 }
        @{ I = 36; Name = 'Chance';                   Short = 'Chance';       Type = 'Chance' }
        @{ I = 37; Name = 'Park Lane';                Short = 'Park Lane';    Type = 'Street';  Group = 'DarkBlue';  Price = 350; House = 200; Rent = @(35, 175, 500, 1100, 1300, 1500) }
        @{ I = 38; Name = 'Super Tax';                Short = 'Super Tax';    Type = 'Tax';     Amount = 100 }
        @{ I = 39; Name = 'Mayfair';                  Short = 'Mayfair';      Type = 'Street';  Group = 'DarkBlue';  Price = 400; House = 200; Rent = @(50, 200, 600, 1400, 1700, 2000) }
    )
}
