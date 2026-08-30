#
# Ronopoly - player tokens.
#
# Glyph is WPF Path mini-language (Geometry.Parse) authored in a 0..100 box,
# so the same string drives the pre-rendered PNG, the on-board token and the
# lobby picker at any size. Colour is the player's identity colour and is used
# for the token disc, the HUD panel accent and the deed owner stripe.
#
@{
    Order = @('hat','car','ship','dog','boot','iron','cat','barrow')

    Tokens = @{
        hat = @{
            Name   = 'Top Hat'
            Colour = '#1C7ED6'
            Glyph  = 'M 34,22 C 34,18 66,18 66,22 L 68,64 L 78,66 C 86,68 86,76 78,78 L 22,78 C 14,76 14,68 22,66 L 32,64 Z'
        }
        car = @{
            Name   = 'Roadster'
            Colour = '#E03131'
            Glyph  = 'M 10,60 L 16,46 C 18,42 22,40 28,39 L 38,30 C 41,27 45,26 50,26 L 64,26 C 70,26 74,29 77,34 L 83,44 C 88,46 90,50 90,56 L 90,64 L 10,64 Z M 26,62 A 8,8 0 1 0 26,78 A 8,8 0 1 0 26,62 Z M 72,62 A 8,8 0 1 0 72,78 A 8,8 0 1 0 72,62 Z'
        }
        ship = @{
            Name   = 'Battleship'
            Colour = '#2F9E44'
            Glyph  = 'M 8,60 L 92,60 L 82,78 L 18,78 Z M 30,60 L 30,44 L 70,44 L 70,60 Z M 46,44 L 46,22 L 52,22 L 52,44 Z M 52,24 L 74,30 L 52,36 Z'
        }
        dog = @{
            Name   = 'Scottie Dog'
            Colour = '#9C36B5'
            Glyph  = 'M 18,44 C 18,36 24,30 34,30 L 60,30 L 62,20 L 70,22 L 72,30 L 80,32 C 86,34 88,40 88,46 L 88,58 L 80,58 L 80,74 L 70,74 L 70,58 L 40,58 L 40,74 L 30,74 L 30,58 L 20,58 C 16,54 16,48 18,44 Z'
        }
        boot = @{
            Name   = 'Boot'
            Colour = '#F59F00'
            Glyph  = 'M 34,18 L 56,18 L 58,44 C 58,50 62,54 70,58 L 84,64 C 90,67 90,78 82,78 L 26,78 C 20,78 18,74 18,68 L 20,30 C 20,22 26,18 34,18 Z'
        }
        iron = @{
            Name   = 'Flat Iron'
            Colour = '#0CA678'
            Glyph  = 'M 14,66 C 14,50 30,38 56,36 L 84,34 C 90,34 92,40 88,44 L 74,58 L 88,64 C 92,66 90,72 84,72 L 20,72 C 16,72 14,70 14,66 Z M 36,36 L 36,26 C 36,20 42,18 50,18 C 58,18 64,20 64,26 L 64,34'
        }
        cat = @{
            Name   = 'Cat'
            Colour = '#E64980'
            Glyph  = 'M 30,34 L 26,16 L 42,26 L 58,26 L 74,16 L 70,34 C 78,42 80,54 80,66 L 80,78 L 20,78 L 20,66 C 20,54 22,42 30,34 Z M 78,50 C 88,46 92,54 86,60'
        }
        barrow = @{
            Name   = 'Wheelbarrow'
            Colour = '#F76707'
            Glyph  = 'M 14,34 L 76,34 L 66,62 L 26,62 Z M 76,34 L 90,26 M 26,62 L 20,74 M 66,62 L 74,74 M 40,62 A 9,9 0 1 0 40,80 A 9,9 0 1 0 40,62 Z'
        }
    }
}
