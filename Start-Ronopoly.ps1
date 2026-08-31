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
    .\Ronopoly.cmd -Mode Host -Remote 3
    .\Ronopoly.cmd -Mode Join -HostAddress 192.168.1.42 -Name Ada
    .\Ronopoly.cmd -Theme Light -Fast

.NOTES
    Ronopoly, a board game for Windows PowerShell.
    Copyright (C) 2026 Ronen K

    This program is free software: you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by the Free
    Software Foundation, either version 3 of the License, or (at your option)
    any later version.

    This program is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
    Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program. If not, see <https://www.gnu.org/licenses/>.

    Monopoly is a trademark of Hasbro. This is an independent implementation
    written for fun and is not affiliated with or endorsed by the trademark
    holder.
#>
[CmdletBinding()]
param(
    [ValidateSet('Solo','Host','Join')][string]$Mode = 'Solo',
    [ValidateSet('Dark','Light')][string]$Theme = 'Dark',
    [string]$HostAddress = '127.0.0.1',
    [int]$Port = 0,
    [string]$Name = 'Player',
    [int]$Seed = 0,
    # Seats left open for people joining over the network. Hosting defaults to
    # one; a game with none cannot be joined, however well the sockets work.
    [int]$Remote = -1,
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
              '-Name', $Name, '-Seed', $Seed, '-Remote', $Remote)
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
    if ($Remote -lt 0) {
        # Hosting without saying so means "let one person in"; anything else
        # means none.
        if ($Mode -eq 'Host') { $Remote = 1 } else { $Remote = 0 }
    }
    Start-RonApp -Mode $Mode -Theme $Theme -HostAddress $HostAddress -Port $Port `
        -PlayerName $Name -Seed $Seed -LoopbackOnly:$LoopbackOnly -RemoteSeats $Remote `
        -FastMode:$Fast -Mute:$Mute -AutoCloseSeconds $AutoCloseSeconds
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
