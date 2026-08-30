#
# Ronopoly - Chance and Community Chest decks (UK / London edition).
#
# All text is ASCII on purpose. Import-PowerShellDataFile on Windows PowerShell
# 5.1 reads a BOM-less file as ANSI, which would mangle a literal pound sign
# into two characters. {C} is substituted with the board's currency symbol by
# Expand-RonCurrency at display time.
#
# Effect kinds (dispatched by Invoke-RonCardEffect):
#   AdvanceTo               Target         - move forward to a space, collecting Go if passed
#   AdvanceSpaces           Delta          - relative move; may be negative, never collects Go
#   AdvanceToNearestStation                - forward to next Station; rent is DOUBLED if owned
#   AdvanceToNearestUtility                - forward to next Utility; owner is paid 10x a FRESH
#                                            roll regardless of how many utilities they hold
#   GoToJail                               - direct to jail, no Go salary, no doubles credit
#   CollectFromBank         Amount
#   PayBank                 Amount
#   CollectFromEachPlayer   Amount
#   PayEachPlayer           Amount
#   GetOutOfJailFree                       - leaves the deck while held, returns to the bottom
#   StreetRepairs           PerHouse, PerHotel
#
@{
    Chance = @(
        @{ Id = 0;  Kind = 'AdvanceTo';               Target = 0;  Text = 'Advance to Go. Collect {C}200.' }
        @{ Id = 1;  Kind = 'AdvanceTo';               Target = 24; Text = 'Advance to Trafalgar Square. If you pass Go, collect {C}200.' }
        @{ Id = 2;  Kind = 'AdvanceTo';               Target = 11; Text = 'Advance to Pall Mall. If you pass Go, collect {C}200.' }
        @{ Id = 3;  Kind = 'AdvanceToNearestUtility'; Text = 'Advance token to the nearest Utility. If unowned you may buy it from the Bank. If owned, throw the dice and pay the owner ten times the amount thrown.' }
        @{ Id = 4;  Kind = 'AdvanceToNearestStation'; Text = 'Advance token to the nearest Station and pay the owner twice the rental to which they are otherwise entitled. If unowned you may buy it from the Bank.' }
        @{ Id = 5;  Kind = 'AdvanceToNearestStation'; Text = 'Advance token to the nearest Station and pay the owner twice the rental to which they are otherwise entitled. If unowned you may buy it from the Bank.' }
        @{ Id = 6;  Kind = 'CollectFromBank';         Amount = 50;  Text = 'Bank pays you dividend of {C}50.' }
        @{ Id = 7;  Kind = 'GetOutOfJailFree';        Text = 'Get out of Jail free. This card may be kept until needed or sold.' }
        @{ Id = 8;  Kind = 'AdvanceSpaces';           Delta = -3;   Text = 'Go back three spaces.' }
        @{ Id = 9;  Kind = 'GoToJail';                Text = 'Go to Jail. Go directly to Jail. Do not pass Go, do not collect {C}200.' }
        @{ Id = 10; Kind = 'StreetRepairs';           PerHouse = 25; PerHotel = 100; Text = 'Make general repairs on all your property. For each house pay {C}25, for each hotel pay {C}100.' }
        @{ Id = 11; Kind = 'PayBank';                 Amount = 15;  Text = 'Speeding fine {C}15.' }
        @{ Id = 12; Kind = 'AdvanceTo';               Target = 15;  Text = 'Take a trip to Marylebone Station. If you pass Go, collect {C}200.' }
        @{ Id = 13; Kind = 'PayEachPlayer';           Amount = 50;  Text = 'You have been elected Chairman of the Board. Pay each player {C}50.' }
        @{ Id = 14; Kind = 'CollectFromBank';         Amount = 150; Text = 'Your building loan matures. Collect {C}150.' }
        @{ Id = 15; Kind = 'AdvanceTo';               Target = 39;  Text = 'Advance to Mayfair.' }
    )

    Chest = @(
        @{ Id = 0;  Kind = 'AdvanceTo';             Target = 0;   Text = 'Advance to Go. Collect {C}200.' }
        @{ Id = 1;  Kind = 'CollectFromBank';       Amount = 200; Text = 'Bank error in your favour. Collect {C}200.' }
        @{ Id = 2;  Kind = 'PayBank';               Amount = 50;  Text = 'Doctor''s fee. Pay {C}50.' }
        @{ Id = 3;  Kind = 'CollectFromBank';       Amount = 50;  Text = 'From sale of stock you get {C}50.' }
        @{ Id = 4;  Kind = 'GetOutOfJailFree';      Text = 'Get out of Jail free. This card may be kept until needed or sold.' }
        @{ Id = 5;  Kind = 'GoToJail';              Text = 'Go to Jail. Go directly to Jail. Do not pass Go, do not collect {C}200.' }
        @{ Id = 6;  Kind = 'CollectFromBank';       Amount = 100; Text = 'Holiday fund matures. Receive {C}100.' }
        @{ Id = 7;  Kind = 'CollectFromBank';       Amount = 20;  Text = 'Income tax refund. Collect {C}20.' }
        @{ Id = 8;  Kind = 'CollectFromEachPlayer'; Amount = 10;  Text = 'It is your birthday. Collect {C}10 from every player.' }
        @{ Id = 9;  Kind = 'CollectFromBank';       Amount = 100; Text = 'Life insurance matures. Collect {C}100.' }
        @{ Id = 10; Kind = 'PayBank';               Amount = 100; Text = 'Hospital fees. Pay {C}100.' }
        @{ Id = 11; Kind = 'PayBank';               Amount = 50;  Text = 'School fees. Pay {C}50.' }
        @{ Id = 12; Kind = 'CollectFromBank';       Amount = 25;  Text = 'Receive {C}25 consultancy fee.' }
        @{ Id = 13; Kind = 'StreetRepairs';         PerHouse = 40; PerHotel = 115; Text = 'You are assessed for street repairs. {C}40 per house, {C}115 per hotel.' }
        @{ Id = 14; Kind = 'CollectFromBank';       Amount = 10;  Text = 'You have won second prize in a beauty contest. Collect {C}10.' }
        @{ Id = 15; Kind = 'CollectFromBank';       Amount = 100; Text = 'You inherit {C}100.' }
    )
}
