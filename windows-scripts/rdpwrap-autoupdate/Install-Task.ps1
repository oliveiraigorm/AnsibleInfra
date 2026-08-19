<#
.SYNOPSIS
    Installs Update-RdpwrapIni.ps1 to C:\ProgramData\rdpwrap-autoupdate and
    registers a daily SYSTEM scheduled task to run it.

.DESCRIPTION
    Must run elevated. Copies the worker script to a stable location outside
    the source tree (so updating the infra repo doesn't break the task), then
    creates/updates the scheduled task 'RDPWrap INI Autoupdate'.

    Trigger: daily at 03:17 local, with a random 30-min delay and a missed-run
    catch-up on next boot.
#>

[CmdletBinding()]
param(
    [string]$TaskName  = 'RDPWrap INI Autoupdate',
    [string]$TargetDir = 'C:\ProgramData\rdpwrap-autoupdate',
    [string]$RunTime   = '03:17'
)

$ErrorActionPreference = 'Stop'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This script must run elevated (Administrator)."
}

$src = Join-Path $PSScriptRoot 'Update-RdpwrapIni.ps1'
if (-not (Test-Path $src)) { throw "Worker script not found at $src" }

New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
$dest = Join-Path $TargetDir 'Update-RdpwrapIni.ps1'
Copy-Item $src $dest -Force
Write-Host "Installed worker -> $dest"

$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dest`""

$trigger = New-ScheduledTaskTrigger -Daily -At $RunTime
$trigger.RandomDelay = 'PT30M'

$principal = New-ScheduledTaskPrincipal `
    -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -DontStopOnIdleEnd `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 15) `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Removed existing task '$TaskName'"
}

Register-ScheduledTask `
    -TaskName $TaskName `
    -Description 'Daily update of rdpwrap.ini from sebaxakerhtc/rdpwrap.ini' `
    -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null

Write-Host "Registered scheduled task '$TaskName' (daily at $RunTime, +random 30m, as SYSTEM)"
Write-Host ""
Write-Host "Run now with:  Start-ScheduledTask -TaskName '$TaskName'"
Write-Host "View logs at:  $TargetDir\update.log"
