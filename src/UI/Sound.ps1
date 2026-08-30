#
# Ronopoly - sound synthesis.
#
# Every effect is BUILT here out of arithmetic - filtered noise and summed
# partials - and cached as a .wav beside the artwork, exactly as the tile art
# is. Nothing ships as audio, so there is no sounds folder that can go missing
# and nothing to download.
#
# Two rules run through all of it, and they are most of the difference between
# a sound effect and a beep:
#
#   1. NEVER START OR STOP A WAVEFORM ABRUPTLY. A sample stepping from silence
#      to full amplitude in one go IS a click, and it is the loudest part of
#      the sound - it was the single worst thing about the first version of
#      this file. Every voice gets a few milliseconds of attack, and every
#      finished effect is faded to true zero at both ends.
#   2. NOTHING REAL IS A BARE SINE OR A BARE SQUARE. Objects ring on several
#      partials at once and impacts are filtered noise, so that is what these
#      are: a bell is four partials with the high ones dying first, a die
#      landing is a noise burst through a resonant filter.
#
# Kept apart from Audio.ps1, which does the playing, so the asset builder can
# render the bank without touching a sound device.
#

$script:RonSoundRate = 44100

# Bumped whenever a recipe below changes. A cached .wav built by an older
# version is rebuilt rather than played forever.
$script:RonSoundBankVersion = 3

# --- primitives ------------------------------------------------------------

function New-RonNoiseBuffer {
    param([Parameter(Mandatory)][int]$Count, [int]$Seed = 12345)
    $rng = [RonRng]::new($Seed)
    $out = New-Object 'double[]' $Count
    for ($i = 0; $i -lt $Count; $i++) { $out[$i] = ($rng.NextDouble() * 2.0) - 1.0 }
    return $out
}

# Chamberlin state-variable filter, which gives lowpass and bandpass from the
# same three lines. Stable while the cutoff stays under about a sixth of the
# sample rate, which every use here does.
#
# The cutoff may sweep: a fixed filter on noise is a hiss, and a moving one is
# a gesture - which is the whole difference between "static" and "a card being
# turned over".
function Invoke-RonSvFilter {
    param(
        [Parameter(Mandatory)][double[]]$Samples,
        [double]$Freq = 1000,
        [double]$EndFreq = 0,
        [double]$Q = 2.0,
        [ValidateSet('Low','Band')][string]$Mode = 'Band'
    )
    $rate = $script:RonSoundRate
    $n = $Samples.Length
    if ($n -eq 0) { return $Samples }
    if ($EndFreq -le 0) { $EndFreq = $Freq }
    $damp = 1.0 / [math]::Max(0.5, $Q)
    $ceiling = $rate / 6.0

    $out = New-Object 'double[]' $n
    $low = 0.0
    $band = 0.0
    for ($i = 0; $i -lt $n; $i++) {
        $fc = $Freq + ($EndFreq - $Freq) * ($i / [double]$n)
        if ($fc -gt $ceiling) { $fc = $ceiling }
        if ($fc -lt 20.0) { $fc = 20.0 }
        $f = 2.0 * [math]::Sin([math]::PI * $fc / $rate)

        $low = $low + $f * $band
        $high = $Samples[$i] - $low - $damp * $band
        $band = $band + $f * $high
        if ($Mode -eq 'Low') { $out[$i] = $low } else { $out[$i] = $band }
    }
    return $out
}

# Attack, then exponential decay, applied in place.
#
# The attack is a raised cosine rather than a straight line: a linear ramp
# still has a corner where it meets the sustain, and a corner is a faint click.
function Add-RonEnvelope {
    param(
        [Parameter(Mandatory)][double[]]$Samples,
        [double]$Attack = 0.004,
        [double]$Decay = 10.0
    )
    $rate = $script:RonSoundRate
    $n = $Samples.Length
    $attackSamples = [int]($Attack * $rate)
    if ($attackSamples -lt 1) { $attackSamples = 1 }
    if ($attackSamples -gt $n) { $attackSamples = $n }

    for ($i = 0; $i -lt $n; $i++) {
        $env = [math]::Exp(-$Decay * ($i / [double]$rate))
        if ($i -lt $attackSamples) {
            $env = $env * (0.5 - 0.5 * [math]::Cos([math]::PI * $i / $attackSamples))
        }
        $Samples[$i] = $Samples[$i] * $env
    }
    return $Samples
}

