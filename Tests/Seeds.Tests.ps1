. (Join-Path (Split-Path -Parent $PSCommandPath) '_Common.ps1')

# New-RonGame picks a seed anywhere up to 2^31 when none is given, so every
# derived seed has to survive one that large. The whole suite previously used
# small hand-picked seeds, which is exactly why an Int32 overflow in the AI's
# per-seat RNG reached a real game: "seed * 31" is fine for 42 and catastrophic
# for 1,500,000,000.
Describe 'Seeds' {

    It 'folds any seed into a valid Int32' {
        foreach ($seed in @(0, 1, 42, 69273666, 69273667, 1500000000, 2147483646)) {
            $mixed = Get-RonSeedMix $seed 7 300
            Assert-True ($mixed -is [int]) "seed $seed produced $($mixed.GetType().Name)"
            Assert-True ($mixed -gt 0) "seed $seed produced $mixed"
            Assert-True ($mixed -le 2147483647) "seed $seed produced $mixed"
        }
    }

    It 'gives different seats different streams' {
        $g = New-RonGame -Players @(
            @{ Name = 'A'; Kind = 'AI'; AiProfile = 'Normal'; Token = 't0' },
            @{ Name = 'B'; Kind = 'AI'; AiProfile = 'Normal'; Token = 't1' }
        ) -Seed 1500000000
        $a = Get-RonAiRng -State $g -PlayerId 0
        $b = Get-RonAiRng -State $g -PlayerId 1
        Assert-NotEqual $a.State $b.State 'two seats must not share a stream'
    }

    It 'plays a full game from a huge seed without overflowing' {
        # This is the regression: before the fix, the first AI decision threw
        # "Cannot convert value 4769379045 to type System.Int32".
        foreach ($seed in @(2147483646, 1500000000, 987654321, 69273667)) {
            $g = New-RonGame -Players @(
                @{ Name = 'A'; Kind = 'AI'; AiProfile = 'Expert'; Token = 't0' },
                @{ Name = 'B'; Kind = 'AI'; AiProfile = 'Easy';   Token = 't1' }
            ) -Seed $seed
            for ($n = 0; $n -lt 120 -and -not $g.IsOver; $n++) {
                $action = Get-RonAiAction -State $g
                Assert-NotNull $action "seed $seed stalled in phase $($g.Turn.Phase)"
                $r = Invoke-RonAction -State $g -Action $action
                Assert-True $r.Ok "seed $seed rejected $($action.Kind): $($r.Reason)"
            }
            Assert-RonInvariant -State $g
        }
    }

    It 'plays a full game from a seed New-RonGame chose itself' {
        # The default path a real game takes, which no earlier test covered.
        for ($attempt = 0; $attempt -lt 5; $attempt++) {
            $g = New-RonGame -Players @(
                @{ Name = 'A'; Kind = 'AI'; AiProfile = 'Hard';   Token = 't0' },
                @{ Name = 'B'; Kind = 'AI'; AiProfile = 'Normal'; Token = 't1' }
            )
            Assert-True ($g.Seed -gt 0) 'a seed was chosen'
            for ($n = 0; $n -lt 60 -and -not $g.IsOver; $n++) {
                $action = Get-RonAiAction -State $g
                Assert-NotNull $action "seed $($g.Seed) stalled in phase $($g.Turn.Phase)"
                $r = Invoke-RonAction -State $g -Action $action
                Assert-True $r.Ok "seed $($g.Seed) rejected $($action.Kind): $($r.Reason)"
            }
            Assert-RonInvariant -State $g
        }
    }

    It 'keeps the RNG itself sane at the extremes' {
        foreach ($seed in @(0, 1, 2147483646)) {
            $rng = [RonRng]::new($seed)
            for ($i = 0; $i -lt 500; $i++) {
                $d = $rng.RollDie()
                Assert-True ($d -ge 1 -and $d -le 6) "seed $seed rolled $d"
            }
        }
    }
}

exit (Complete-RonTests)
