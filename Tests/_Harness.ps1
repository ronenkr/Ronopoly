#
# Ronopoly - test harness.
#
# Deliberately dependency-free. The only Pester on this machine is 3.4.0, whose
# legacy space syntax ("Should Be") breaks the moment anyone installs Pester 5,
# and whose scoping differs enough to matter. Eighty lines of our own is
# version-proof and can dump exactly what a game engine failure needs: the seed
# and the state, not just an expected/actual pair.
#

$script:RonTest = @{
    Suite    = ''
    Context  = ''
    Pass     = 0
    Fail     = 0
    Failures = New-Object System.Collections.ArrayList
    Started  = Get-Date
}

function Describe {
    param([Parameter(Mandatory, Position = 0)][string]$Name,
          [Parameter(Mandatory, Position = 1)][scriptblock]$Body)
    $script:RonTest.Suite = $Name
    Write-Host ''
    Write-Host "  $Name" -ForegroundColor Cyan
    & $Body
    $script:RonTest.Suite = ''
}

function Context {
    param([Parameter(Mandatory, Position = 0)][string]$Name,
          [Parameter(Mandatory, Position = 1)][scriptblock]$Body)
    $prev = $script:RonTest.Context
    $script:RonTest.Context = $Name
    Write-Host "    $Name" -ForegroundColor DarkCyan
    & $Body
    $script:RonTest.Context = $prev
}

function It {
    param([Parameter(Mandatory, Position = 0)][string]$Name,
          [Parameter(Mandatory, Position = 1)][scriptblock]$Body)
    try {
        & $Body
        $script:RonTest.Pass++
        Write-Host "      [ok]   $Name" -ForegroundColor DarkGreen
    }
    catch {
        $script:RonTest.Fail++
        $where = ''
        if ($_.InvocationInfo) { $where = "{0}:{1}" -f (Split-Path -Leaf $_.InvocationInfo.ScriptName), $_.InvocationInfo.ScriptLineNumber }
        $msg = $_.Exception.Message
        [void]$script:RonTest.Failures.Add([pscustomobject]@{
            Suite   = $script:RonTest.Suite
            Context = $script:RonTest.Context
            Test    = $Name
            Message = $msg
            Where   = $where
        })
        Write-Host "      [FAIL] $Name" -ForegroundColor Red
        Write-Host "             $msg" -ForegroundColor Red
        if ($where) { Write-Host "             at $where" -ForegroundColor DarkRed }
    }
}

# --- assertions ------------------------------------------------------------

# Values are truncated: a failing comparison of two serialised games would
# otherwise dump 4 KB of JSON twice and bury every other result.
function Format-AssertValue {
    param($Value, [int]$Max = 160)
    $s = [string]$Value
    if ($s.Length -le $Max) { return $s }
    return ($s.Substring(0, $Max) + "... (" + $s.Length + " chars)")
}

function Assert-Equal {
    param([Parameter(Position = 0)]$Expected, [Parameter(Position = 1)]$Actual, [Parameter(Position = 2)][string]$Because = '')
    if ($Expected -ne $Actual) {
        $extra = ''
        if ($Because) { $extra = "  ($Because)" }
        throw ("expected <{0}> but got <{1}>{2}" -f (Format-AssertValue $Expected), (Format-AssertValue $Actual), $extra)
    }
}

function Assert-NotEqual {
    param([Parameter(Position = 0)]$NotExpected, [Parameter(Position = 1)]$Actual, [Parameter(Position = 2)][string]$Because = '')
    if ($NotExpected -eq $Actual) { throw ("expected anything but <{0}>  {1}" -f $NotExpected, $Because) }
}

function Assert-True {
    param([Parameter(Position = 0)]$Condition, [Parameter(Position = 1)][string]$Because = 'expected $true')
    if (-not $Condition) { throw $Because }
}

function Assert-False {
    param([Parameter(Position = 0)]$Condition, [Parameter(Position = 1)][string]$Because = 'expected $false')
    if ($Condition) { throw $Because }
}

function Assert-Null {
    param([Parameter(Position = 0)]$Value, [Parameter(Position = 1)][string]$Because = 'expected $null')
    if ($null -ne $Value) { throw ("$Because but got <{0}>" -f $Value) }
}

function Assert-NotNull {
    param([Parameter(Position = 0)]$Value, [Parameter(Position = 1)][string]$Because = 'expected non-null')
    if ($null -eq $Value) { throw $Because }
}

# Asserts the scriptblock throws, optionally matching a substring of the message.
function Assert-Throws {
    param([Parameter(Mandatory, Position = 0)][scriptblock]$Body,
          [Parameter(Position = 1)][string]$Match = '')
    $threw = $false
    $message = ''
    try { & $Body } catch { $threw = $true; $message = $_.Exception.Message }
    if (-not $threw) { throw 'expected the scriptblock to throw, but it did not' }
    if ($Match -and ($message -notlike "*$Match*")) {
        throw ("expected a throw matching '{0}' but got '{1}'" -f $Match, $message)
    }
}

# Arrays compare by value, in order. -ne on two arrays is a filter, not a
# boolean, so Assert-Equal cannot be used for them.
function Assert-Sequence {
    param([Parameter(Position = 0)]$Expected, [Parameter(Position = 1)]$Actual, [Parameter(Position = 2)][string]$Because = '')
    $e = @($Expected)
    $a = @($Actual)
    if ($e.Count -ne $a.Count) {
        throw ("expected {0} items <{1}> but got {2} <{3}>  {4}" -f $e.Count, ($e -join ','), $a.Count, ($a -join ','), $Because)
    }
    for ($i = 0; $i -lt $e.Count; $i++) {
        if ($e[$i] -ne $a[$i]) {
            throw ("index {0}: expected <{1}> but got <{2}>   full: <{3}> vs <{4}>  {5}" -f $i, $e[$i], $a[$i], ($e -join ','), ($a -join ','), $Because)
        }
    }
}

# --- reporting -------------------------------------------------------------

function Complete-RonTests {
    $t = $script:RonTest
    $elapsed = (Get-Date) - $t.Started
    Write-Host ''
    if ($t.Fail -eq 0) {
        Write-Host ("  {0} passed in {1:N1}s" -f $t.Pass, $elapsed.TotalSeconds) -ForegroundColor Green
    }
    else {
        Write-Host ("  {0} passed, {1} FAILED in {2:N1}s" -f $t.Pass, $t.Fail, $elapsed.TotalSeconds) -ForegroundColor Red
        foreach ($f in $t.Failures) {
            Write-Host ("    - {0} / {1}: {2}" -f $f.Suite, $f.Test, $f.Message) -ForegroundColor Red
        }
    }
    Write-Host ''
    return $t.Fail
}