# A struck tone: a fundamental plus partials, each with its own gain and its
# own decay rate.
#
# Per-partial decay is what makes this sound struck rather than played. High
# partials die away far faster than low ones in every real object, and a bell
# whose partials all decay together sounds like an organ.
function New-RonTone {
    param(
        [double]$Freq = 440,
        [double]$EndFreq = 0,
        [double]$Seconds = 0.3,
        [double[]]$Partials = @(1.0),
        [double[]]$PartialGains = @(1.0),
        [double[]]$PartialDecays = $null,
        [double]$Attack = 0.005,
        [double]$Decay = 8.0,
        [double]$Gain = 0.5
    )
    $rate = $script:RonSoundRate
    $n = [int]($rate * $Seconds)
    if ($n -lt 2) { $n = 2 }
    if ($EndFreq -le 0) { $EndFreq = $Freq }

    $count = $Partials.Length
    $phases = New-Object 'double[]' $count
    $gains  = New-Object 'double[]' $count
    $decays = New-Object 'double[]' $count
    for ($p = 0; $p -lt $count; $p++) {
        $gains[$p] = 1.0
        if ($p -lt $PartialGains.Length) { $gains[$p] = $PartialGains[$p] }
        $decays[$p] = $Decay
        if ($null -ne $PartialDecays -and $p -lt $PartialDecays.Length) { $decays[$p] = $PartialDecays[$p] }
    }

    $attackSamples = [int]($Attack * $rate)
    if ($attackSamples -lt 1) { $attackSamples = 1 }
    $step = 2.0 * [math]::PI / $rate

    # One pass over the samples with the partials summed inside it, rather than
    # one pass per partial: in PowerShell the loop itself costs more than the
    # arithmetic in it, so the number of iterations is what to minimise.
    $out = New-Object 'double[]' $n
    for ($i = 0; $i -lt $n; $i++) {
        $t = $i / [double]$rate
        $f = $Freq + ($EndFreq - $Freq) * ($i / [double]$n)
        $attack = 1.0
        if ($i -lt $attackSamples) { $attack = 0.5 - 0.5 * [math]::Cos([math]::PI * $i / $attackSamples) }

        $sum = 0.0
        for ($p = 0; $p -lt $count; $p++) {
            $phases[$p] = $phases[$p] + $step * $f * $Partials[$p]
            $sum += [math]::Sin($phases[$p]) * $gains[$p] * [math]::Exp(-$decays[$p] * $t)
        }
        $out[$i] = $sum * $attack * $Gain
    }
    return $out
}

# A struck or scraped object: noise through a resonant filter. Short and
# high-Q is a tick, longer and lower is a thud, sweeping is a swish.
function New-RonNoiseHit {
    param(
        [double]$Seconds = 0.08,
        [double]$Freq = 2000,
        [double]$EndFreq = 0,
        [double]$Q = 3.0,
        [double]$Attack = 0.001,
        [double]$Decay = 40.0,
        [double]$Gain = 0.5,
        [int]$Seed = 12345,
        [ValidateSet('Low','Band')][string]$Mode = 'Band'
    )
    $n = [int]($script:RonSoundRate * $Seconds)
    if ($n -lt 2) { $n = 2 }
    $noise = New-RonNoiseBuffer -Count $n -Seed $Seed
    $filtered = Invoke-RonSvFilter -Samples $noise -Freq $Freq -EndFreq $EndFreq -Q $Q -Mode $Mode
    [void](Add-RonEnvelope -Samples $filtered -Attack $Attack -Decay $Decay)
    for ($i = 0; $i -lt $n; $i++) { $filtered[$i] = $filtered[$i] * $Gain }
    return $filtered
}

