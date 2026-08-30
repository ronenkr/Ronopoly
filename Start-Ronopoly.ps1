<#
.SYNOPSIS
    Ronopoly - a Monopoly game in Windows PowerShell and WPF.

.DESCRIPTION
    Launch with Ronopoly.cmd, or run this directly from an STA PowerShell host.
    If started in an MTA host it relaunches itself, because WPF cannot create a
    window on an MTA thread and the failure is otherwise an opaque exception
    from deep inside PresentationFramework.

.EXAMPLE
    .\Ronopoly.cmd
    .\Ronopoly.cmd -Mode Host
    .\Ronopoly.cmd -Mode Join -HostAddress 192.168.1.42
    .\Ronopoly.cmd -Theme Light -Fast
#>
[CmdletBinding()]
param(
    [ValidateSet('Solo','Host','Join')][string]$Mode = 'Solo',
    [ValidateSet('Dark','Light')][string]$Theme = 'Dark',
    [string]$HostAddress = '127.0.0.1',
    [int]$Port = 0,
    [string]$Name = 'Player',
    [int]$Seed = 0,
    # Bind to 127.0.0.1 only. Useful for testing several clients on one machine:
    # a loopback listen never triggers the Windows Defender prompt.
    [switch]$LoopbackOnly,
    # Skip the dice and token animations.
    [switch]$Fast,
    # Start with the sound effects off (they can also be toggled in the window).
    [switch]$Mute,
    [switch]$LogToFile,
    # Close the window automatically after N seconds. Lets an automated check
    # drive this exact entry point - launcher, bootstrap, window and all.
    [int]$AutoCloseSeconds = 0
)

if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Write-Host 'Ronopoly needs an STA host for WPF; relaunching...' -ForegroundColor Yellow
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', $PSCommandPath,
              '-Mode', $Mode, '-Theme', $Theme, '-HostAddress', $HostAddress, '-Port', $Port,
              '-Name', $Name, '-Seed', $Seed)
    if ($LoopbackOnly) { $argv += '-LoopbackOnly' }
    if ($Fast)         { $argv += '-Fast' }
    if ($Mute)         { $argv += '-Mute' }
    if ($LogToFile)    { $argv += '-LogToFile' }
    if ($AutoCloseSeconds -gt 0) { $argv += @('-AutoCloseSeconds', $AutoCloseSeconds) }
    & powershell.exe @argv
    exit $LASTEXITCODE
}

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'src\Bootstrap.ps1') -Scope App

Initialize-RonLog -Level Info -ToFile:$LogToFile
Write-RonLog "Ronopoly starting - mode $Mode, PowerShell $($PSVersionTable.PSVersion)" -Category app

try {
    Start-RonApp -Mode $Mode -Theme $Theme -HostAddress $HostAddress -Port $Port `
        -PlayerName $Name -Seed $Seed -LoopbackOnly:$LoopbackOnly -FastMode:$Fast -Mute:$Mute `
        -AutoCloseSeconds $AutoCloseSeconds
}
catch {
    Write-RonLog "Fatal: $($_.Exception.Message)" -Level Error -Category app
    Write-Host ''
    Write-Host '  Ronopoly could not start.' -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    if ($_.InvocationInfo) {
        Write-Host "  at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkRed
        Write-Host "  $($_.InvocationInfo.Line.Trim())" -ForegroundColor DarkRed
    }
    Write-Host ''
    exit 1
}
exit 0
