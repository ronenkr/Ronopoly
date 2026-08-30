#
# Ronopoly - sound playback.
#
# The effects themselves live in Sound.ps1, which is pure arithmetic and knows
# nothing about audio devices. This file is only about getting them out of a
# speaker.
#
# The bank is CACHED as .wav files under Assets\sounds, on exactly the same
# terms as the tile art: the builder writes them, the game writes them itself
# if they are missing, and deleting the folder costs nothing but a slower first
# start. Synthesising the set takes a couple of seconds in PowerShell, which is
# fine once and much too slow every launch.
#
# Playback goes through WPF MediaPlayer rather than SoundPlayer. SoundPlayer
# wraps the Win32 PlaySound API, which has exactly ONE asynchronous voice: the
# second sound to start cuts the first one off mid-note. Rolling the dice and
# then landing on rent was two truncated sounds rather than two sounds.
# MediaPlayer mixes, and gives a volume control for free. SoundPlayer stays as
# the fallback for a machine whose media stack is missing, where it is still
# better than silence.
#

$script:RonAudioPlayers  = @{}   # key -> MediaPlayer
$script:RonAudioFallback = @{}   # key -> SoundPlayer
$script:RonAudioOn       = $true
$script:RonAudioVolume   = 0.75

# Full, half, off - one button cycling three states. Somebody who finds the
# effects intrusive should not have to choose between them and silence, which
# is the only choice a plain mute toggle offers.
$script:RonAudioSteps = @(0.75, 0.32, 0.0)
$script:RonAudioStep  = 0

function Initialize-RonAudio {
    param([switch]$Muted)
    $script:RonAudioOn = -not $Muted
    if ($Muted) { $script:RonAudioStep = 2; $script:RonAudioVolume = 0.0 }
    if ($script:RonAudioPlayers.Count -gt 0 -or $script:RonAudioFallback.Count -gt 0) { return }

    try {
        $built = Build-RonSoundCache
        if ($built -gt 0) {
            Write-RonLog "Built $built sound(s) into the cache." -Level Info -Category audio
        }
    }
    catch {
        # An unwritable folder is not a reason to lose the sound: the effects
        # are still rendered below, just into memory each time.
        Write-RonLog "Could not write the sound cache ($($_.Exception.Message))." -Level Warn -Category audio
    }

    try {
        foreach ($item in (Get-RonSoundCatalogue)) {
            $path = Get-RonSoundCachePath $item.File
            if (-not (Test-Path -LiteralPath $path)) {
                # No file to point MediaPlayer at, so this one is memory-only.
                $bytes = New-RonWavBytes -Samples (& $item.Make)
                Add-RonFallbackPlayer -Key $item.Key -Bytes $bytes
                continue
            }
            $player = New-Object System.Windows.Media.MediaPlayer
            $player.Open((New-Object System.Uri($path)))
            $player.Volume = $script:RonAudioVolume
            $script:RonAudioPlayers[$item.Key] = $player
        }
        Write-RonLog "Loaded $($script:RonAudioPlayers.Count) sounds." -Level Info -Category audio
    }
    catch {
        # A machine with no media stack must still be able to play the game.
        Write-RonLog "MediaPlayer unavailable ($($_.Exception.Message)); falling back." -Level Warn -Category audio
        $script:RonAudioPlayers = @{}
        Initialize-RonAudioFallback
    }
}

function Initialize-RonAudioFallback {
    try {
        foreach ($item in (Get-RonSoundCatalogue)) {
            if ($script:RonAudioFallback.ContainsKey($item.Key)) { continue }
            $path = Get-RonSoundCachePath $item.File
            if (Test-Path -LiteralPath $path) {
                $bytes = [System.IO.File]::ReadAllBytes($path)
            }
            else {
                $bytes = New-RonWavBytes -Samples (& $item.Make)
            }
            Add-RonFallbackPlayer -Key $item.Key -Bytes $bytes
        }
    }
    catch {
        Write-RonLog "Audio unavailable ($($_.Exception.Message)); continuing silently." -Level Warn -Category audio
        $script:RonAudioOn = $false
    }
}

# A SoundPlayer that goes out of scope is collected mid-playback and the sound
# cuts off - the classic .NET audio bug, and the reason these are held in a
# pool rather than created per use.
function Add-RonFallbackPlayer {
    param([Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][byte[]]$Bytes)
    $player = New-Object System.Media.SoundPlayer
    $player.Stream = New-Object System.IO.MemoryStream(, $Bytes)
    $player.Load()
    $script:RonAudioFallback[$Key] = $player
}

function Invoke-RonSound {
    param([Parameter(Mandatory)][string]$Name)
    if (-not $script:RonAudioOn) { return }

    $player = $script:RonAudioPlayers[$Name]
    if ($null -ne $player) {
        try {
            # Rewind before playing: a MediaPlayer sitting at the end of its
            # clip plays nothing at all, which is how a sound silently stops
            # working after its first use.
            $player.Position = [TimeSpan]::Zero
            $player.Play()
            return
        }
        catch {
            $script:RonAudioPlayers.Remove($Name)
        }
    }

    $fallback = $script:RonAudioFallback[$Name]
    if ($null -eq $fallback) {
        Initialize-RonAudioFallback
        $fallback = $script:RonAudioFallback[$Name]
    }
    if ($null -ne $fallback) {
        try { $fallback.Play() } catch { }
    }
}

function Set-RonAudioEnabled {
    param([bool]$Enabled)
    $script:RonAudioOn = $Enabled
    return $script:RonAudioOn
}

function Test-RonAudioEnabled { return $script:RonAudioOn }

# Advances the sound button one state and returns the new volume.
function Step-RonAudioLevel {
    $script:RonAudioStep = ($script:RonAudioStep + 1) % $script:RonAudioSteps.Count
    $level = $script:RonAudioSteps[$script:RonAudioStep]
    [void](Set-RonAudioVolume $level)
    $script:RonAudioOn = ($level -gt 0.0)
    return $level
}

function Get-RonAudioLabel {
    if (-not $script:RonAudioOn) { return 'Muted' }
    if ($script:RonAudioVolume -le 0.5) { return 'Quiet' }
    return 'Sound'
}

# Note: the SoundPlayer fallback has no volume of its own, so on a machine
# without a media stack Quiet plays at full level. Better than losing the
# sound entirely, and it is the rare path.
function Set-RonAudioVolume {
    param([double]$Volume)
    if ($Volume -lt 0.0) { $Volume = 0.0 }
    if ($Volume -gt 1.0) { $Volume = 1.0 }
    $script:RonAudioVolume = $Volume
    foreach ($player in $script:RonAudioPlayers.Values) {
        try { $player.Volume = $Volume } catch { }
    }
    return $script:RonAudioVolume
}

# For diagnostics and tests: how many effects are on the mixing path rather
# than the single-voice fallback.
function Get-RonAudioPlayerCount { return $script:RonAudioPlayers.Count }