# Lays voices onto one timeline, each starting at its own offset in seconds.
function Add-RonVoices {
    param([Parameter(Mandatory)][object[]]$Voices, [double[]]$Offsets = $null)
    $rate = $script:RonSoundRate
    $length = 0
    for ($v = 0; $v -lt $Voices.Count; $v++) {
        $start = 0
        if ($null -ne $Offsets -and $v -lt $Offsets.Length) { $start = [int]($Offsets[$v] * $rate) }
        $end = $start + $Voices[$v].Length
        if ($end -gt $length) { $length = $end }
    }
    $mix = New-Object 'double[]' $length
    for ($v = 0; $v -lt $Voices.Count; $v++) {
        $start = 0
        if ($null -ne $Offsets -and $v -lt $Offsets.Length) { $start = [int]($Offsets[$v] * $rate) }
        $src = $Voices[$v]
        for ($i = 0; $i -lt $src.Length; $i++) { $mix[$start + $i] += $src[$i] }
    }
    return $mix
}

# The last pass over every effect: block DC, guarantee silence at both edges,
# and normalise to a chosen level.
#
# Normalising per effect rather than trusting the gains is what keeps the set
# balanced - it means a sound can be redesigned without every other sound
# needing its volume re-checked - and it makes clipping structurally
# impossible rather than merely unlikely.
function Complete-RonSound {
    param(
        [Parameter(Mandatory)][double[]]$Samples,
        [double]$Level = 0.6,
        [double]$FadeIn = 0.003,
        [double]$FadeOut = 0.02
    )
    $rate = $script:RonSoundRate
    $n = $Samples.Length
    if ($n -eq 0) { return $Samples }

    # One-pole DC blocker. Filtered noise carries a slow wander that is
    # inaudible on its own but shows up as a thump at the start of playback.
    $prevIn = 0.0
    $prevOut = 0.0
    for ($i = 0; $i -lt $n; $i++) {
        $x = $Samples[$i]
        $y = $x - $prevIn + 0.9995 * $prevOut
        $prevIn = $x
        $prevOut = $y
        $Samples[$i] = $y
    }

    $fadeInN  = [math]::Min([int]($FadeIn * $rate), [int]($n / 2))
    $fadeOutN = [math]::Min([int]($FadeOut * $rate), [int]($n / 2))
    for ($i = 0; $i -lt $fadeInN; $i++) {
        $Samples[$i] = $Samples[$i] * (0.5 - 0.5 * [math]::Cos([math]::PI * $i / $fadeInN))
    }
    for ($i = 0; $i -lt $fadeOutN; $i++) {
        $k = $n - 1 - $i
        $Samples[$k] = $Samples[$k] * (0.5 - 0.5 * [math]::Cos([math]::PI * $i / $fadeOutN))
    }

    $peak = 0.0
    for ($i = 0; $i -lt $n; $i++) {
        $a = [math]::Abs($Samples[$i])
        if ($a -gt $peak) { $peak = $a }
    }
    if ($peak -gt 0.0) {
        $scale = $Level / $peak
        for ($i = 0; $i -lt $n; $i++) { $Samples[$i] = $Samples[$i] * $scale }
    }
    return $Samples
}

# --- the bank --------------------------------------------------------------
#
# Each recipe is a description of a physical event, not of a waveform.

function New-RonDiceSound {
    # Four bounces, irregularly spaced and losing energy. Each is a bright
    # tick (the corner striking) over a shorter woody body (the block of it).
    $voices = @()
    $offsets = @()
    # The gaps SHORTEN as it settles - that deceleration is most of what makes
    # a series of ticks read as a die rather than a drum roll.
    $times  = @(0.000, 0.062, 0.112, 0.150, 0.178)
    $levels = @(0.60,  0.85,  0.66,  0.42,  0.26)
    $tones  = @(2400,  2900,  2150,  2600,  1900)
    for ($i = 0; $i -lt $times.Length; $i++) {
        $voices += ,(New-RonNoiseHit -Seconds 0.05 -Freq $tones[$i] -Q 2.2 -Decay 90 -Gain $levels[$i] -Seed (101 + $i * 37))
        $voices += ,(New-RonNoiseHit -Seconds 0.06 -Freq 420 -Q 3.5 -Decay 70 -Gain ($levels[$i] * 0.7) -Seed (211 + $i * 53))
        $offsets += $times[$i]
        $offsets += $times[$i]
    }
    return (Complete-RonSound -Samples (Add-RonVoices -Voices $voices -Offsets $offsets) -Level 0.55)
}

