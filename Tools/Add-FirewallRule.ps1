<#
.SYNOPSIS
    Allows Ronopoly through the Windows firewall so other machines can join.

.DESCRIPTION
    Optional. Windows normally prompts once, the first time the game listens on
    a real network interface, and allowing that prompt is enough. This script
    exists for the case where the prompt was dismissed, or where prompts are
    suppressed by policy.

    Must run elevated.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Tools\Add-FirewallRule.ps1
    .\Tools\Add-FirewallRule.ps1 -Remove
#>
[CmdletBinding()]
param(
    [int]$Port = 27015,
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$name = "Ronopoly (TCP $Port)"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal $identity
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ''
    Write-Host '  This needs to run as administrator.' -ForegroundColor Yellow
    Write-Host '  Right-click PowerShell, Run as administrator, then run it again.' -ForegroundColor Yellow
    Write-Host ''
    exit 1
}

if ($Remove) {
    Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Write-Host "  Removed: $name" -ForegroundColor Green
    exit 0
}

if (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue) {
    Write-Host "  Already present: $name" -ForegroundColor DarkGray
    exit 0
}

New-NetFirewallRule -DisplayName $name -Direction Inbound -Action Allow `
    -Protocol TCP -LocalPort $Port -Profile Private, Domain | Out-Null

Write-Host ''
Write-Host "  Added: $name" -ForegroundColor Green
Write-Host '  Private and domain networks only - not public Wi-Fi.' -ForegroundColor DarkGray
Write-Host ''
exit 0
