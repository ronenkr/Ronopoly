#
# Ronopoly - logging and the replayable action log.
#
# Two separate things share this file:
#   Write-RonLog     diagnostics for humans (console + rolling file)
#   Add-RonAction    the action log, which together with GameState.Seed makes
#                    any game - including a simulator failure 800 turns deep -
#                    exactly reproducible.
#

$script:RonLogLevel   = 'Info'     # Debug | Info | Warn | Error | None
$script:RonLogFile    = $null
$script:RonLogToHost  = $false
$script:RonActionLog  = New-Object System.Collections.ArrayList

$script:RonLogRank = @{
    Debug = 0
    Info  = 1
    Warn  = 2
    Error = 3
    None  = 99
}

function Initialize-RonLog {
    param(
        [ValidateSet('Debug','Info','Warn','Error','None')][string]$Level = 'Info',
        [switch]$ToFile,
        [switch]$ToHost
    )
    $script:RonLogLevel  = $Level
    $script:RonLogToHost = [bool]$ToHost
    $script:RonLogFile   = $null
    if ($ToFile) {
        $dir = Get-RonPath 'Logs'
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $script:RonLogFile = Join-Path $dir "ronopoly-$stamp-$PID.log"
    }
}

function Write-RonLog {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Message,
        [ValidateSet('Debug','Info','Warn','Error')][string]$Level = 'Info',
        [string]$Category = 'app'
    )
    if ($script:RonLogRank[$Level] -lt $script:RonLogRank[$script:RonLogLevel]) { return }

    $line = '{0} [{1}] {2,-5} {3}' -f (Get-Date -Format 'HH:mm:ss.fff'), $Category, $Level.ToUpper(), $Message

    if ($script:RonLogToHost) {
        if ($Level -eq 'Error')     { Write-Host $line -ForegroundColor Red }
        elseif ($Level -eq 'Warn')  { Write-Host $line -ForegroundColor Yellow }
        elseif ($Level -eq 'Debug') { Write-Host $line -ForegroundColor DarkGray }
        else                        { Write-Host $line }
    }

    if ($null -ne $script:RonLogFile) {
        # -Encoding utf8 is mandatory: Add-Content defaults to the system ANSI
        # codepage on 5.1, which mangles any non-ASCII property name.
        Add-Content -LiteralPath $script:RonLogFile -Value $line -Encoding utf8
    }
}

# --- Action log ------------------------------------------------------------

function Reset-RonActionLog {
    $script:RonActionLog = New-Object System.Collections.ArrayList
}

function Add-RonAction {
    param(
        [Parameter(Mandatory)][int]$Version,
        [Parameter(Mandatory)][object]$Action
    )
    [void]$script:RonActionLog.Add([pscustomobject]@{
        Version = $Version
        Action  = $Action
    })
}

function Get-RonActionLog {
    return $script:RonActionLog.ToArray()
}

# Everything needed to reproduce a failure: the seed, the rule flags and the
# exact action sequence. The simulator writes one of these per crashed game.
function Export-RonReplay {
    param(
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][string]$Path,
        [string]$Note = ''
    )
    $replay = [pscustomobject]@{
        Note      = $Note
        Seed      = $State.Seed
        GameId    = $State.GameId
        Rules     = $State.Rules
        Players   = @($State.Players | ForEach-Object { @{ Id = $_.Id; Name = $_.Name; Kind = $_.Kind; AiProfile = $_.AiProfile } })
        Actions   = Get-RonActionLog
        FinalState = $State.ToData()
    }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Set-Content -LiteralPath $Path -Value (ConvertTo-RonJson $replay -Pretty) -Encoding utf8
    return $Path
}

# --- error accounting ------------------------------------------------------
#
# An exception thrown inside a DispatcherTimer tick is swallowed: the timer
# stops, the game silently freezes, and the process still exits 0. That made a
# real Int32 overflow in the AI's seed derivation invisible to every "does it
# launch?" check. Errors are counted here so a test can assert on them, and the
# timer handlers report rather than die quietly.

$script:RonErrorCount = 0
$script:RonLastError  = ''

function Add-RonError {
    param([Parameter(Mandatory)][string]$Message, [string]$Category = 'app')
    $script:RonErrorCount++
    $script:RonLastError = $Message
    Write-RonLog $Message -Level Error -Category $Category
}

function Get-RonErrorCount { return $script:RonErrorCount }
function Get-RonLastError  { return $script:RonLastError }
function Reset-RonErrors   { $script:RonErrorCount = 0; $script:RonLastError = '' }

# Runs a scriptblock, and turns any exception into a logged, counted, reportable
# error instead of a silent freeze. Every DispatcherTimer handler goes through
# this.
function Invoke-RonGuarded {
    param(
        [Parameter(Mandatory)][scriptblock]$Body,
        [string]$Category = 'app',
        [scriptblock]$OnError = $null
    )
    try { & $Body }
    catch {
        $where = ''
        if ($_.InvocationInfo) {
            $where = " at {0}:{1}" -f (Split-Path -Leaf $_.InvocationInfo.ScriptName), $_.InvocationInfo.ScriptLineNumber
        }
        Add-RonError ("$($_.Exception.Message)$where") $Category
        if ($null -ne $OnError) { & $OnError $_ }
    }
}
