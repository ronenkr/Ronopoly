. (Join-Path (Split-Path -Parent $PSCommandPath) '_Harness.ps1')

# The sound bank, measured rather than listened to.
#
# Audio is the one part of this project that cannot be checked by looking at
# it, so these assert the properties that separate a sound effect from a fault:
# it starts and ends at silence (anything else IS a click, and a click is
# louder than the sound it introduces), it never clips, and it is not empty.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'src\Bootstrap.ps1') -Scope Art

$script:Bank = @{}
foreach ($item in (Get-RonSoundCatalogue)) { $script:Bank[$item.Key] = (& $item.Make) }

function Measure-TestEdge {
    param([double[]]$Samples, [switch]$Tail)
    $rate = Get-RonSoundRate
    $n = $Samples.Length
    $edge = [int]($rate * 0.001)
    $sum = 0.0
    for ($i = 0; $i -lt $edge; $i++) {
        if ($Tail) { $sum += [math]::Abs($Samples[$n - 1 - $i]) }
        else       { $sum += [math]::Abs($Samples[$i]) }
    }
    return ($sum / $edge)
}

Describe 'Sound bank' {

    It 'starts and ends at true silence' {
        foreach ($key in $script:Bank.Keys) {
            $s = $script:Bank[$key]
            Assert-Equal 0.0 ([double]$s[0]) "$key does not start at zero"
            Assert-Equal 0.0 ([double]$s[$s.Length - 1]) "$key does not end at zero"
            # And it must ARRIVE at silence smoothly, not merely touch it: a
            # single zero sample in front of a full-amplitude one is still a
            # click. A millisecond either end has to be quiet.
            Assert-True ((Measure-TestEdge -Samples $s) -lt 0.05) "$key opens with a click"
            Assert-True ((Measure-TestEdge -Samples $s -Tail) -lt 0.01) "$key ends with a click"
        }
    }

    It 'is audible and never clips' {
        foreach ($key in $script:Bank.Keys) {
            $s = $script:Bank[$key]
            $peak = 0.0
            $sumsq = 0.0
            foreach ($v in $s) {
                $a = [math]::Abs($v)
                if ($a -gt $peak) { $peak = $a }
                $sumsq += $v * $v
            }
            $rms = [math]::Sqrt($sumsq / $s.Length)
            Assert-True ($peak -le 0.95) "$key peaks at $peak and will clip"
            Assert-True ($peak -ge 0.25) "$key peaks at only $peak"
            # Loudness follows average level, not the highest sample, so a
            # sustained tone at the same peak as a transient is far louder.
            Assert-True ($rms -ge 0.02) "$key is near-silent (rms $rms)"
            Assert-True ($rms -le 0.25) "$key is much louder than the rest (rms $rms)"
        }
    }

    It 'carries no DC offset' {
        # Filtered noise wanders slowly around zero, and that wander is a thump
        # at the start of playback rather than a sound anyone can name.
        foreach ($key in $script:Bank.Keys) {
            $s = $script:Bank[$key]
            $sum = 0.0
            foreach ($v in $s) { $sum += $v }
            Assert-True ([math]::Abs($sum / $s.Length) -lt 0.01) "$key has a DC offset"
        }
    }

    It 'is short enough to be an effect rather than a tune' {
        foreach ($key in $script:Bank.Keys) {
            $seconds = $script:Bank[$key].Length / [double](Get-RonSoundRate)
            Assert-True ($seconds -gt 0.05) "$key is only $seconds s"
            Assert-True ($seconds -lt 1.5) "$key runs for $seconds s"
        }
    }

    It 'writes a WAV a player can actually read' {
        $samples = $script:Bank['dice']
        $bytes = New-RonWavBytes -Samples $samples
        $text = [System.Text.Encoding]::ASCII.GetString($bytes, 0, 4)
        Assert-Equal 'RIFF' $text 'not a RIFF file'
        Assert-Equal 'WAVE' ([System.Text.Encoding]::ASCII.GetString($bytes, 8, 4)) 'not a WAVE file'
        Assert-Equal 'fmt ' ([System.Text.Encoding]::ASCII.GetString($bytes, 12, 4)) 'no format chunk'
        Assert-Equal 1 ([BitConverter]::ToInt16($bytes, 20)) 'not PCM'
        Assert-Equal 1 ([BitConverter]::ToInt16($bytes, 22)) 'not mono'
        Assert-Equal (Get-RonSoundRate) ([BitConverter]::ToInt32($bytes, 24)) 'wrong sample rate'
        Assert-Equal 16 ([BitConverter]::ToInt16($bytes, 34)) 'not 16-bit'
        Assert-Equal 'data' ([System.Text.Encoding]::ASCII.GetString($bytes, 36, 4)) 'no data chunk'
        Assert-Equal ($samples.Length * 2) ([BitConverter]::ToInt32($bytes, 40)) 'wrong data length'
        Assert-Equal ($samples.Length * 2 + 44) $bytes.Length 'wrong file length'
    }

    It 'has an effect for every sound the game asks to play' {
        # A typo in a sound name is otherwise completely silent - the game
        # simply plays nothing and nobody finds out. Read the names straight
        # out of the animator and check every one of them exists.
        $animator = Get-Content -LiteralPath (Join-Path $root 'src\UI\Animator.ps1') -Raw
        $asked = @([regex]::Matches($animator, "Invoke-RonSound\s+'([^']+)'") |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        Assert-True ($asked.Count -ge 8) "only found $($asked.Count) sound calls to check"
        foreach ($name in $asked) {
            Assert-True $script:Bank.ContainsKey($name) "the game plays '$name', which the bank does not have"
        }
    }

    It 'rebuilds a cache written by an older version' {
        $stamp = Get-RonSoundCachePath 'sounds/version.txt'
        Assert-True (Test-Path -LiteralPath $stamp) 'the cache was never stamped'
        $real = (Get-Content -LiteralPath $stamp -Raw).Trim()
        Assert-Equal ([string](Get-RonSoundBankVersion)) $real 'the cache on disk is stale'
        try {
            Set-Content -LiteralPath $stamp -Value '0' -Encoding ascii
            Assert-False (Test-RonSoundCacheCurrent) 'an old cache was accepted as current'
        }
        finally {
            Set-Content -LiteralPath $stamp -Value $real -Encoding ascii
        }
        Assert-True (Test-RonSoundCacheCurrent) 'the restored stamp was not accepted'
    }
}

exit (Complete-RonTests)
