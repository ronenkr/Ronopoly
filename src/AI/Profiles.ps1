#
# Ronopoly - AI difficulty profiles.
#
# Difficulty is a PARAMETER TABLE, not a set of code paths. Decide.ps1 has
# exactly one implementation of each decision; only these numbers change.
#
# MistakeRate is what makes Easy feel human: instead of weakening the maths, it
# occasionally plays a random legal action instead of the best one. Three lines
# of code, and far more natural than a bot that is merely bad at arithmetic.
#

$script:RonAiProfiles = @{

    Easy = @{
        BuyThreshold  = 1.15   # required Value/Price ratio before buying
        Aggression    = 0.60   # multiplier on the auction ceiling
        ReserveFactor = 0.40   # multiplier on the cash-reserve target
        BuildFactor   = 0.60   # willingness to spend down to the reserve
        ProposeTrades = $false
        AcceptTrades  = $true
        DenialBids    = $false
        MistakeRate   = 0.15
        JailStayBias  = 0.00   # extra willingness to sit in jail late game
    }

    Normal = @{
        BuyThreshold  = 1.00
        Aggression    = 0.85
        ReserveFactor = 0.80
        BuildFactor   = 0.85
        ProposeTrades = $false
        AcceptTrades  = $true
        DenialBids    = $false
        MistakeRate   = 0.05
        JailStayBias  = 0.10
    }

    Hard = @{
        BuyThreshold  = 0.85
        Aggression    = 1.05
        ReserveFactor = 1.00
        BuildFactor   = 1.00
        ProposeTrades = $true
        AcceptTrades  = $true
        DenialBids    = $false
        MistakeRate   = 0.00
        JailStayBias  = 0.20
    }

    Expert = @{
        BuyThreshold  = 0.75
        Aggression    = 1.25
        ReserveFactor = 1.20
        BuildFactor   = 1.10
        ProposeTrades = $true
        AcceptTrades  = $true
        DenialBids    = $true
        MistakeRate   = 0.00
        JailStayBias  = 0.30
    }
}

function Get-RonAiProfile {
    param([string]$Name = 'Normal')
    if ([string]::IsNullOrEmpty($Name) -or -not $script:RonAiProfiles.ContainsKey($Name)) { $Name = 'Normal' }
    return $script:RonAiProfiles[$Name]
}

function Get-RonAiProfileNames { return @('Easy','Normal','Hard','Expert') }

# Each AI seat gets its own deterministic stream, derived from the game seed
# and the player id, so a simulator failure is reproducible from the seed alone
# and one bot's decisions never shift another's dice.
function Get-RonAiRng {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId
    )
    return [RonRng]::new((Get-RonSeedMix $State.Seed $PlayerId $State.Turn.TurnNumber))
}