function New-RonCashSound {
    # A till: coins first, then the bell. The coins are three tiny high ticks
    # a few milliseconds apart, which is what stops the bell sounding like a
    # doorbell.
    $voices = @(
        (New-RonNoiseHit -Seconds 0.03 -Freq 5200 -Q 1.6 -Decay 190 -Gain 0.5 -Seed 401),
        (New-RonNoiseHit -Seconds 0.03 -Freq 4300 -Q 1.8 -Decay 200 -Gain 0.4 -Seed 402),
        (New-RonNoiseHit -Seconds 0.03 -Freq 6100 -Q 1.5 -Decay 210 -Gain 0.35 -Seed 403),
        (New-RonTone -Freq 1046 -Seconds 0.34 -Gain 0.5 -Attack 0.002 `
            -Partials @(1.0, 2.01, 3.02) -PartialGains @(1.0, 0.42, 0.16) -PartialDecays @(9, 15, 24)),
        (New-RonTone -Freq 1568 -Seconds 0.40 -Gain 0.42 -Attack 0.002 `
            -Partials @(1.0, 2.01) -PartialGains @(1.0, 0.30) -PartialDecays @(8, 14))
    )
    $mix = Add-RonVoices -Voices $voices -Offsets @(0.000, 0.021, 0.044, 0.012, 0.096)
    return (Complete-RonSound -Samples $mix -Level 0.60)
}

function New-RonCardSound {
    # Paper. A noise band sweeping upward is a card sliding off the deck; the
    # tick at the end is it landing face up.
    $voices = @(
        (New-RonNoiseHit -Seconds 0.15 -Freq 1100 -EndFreq 5200 -Q 1.1 -Attack 0.018 -Decay 24 -Gain 0.55 -Seed 811),
        (New-RonNoiseHit -Seconds 0.05 -Freq 2600 -Q 1.4 -Decay 80 -Gain 0.35 -Seed 812)
    )
    return (Complete-RonSound -Samples (Add-RonVoices -Voices $voices -Offsets @(0.0, 0.135)) -Level 0.38)
}

