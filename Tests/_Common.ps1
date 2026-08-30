#
# Shared test setup: bootstrap the engine and build small fixed positions.
# Dot-sourced by every *.Tests.ps1 file.
#
$ErrorActionPreference = 'Stop'
$script:TestRoot = Split-Path -Parent $PSCommandPath
. (Join-Path $script:TestRoot '..\src\Bootstrap.ps1')
. (Join-Path $script:TestRoot '_Harness.ps1')

# A deterministic two- to four-player game with nothing owned. Seed is fixed so
# any failure reproduces exactly.
function New-TestGame {
    param(
        [int]$Players = 2,
        [int]$Seed = 999,
        [hashtable]$RuleOverrides = @{}
    )
    $rules = Get-RonDefaultRules
    foreach ($k in $RuleOverrides.Keys) { $rules[$k] = $RuleOverrides[$k] }

    $specs = @()
    $names = @('Ann','Bob','Cat','Dan','Eve','Fay','Gus','Hal')
    for ($i = 0; $i -lt $Players; $i++) {
        $specs += @{ Name = $names[$i]; Kind = 'AI'; AiProfile = 'Normal'; Token = "t$i" }
    }
    return (New-RonGame -Players $specs -Seed $Seed -Rules $rules)
}

# Assigns ownership directly, bypassing payment. For rent and building tests
# that need a specific board position without playing 40 turns to reach it.
function Set-TestOwner {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [Parameter(Mandatory)][int[]]$Indices,
        [int]$Houses = 0,
        [switch]$Mortgaged
    )
    foreach ($i in $Indices) {
        $State.Properties[$i].OwnerId   = $PlayerId
        $State.Properties[$i].Houses    = $Houses
        $State.Properties[$i].Mortgaged = [bool]$Mortgaged
    }
    if ($Houses -gt 0) {
        # Keep the bank's stock consistent so Assert-RonInvariant still holds.
        foreach ($i in $Indices) {
            if ($Houses -eq 5) { $State.Bank.HotelsAvailable -= 1 }
            else               { $State.Bank.HousesAvailable -= $Houses }
        }
    }
}

# Sets a player's cash without breaking money conservation.
function Set-TestCash {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][int]$PlayerId,
        [Parameter(Mandatory)][int]$Cash
    )
    $p = $State.GetPlayer($PlayerId)
    $State.MoneyInPlay += ($Cash - $p.Cash)
    $p.Cash = $Cash
}

function Set-TestPhase {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][string]$Phase,
        [int]$CurrentPlayerId = -1
    )
    if ($CurrentPlayerId -ge 0) { $State.Turn.CurrentPlayerId = $CurrentPlayerId }
    $State.Turn.Phase = $Phase
}
