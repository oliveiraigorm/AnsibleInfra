<#
.SYNOPSIS
    Removes the 'RDPWrap INI Autoupdate' scheduled task and the staged worker
    script. Leaves logs and backups in place.
#>

[CmdletBinding()]
param(
    [string]$TaskName  = 'RDPWrap INI Autoupdate',
    [string]$TargetDir = 'C:\ProgramData\rdpwrap-autoupdate'
)

$ErrorActionPreference = 'Stop'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This script must run elevated (Administrator)."
}

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Unregistered task '$TaskName'"
} else {
    Write-Host "Task '$TaskName' not registered; nothing to do"
}

$worker = Join-Path $TargetDir 'Update-RdpwrapIni.ps1'
if (Test-Path $worker) {
    Remove-Item $worker -Force
    Write-Host "Removed $worker"
}

Write-Host "Logs and backups preserved under $TargetDir"