function New-RonBuildSound {
    # A wooden house set down on a board: a low body with a click on top of it.
    $voices = @(
        (New-RonTone -Freq 190 -EndFreq 128 -Seconds 0.16 -Gain 0.55 -Attack 0.002 `
            -Partials @(1.0, 2.4) -PartialGains @(1.0, 0.35) -PartialDecays @(26, 42)),
        (New-RonNoiseHit -Seconds 0.05 -Freq 1500 -Q 2.0 -Decay 110 -Gain 0.30 -Seed 555),
        (New-RonNoiseHit -Seconds 0.07 -Freq 380 -Q 4.0 -Decay 60 -Gain 0.35 -Seed 556)
    )
    return (Complete-RonSound -Samples (Add-RonVoices -Voices $voices -Offsets @(0.0, 0.0, 0.0)) -Level 0.50)
}

function New-RonJailSound {
    # A cell door. Metal bars ring on partials nothing like a musical scale -
    # these ratios are roughly those of a struck bar - and the scrape of the
    # strike itself is the noise at the front.
    $voices = @(
        (New-RonNoiseHit -Seconds 0.06 -Freq 3200 -Q 1.2 -Decay 70 -Gain 0.40 -Seed 909),
        (New-RonTone -Freq 300 -Seconds 0.85 -Gain 0.50 -Attack 0.002 `
            -Partials @(1.0, 2.76, 5.40) -PartialGains @(1.0, 0.55, 0.28) -PartialDecays @(3.4, 5.5, 9.0)),
        (New-RonTone -Freq 302 -Seconds 0.85 -Gain 0.28 -Attack 0.002 `
            -Partials @(1.0, 2.76) -PartialGains @(1.0, 0.45) -PartialDecays @(3.6, 6.0))
    )
    return (Complete-RonSound -Samples (Add-RonVoices -Voices $voices -Offsets @(0.0, 0.0, 0.0)) -Level 0.52 -FadeOut 0.05)
}

function New-RonBankruptSound {
    # Everything falling over: a hollow tone sliding down a tenth, and a soft
    # thud underneath it landing at the bottom.
    $voices = @(
        (New-RonTone -Freq 330 -EndFreq 98 -Seconds 0.75 -Gain 0.55 -Attack 0.012 -Decay 3.2 `
            -Partials @(1.0, 3.0, 5.0) -PartialGains @(1.0, 0.16, 0.06) -PartialDecays @(3.2, 4.4, 6.0)),
        (New-RonTone -Freq 92 -EndFreq 66 -Seconds 0.35 -Gain 0.45 -Attack 0.006 `
            -Partials @(1.0) -PartialGains @(1.0) -PartialDecays @(9.0))
    )
    return (Complete-RonSound -Samples (Add-RonVoices -Voices $voices -Offsets @(0.0, 0.52)) -Level 0.42 -FadeOut 0.06)
}

function New-RonWinSound {
    # A rising major triad, each note with a second and third partial so it
    # reads as an instrument rather than a test tone, and the last one left
    # ringing.
    $voices = @(
        (New-RonTone -Freq 523 -Seconds 0.30 -Gain 0.45 -Attack 0.006 `
            -Partials @(1.0, 2.0, 3.0) -PartialGains @(1.0, 0.34, 0.12) -PartialDecays @(7, 11, 16)),
        (New-RonTone -Freq 659 -Seconds 0.30 -Gain 0.45 -Attack 0.006 `
            -Partials @(1.0, 2.0, 3.0) -PartialGains @(1.0, 0.34, 0.12) -PartialDecays @(7, 11, 16)),
        (New-RonTone -Freq 784 -Seconds 0.75 -Gain 0.50 -Attack 0.006 `
            -Partials @(1.0, 2.0, 3.0) -PartialGains @(1.0, 0.38, 0.16) -PartialDecays @(3.4, 6, 10)),
        (New-RonTone -Freq 1046 -Seconds 0.75 -Gain 0.34 -Attack 0.006 `
            -Partials @(1.0, 2.0) -PartialGains @(1.0, 0.28) -PartialDecays @(3.2, 6))
    )
    return (Complete-RonSound -Samples (Add-RonVoices -Voices $voices -Offsets @(0.0, 0.10, 0.20, 0.20)) -Level 0.62 -FadeOut 0.05)
}

function New-RonTradeSound {
    # A deal closing: two notes up, softly, with none of the till's coins.
    $voices = @(
        (New-RonTone -Freq 587 -Seconds 0.22 -Gain 0.45 -Attack 0.008 `
            -Partials @(1.0, 2.0) -PartialGains @(1.0, 0.26) -PartialDecays @(10, 16)),
        (New-RonTone -Freq 880 -Seconds 0.40 -Gain 0.45 -Attack 0.008 `
            -Partials @(1.0, 2.0) -PartialGains @(1.0, 0.26) -PartialDecays @(7, 12))
    )
    return (Complete-RonSound -Samples (Add-RonVoices -Voices $voices -Offsets @(0.0, 0.10)) -Level 0.40)
}

# The catalogue, in the same shape as the art one: a key, the file it caches
# to, and the scriptblock that builds it.
function Get-RonSoundCatalogue {
    return @(
        @{ Key = 'dice';     File = 'sounds/dice.wav';     Make = { New-RonDiceSound } }
        @{ Key = 'cash';     File = 'sounds/cash.wav';     Make = { New-RonCashSound } }
        @{ Key = 'card';     File = 'sounds/card.wav';     Make = { New-RonCardSound } }
        @{ Key = 'build';    File = 'sounds/build.wav';    Make = { New-RonBuildSound } }
        @{ Key = 'jail';     File = 'sounds/jail.wav';     Make = { New-RonJailSound } }
        @{ Key = 'bankrupt'; File = 'sounds/bankrupt.wav'; Make = { New-RonBankruptSound } }
        @{ Key = 'win';      File = 'sounds/win.wav';      Make = { New-RonWinSound } }
        @{ Key = 'trade';    File = 'sounds/trade.wav';    Make = { New-RonTradeSound } }
    )
}

# --- wav -------------------------------------------------------------------

function New-RonWavBytes {
    param([Parameter(Mandatory)][double[]]$Samples)
    $count = $Samples.Length
    $dataBytes = $count * 2
    $stream = New-Object System.IO.MemoryStream
    $w = New-Object System.IO.BinaryWriter $stream
    try {
        $w.Write([byte[]][char[]]'RIFF')
        $w.Write([int](36 + $dataBytes))
        $w.Write([byte[]][char[]]'WAVE')
        $w.Write([byte[]][char[]]'fmt ')
        $w.Write([int]16)                                   # PCM chunk size
        $w.Write([int16]1)                                  # format: PCM
        $w.Write([int16]1)                                  # channels: mono
        $w.Write([int]$script:RonSoundRate)
        $w.Write([int]($script:RonSoundRate * 2))           # byte rate
        $w.Write([int16]2)                                  # block align
        $w.Write([int16]16)                                 # bits per sample
        $w.Write([byte[]][char[]]'data')
        $w.Write([int]$dataBytes)
        foreach ($s in $Samples) {
            $v = $s
            if ($v -gt 1.0) { $v = 1.0 }
            if ($v -lt -1.0) { $v = -1.0 }
            $w.Write([int16]([math]::Round($v * 32000)))
        }
        $w.Flush()
        return $stream.ToArray()
    }
    finally { $w.Dispose() }
}

function Save-RonSoundFile {
    param(
        [Parameter(Mandatory)][double[]]$Samples,
        [Parameter(Mandatory)][string]$Path
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    [System.IO.File]::WriteAllBytes($Path, (New-RonWavBytes -Samples $Samples))
    return $Path
}

# --- the cache -------------------------------------------------------------
#
# On exactly the same terms as the tile art: the builder writes it, the game
# writes it itself if it is missing, and deleting the folder costs nothing but
# a slower first start.

function Get-RonSoundCachePath {
    param([Parameter(Mandatory)][string]$File)
    return (Get-RonPath (Join-Path 'Assets' ($File -replace '/', '\')))
}

# The cache is only trusted when it was written by THIS version of the
# recipes. Without the stamp a redesigned effect would keep playing in its old
# form on every machine that had already run the game once, which is a
# maddening thing to debug from a bug report.
function Test-RonSoundCacheCurrent {
    $stamp = Get-RonSoundCachePath 'sounds/version.txt'
    if (-not (Test-Path -LiteralPath $stamp)) { return $false }
    try {
        $have = (Get-Content -LiteralPath $stamp -Raw -ErrorAction Stop).Trim()
        return ($have -eq [string](Get-RonSoundBankVersion))
    }
    catch { return $false }
}

function Write-RonSoundCacheStamp {
    $stamp = Get-RonSoundCachePath 'sounds/version.txt'
    $dir = Split-Path -Parent $stamp
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -LiteralPath $stamp -Value ([string](Get-RonSoundBankVersion)) -Encoding ascii
}

# Renders any effect whose .wav is missing or stale. Returns the number built,
# so both the app and Tools\Build-Assets.ps1 can report it.
function Build-RonSoundCache {
    param([switch]$Force)
    $current = Test-RonSoundCacheCurrent
    $built = 0
    foreach ($item in (Get-RonSoundCatalogue)) {
        $path = Get-RonSoundCachePath $item.File
        if (-not $Force -and $current -and (Test-Path -LiteralPath $path)) { continue }
        [void](Save-RonSoundFile -Samples (& $item.Make) -Path $path)
        $built++
    }
    if ($built -gt 0) { Write-RonSoundCacheStamp }
    return $built
}

function Get-RonSoundBankVersion { return $script:RonSoundBankVersion }
function Get-RonSoundRate { return $script:RonSoundRate }
