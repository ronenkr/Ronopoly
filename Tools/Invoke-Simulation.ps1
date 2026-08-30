<#
.SYNOPSIS
    Headless AI-vs-AI shakedown for the Ronopoly rules engine.

.DESCRIPTION
    The engine never loads WPF, so this runs at full speed with no UI. Every
    failure is reported WITH ITS SEED and full action log, which is what makes
    a crash 800 turns deep actually fixable.

.EXAMPLE
    .\Tools\Invoke-Simulation.ps1 -Games 1000 -AssertInvariants
    .\Tools\Invoke-Simulation.ps1 -Games 100 -RandomBots -AssertInvariants
#>
[CmdletBinding()]
param(
    [int]$Games = 100,
    [int]$Seed = 42,
    [string[]]$Profiles = @('Expert','Hard','Normal','Easy'),
    [int]$MaxTurns = 1000,
    [switch]$AssertInvariants,
    # Uniformly random legal actions instead of the AI. No strategy at all, but
    # it walks into rule paths a competent bot avoids, so it is the harshest
    # test of the engine itself.
    [switch]$RandomBots,
    [hashtable]$Rules = $null,
    [string]$ReplayDir = '',
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\Bootstrap.ps1')

# Every action would otherwise be uncapped; a stalled FSM must fail loudly
# rather than spin.
$actionBudget = $MaxTurns * 40

$results = New-Object System.Collections.ArrayList
$failures = New-Object System.Collections.ArrayList
$started = Get-Date

for ($n = 0; $n -lt $Games; $n++) {
    $gameSeed = $Seed + $n
    $state = $null
    try {
        $specs = @()
        for ($i = 0; $i -lt $Profiles.Count; $i++) {
            $specs += @{ Name = "$($Profiles[$i])$i"; Kind = 'AI'; AiProfile = $Profiles[$i]; Token = "t$i" }
        }
        $ruleSet = $Rules
        if ($null -eq $ruleSet) { $ruleSet = Get-RonDefaultRules }
        else {
            $copy = Get-RonDefaultRules
            foreach ($k in $ruleSet.Keys) { $copy[$k] = $ruleSet[$k] }
            $ruleSet = $copy
        }

        $state = New-RonGame -Players $specs -Seed $gameSeed -Rules $ruleSet
        Reset-RonActionLog
        $botRng = [RonRng]::new((Get-RonSeedMix $gameSeed 7919))
        $actions = 0

        while (-not $state.IsOver) {
            if ($state.Turn.TurnNumber -gt $MaxTurns) {
                Complete-RonGame -State $state -ByTurnLimit
                break
            }
            $acting = Get-RonActingPlayerId -State $state
            if ($RandomBots) { $action = Get-RonRandomAction -State $state -Rng $botRng -PlayerId $acting }
            else             { $action = Get-RonAiAction     -State $state -PlayerId $acting }

            if ($null -eq $action) {
                throw "deadlock: no legal action for player $acting in phase '$($state.Turn.Phase)'"
            }
            Add-RonAction -Version $state.Version -Action $action
            $r = Invoke-RonAction -State $state -Action $action -AssertInvariants:$AssertInvariants
            if (-not $r.Ok) {
                throw "the bot produced an illegal action '$($action.Kind)' in phase '$($state.Turn.Phase)': $($r.Reason)"
            }
            $actions++
            if ($actions -gt $actionBudget) {
                throw "stall: $actions actions without finishing (phase '$($state.Turn.Phase)', turn $($state.Turn.TurnNumber))"
            }
        }

        $winner = 'none'
        if ($state.WinnerId -ge 0) { $winner = $state.GetPlayer($state.WinnerId).AiProfile }
        [void]$results.Add([pscustomobject]@{
            Seed    = $gameSeed
            Winner  = $winner
            Turns   = $state.Turn.TurnNumber
            Actions = $actions
        })
    }
    catch {
        $msg = $_.Exception.Message
        [void]$failures.Add([pscustomobject]@{ Seed = $gameSeed; Message = $msg })
        if (-not $Quiet) {
            Write-Host ("  [FAIL] seed {0}: {1}" -f $gameSeed, $msg) -ForegroundColor Red
        }
        if ($ReplayDir -and $null -ne $state) {
            $path = Join-Path $ReplayDir "replay-$gameSeed.json"
            [void](Export-RonReplay -State $state -Path $path -Note $msg)
            if (-not $Quiet) { Write-Host "         replay: $path" -ForegroundColor DarkRed }
        }
    }

    $tick = [math]::Max(1, [int]($Games / 20))
    if (-not $Quiet -and (($n + 1) % $tick -eq 0)) {
        Write-Host ("  {0}/{1} games, {2} failures" -f ($n + 1), $Games, $failures.Count) -ForegroundColor DarkGray
    }
}

$elapsed = (Get-Date) - $started
Write-Host ''
Write-Host ("  {0} games in {1:N1}s  ({2:N2}s/game)" -f $Games, $elapsed.TotalSeconds, ($elapsed.TotalSeconds / [math]::Max(1, $Games)))

if ($results.Count -gt 0) {
    $turns = ($results | Measure-Object Turns -Average -Maximum)
    Write-Host ("  turns: avg {0:N0}, max {1:N0}" -f $turns.Average, $turns.Maximum)
    Write-Host '  win rate by profile:'
    foreach ($grp in ($results | Group-Object Winner | Sort-Object Count -Descending)) {
        Write-Host ("    {0,-8} {1,5:P1}  ({2})" -f $grp.Name, ($grp.Count / $results.Count), $grp.Count)
    }
}

if ($failures.Count -gt 0) {
    Write-Host ''
    Write-Host ("  {0} FAILURES" -f $failures.Count) -ForegroundColor Red
    foreach ($grp in ($failures | Group-Object Message | Sort-Object Count -Descending | Select-Object -First 10)) {
        Write-Host ("    x{0,-4} {1}" -f $grp.Count, $grp.Name) -ForegroundColor Red
        Write-Host ("           first seed: {0}" -f $grp.Group[0].Seed) -ForegroundColor DarkRed
    }
    exit 1
}

Write-Host '  no failures' -ForegroundColor Green
exit 0
