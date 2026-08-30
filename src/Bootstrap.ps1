#
# Ronopoly - the loader.
#
# Usage (always DOT-SOURCED, never called):
#     . "$root\src\Bootstrap.ps1"            # engine only: no WPF, headless
#     . "$root\src\Bootstrap.ps1" -Scope App # engine + networking + WPF UI
#
# Why dot-sourcing and not a module: a PowerShell 5.1 class defined inside a
# .psm1 is NOT reachable as a type literal from outside the module - [GameState]
# fails with "Unable to find type" even after a successful Import-Module. This
# was measured on this machine, not assumed. Dot-sourcing works, including
# cross-file inheritance, so the whole project is dot-sourced.
#
# Why this file must not wrap the loading in a function: dot-sourcing inside a
# function scopes the results to that function. Bootstrap therefore loads at
# its own script scope, which - because IT is dot-sourced - is the caller's.
#
# The order below is hand-maintained and deliberate. Do NOT replace it with
# Get-ChildItem: alphabetical order is not dependency order, and a silent
# misorder shows up much later as a baffling runtime error.
#
param(
    # Engine  headless rules + AI, loads no WPF at all (tests, simulator)
    # Art     Engine + WPF + Art.ps1 only (the asset generator)
    # App     everything: networking and the full UI
    [ValidateSet('Engine','Art','App')]
    [string]$Scope = 'Engine'
)

# Note: no Set-StrictMode and no $ErrorActionPreference here on purpose. Strict
# mode 2.0 would break the deliberately tolerant FromData property access, and a
# loader has no business imposing preferences on its host - entry points set
# their own.

$script:RonRoot = Split-Path -Parent $PSScriptRoot

# Types.ps1 must be first: everything else uses [GameState] and friends as
# parameter types, which are resolved when each file is parsed.
$script:RonEngineFiles = @(
    'src\Core\Types.ps1'
    'src\Core\Util.ps1'
    'src\Core\Log.ps1'

    'src\Engine\Board.ps1'        # static board queries - no state
    'src\Engine\Events.ps1'       # event constructors + client-side replay
    'src\Engine\State.ps1'        # New-RonGame and state invariants
    'src\Engine\Money.ps1'        # cash transfer + Resolve-RonDebt entry point
    'src\Engine\Rent.ps1'
    'src\Engine\Property.ps1'     # buy / transfer / mortgage
    'src\Engine\Building.ps1'     # even-build rules + bank supply
    'src\Engine\Movement.ps1'
    'src\Engine\Cards.ps1'
    'src\Engine\Auction.ps1'
    'src\Engine\Trade.ps1'
    'src\Engine\Bankruptcy.ps1'
    'src\Engine\Turn.ps1'         # the turn FSM
    'src\Engine\Actions.ps1'      # THE seam: Get/Test/Invoke action

    'src\AI\Profiles.ps1'
    'src\AI\Valuation.ps1'
    'src\AI\TradeAI.ps1'
    'src\AI\Decide.ps1'
)

# Shared by the asset generator and the app: the one definition of the artwork
# and of the sound effects. Sound.ps1 is pure arithmetic - it touches no audio
# device - which is what lets the builder render the .wav cache headlessly.
$script:RonArtFiles = @(
    'src\UI\Art.ps1'
    'src\UI\Sound.ps1'
)

$script:RonAppFiles = @(
    'src\Net\NetCore.cs.ps1'      # inline C# socket engine (compiled once)
    'src\Net\Protocol.ps1'        # framing and message constructors
    'src\Net\Session.ps1'         # THE seam: Local / Host / Client, one shape
    'src\Net\Lobby.ps1'

    'src\UI\Assets.ps1'           # manifest + Art.ps1 fallback
    'src\UI\Audio.ps1'            # playback: the cache, MediaPlayer, mute
    'src\UI\Theme.ps1'
    'src\UI\Xaml\MainWindow.xaml.ps1'
    'src\UI\Board.View.ps1'
    'src\UI\Tokens.View.ps1'
    'src\UI\Dice.View.ps1'
    'src\UI\Hud.View.ps1'
    'src\UI\Overlays.ps1'
    'src\UI\Animator.ps1'
    'src\UI\App.ps1'
)

$script:RonWpfAssemblies = @(
    'PresentationFramework'
    'PresentationCore'
    'WindowsBase'
    'System.Xaml'
    'System.Drawing'
    'System.Windows.Forms'
    'WindowsFormsIntegration'
)

# Resolve and validate the whole list before loading any of it, so a typo is
# reported as one clear message rather than a half-loaded session.
$toLoad = @($script:RonEngineFiles)
if ($Scope -eq 'Art' -or $Scope -eq 'App') { $toLoad += $script:RonArtFiles }
if ($Scope -eq 'App') { $toLoad += $script:RonAppFiles }

$resolved = @()
$missing  = @()
foreach ($rel in $toLoad) {
    $full = Join-Path $script:RonRoot $rel
    if (Test-Path -LiteralPath $full) { $resolved += $full } else { $missing += $rel }
}
if ($missing.Count -gt 0) {
    throw ("Bootstrap: {0} source file(s) missing under '{1}':{2}{3}" -f `
        $missing.Count, $script:RonRoot, [Environment]::NewLine, ($missing -join [Environment]::NewLine))
}

if ($Scope -ne 'Engine') {
    foreach ($asm in $script:RonWpfAssemblies) { Add-Type -AssemblyName $asm }
}

foreach ($full in $resolved) { . $full }

$script:RonLoadedScope = $Scope
