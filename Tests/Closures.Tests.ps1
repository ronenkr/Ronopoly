. (Join-Path (Split-Path -Parent $PSCommandPath) '_Harness.ps1')

# The closure-in-a-closure trap, caught by reading the source rather than by
# clicking every button in the game.
#
# GetNewClosure() copies the variables LOCAL to the scope it is called from. A
# scriptblock built INSIDE another closure therefore captures that invocation's
# own locals and nothing else: everything the outer closure was built with
# belongs to the outer closure's MODULE, which is not local to anything, and
# the handler silently reads $null instead.
#
# Silently is the problem. Nothing warns, nothing fails at build time, and the
# panel looks perfectly correct until somebody presses the button - which is
# how "choose who to trade with" shipped broken. The overlays are full of
# redraw closures that build click handlers, so this will happen again, and a
# static check costs nothing and never forgets to look.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

# Variables PowerShell provides itself, which are never captured and never
# need to be.
$script:AutoVars = @(
    '_', 'this', 'args', 'null', 'true', 'false', 'psitem', 'input', 'error',
    'foreach', 'switch', 'matches', 'lastexitcode', 'psboundparameters',
    'myinvocation', 'pscommandpath', 'psscriptroot', 'host', 'pwd', 'home',
    'executioncontext', 'stacktrace', 'psversiontable', 'ofs'
)

# Every name the scriptblock makes local to itself: parameters, assignments,
# and foreach/for loop variables.
function Get-TestAssignedNames {
    param([System.Management.Automation.Language.Ast]$Body)
    $names = @{}
    if ($null -ne $Body.ParamBlock) {
        foreach ($p in $Body.ParamBlock.Parameters) { $names[$p.Name.VariablePath.UserPath.ToLower()] = $true }
    }
    foreach ($a in $Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
        if ($a.Left -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $names[$a.Left.VariablePath.UserPath.ToLower()] = $true
        }
        # $a, $b = 1, 2
        if ($a.Left -is [System.Management.Automation.Language.ArrayLiteralAst]) {
            foreach ($el in $a.Left.Elements) {
                if ($el -is [System.Management.Automation.Language.VariableExpressionAst]) {
                    $names[$el.VariablePath.UserPath.ToLower()] = $true
                }
            }
        }
    }
    foreach ($f in $Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst] }, $true)) {
        $names[$f.Variable.VariablePath.UserPath.ToLower()] = $true
    }
    return $names
}

# Names the scriptblock uses but never sets - the ones it must have captured.
function Get-TestFreeNames {
    param([System.Management.Automation.Language.Ast]$Body)
    $assigned = Get-TestAssignedNames -Body $Body
    $free = @{}
    foreach ($v in $Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)) {
        $name = $v.VariablePath.UserPath.ToLower()
        if ($script:AutoVars -contains $name) { continue }
        if ($v.VariablePath.IsGlobal -or $v.VariablePath.IsScript) { continue }
        if ($assigned.ContainsKey($name)) { continue }
        $free[$name] = $v.Extent.StartLineNumber
    }
    return $free
}

# Finds every closure built inside another closure that reads a variable the
# inner one cannot actually see.
function Get-TestUnsafeClosures {
    param([string]$Path = '', [string]$Text = '')
    $tokens = $null
    $errors = $null
    if ($Text) { $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors) }
    else       { $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors) }

    $isClosure = {
        param($n)
        $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
        $n.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
        $n.Member.Value -eq 'GetNewClosure' -and
        $n.Expression -is [System.Management.Automation.Language.ScriptBlockExpressionAst]
    }

    $label = '(inline)'
    if ($Path) { $label = Split-Path -Leaf $Path }

    $found = New-Object System.Collections.ArrayList
    foreach ($outer in $ast.FindAll($isClosure, $true)) {
        $outerBody = $outer.Expression.ScriptBlock
        # What the OUTER closure makes local to each invocation of itself. Only
        # these can be handed on to a closure built inside it.
        $safe = Get-TestAssignedNames -Body $outerBody

        foreach ($inner in $outerBody.FindAll($isClosure, $true)) {
            if ($inner -eq $outer) { continue }
            $free = Get-TestFreeNames -Body $inner.Expression.ScriptBlock
            foreach ($name in $free.Keys) {
                if ($safe.ContainsKey($name)) { continue }
                [void]$found.Add(@{
                    File = $label
                    Line = $inner.Expression.Extent.StartLineNumber
                    Name = $name
                })
            }
        }
    }
    return $found.ToArray()
}

Describe 'Closures in closures' {

    It 'catches a handler that captures nothing' {
        # The check has to be shown to WORK before "it found nothing" means
        # anything at all. This is the exact shape of the bug it exists for.
        $bad = @'
$ctx = @{ Value = 0 }
$redraw = {
    $btn = New-Object System.Windows.Controls.Button
    $btn.Add_Click({ $ctx.Value = 1 }.GetNewClosure())
}.GetNewClosure()
'@
        $hits = @(Get-TestUnsafeClosures -Text $bad)
        Assert-Equal 1 $hits.Count 'the check cannot see the bug it is for'
        Assert-Equal 'ctx' $hits[0].Name
    }

    It 'accepts a handler given a local to hold on to' {
        # And the fix has to pass, or the check is just noise that everybody
        # learns to ignore.
        $good = @'
$ctx = @{ Value = 0 }
$redraw = {
    $offer = $ctx
    $btn = New-Object System.Windows.Controls.Button
    $btn.Add_Click({ $offer.Value = 1 }.GetNewClosure())
}.GetNewClosure()
'@
        Assert-Equal 0 @(Get-TestUnsafeClosures -Text $good).Count 'a correctly bound handler was flagged'
    }

    It 'finds none anywhere in the app' {
        $hits = New-Object System.Collections.ArrayList
        foreach ($file in (Get-ChildItem -Path (Join-Path $root 'src') -Recurse -Filter '*.ps1')) {
            foreach ($h in (Get-TestUnsafeClosures -Path $file.FullName)) { [void]$hits.Add($h) }
        }
        $report = @($hits | ForEach-Object { "$($_.File):$($_.Line) reads `$$($_.Name), which it cannot see" }) -join "; "
        Assert-Equal 0 $hits.Count $report
    }
}

exit (Complete-RonTests)
