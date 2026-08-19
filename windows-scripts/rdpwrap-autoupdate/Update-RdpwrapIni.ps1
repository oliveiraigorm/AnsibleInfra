<#
.SYNOPSIS
    Downloads the latest rdpwrap.ini from sebaxakerhtc/rdpwrap.ini and swaps it
    in if changed, restarting TermService.

.DESCRIPTION
    Idempotent updater intended to run daily as SYSTEM via Task Scheduler.
    - Downloads upstream INI to a temp file.
    - Compares SHA256 against the currently-installed INI.
    - If different: backs up current INI, stops TermService (+ deps), swaps the
      file, restarts TermService.
    - If same: logs "no change" and exits 0.
    - All output written to a rolling log next to the script.

    Exit codes: 0 = no-op or success, 1 = download failed,
                2 = service restart failed, 3 = unexpected error.

.NOTES
    Source repo: https://github.com/sebaxakerhtc/rdpwrap.ini
    Maintained alongside infra at: ~/infra/windows-scripts/rdpwrap-autoupdate/
#>

[CmdletBinding()]
param(
    [string]$InstallDir = 'C:\Program Files\RDP Wrapper',
    [string]$SourceUrl  = 'https://raw.githubusercontent.com/sebaxakerhtc/rdpwrap.ini/master/rdpwrap.ini',
    [string]$LogDir     = 'C:\ProgramData\rdpwrap-autoupdate',
    [int]$KeepBackups   = 10
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$logFile = Join-Path $LogDir 'update.log'

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK'), $Level, $Message
    Add-Content -Path $logFile -Value $line
    Write-Host $line
}

function Invoke-WithRetry {
    param([scriptblock]$Script, [int]$Tries = 3, [int]$DelaySec = 5)
    for ($i = 1; $i -le $Tries; $i++) {
        try { return & $Script }
        catch {
            if ($i -eq $Tries) { throw }
            Write-Log "attempt $i failed: $($_.Exception.Message); retrying in ${DelaySec}s" 'WARN'
            Start-Sleep -Seconds $DelaySec
        }
    }
}

try {
    Write-Log "=== rdpwrap.ini autoupdate run ==="
    $iniPath = Join-Path $InstallDir 'rdpwrap.ini'
    if (-not (Test-Path $iniPath)) { throw "INI not found at $iniPath" }

    $tmp = New-TemporaryFile
    try {
        Write-Log "downloading $SourceUrl"
        Invoke-WithRetry { Invoke-WebRequest -Uri $SourceUrl -OutFile $tmp -UseBasicParsing -TimeoutSec 60 } | Out-Null

        $newHash = (Get-FileHash -Algorithm SHA256 $tmp).Hash
        $curHash = (Get-FileHash -Algorithm SHA256 $iniPath).Hash
        Write-Log "current sha256: $curHash"
        Write-Log "remote  sha256: $newHash"

        if ($newHash -eq $curHash) {
            Write-Log "no change; exiting"
            exit 0
        }

        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupDir = Join-Path $LogDir 'backups'
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        $backup = Join-Path $backupDir "rdpwrap.ini.$stamp.bak"
        Copy-Item $iniPath $backup -Force
        Write-Log "backed up current INI -> $backup"

        $svc = Get-Service -Name TermService
        $dependents = @(Get-Service -Name TermService -DependentServices |
            Where-Object { $_.Status -eq 'Running' } | Select-Object -ExpandProperty Name)
        Write-Log "stopping TermService (dependents: $($dependents -join ', '))"
        Stop-Service -Name TermService -Force

        try {
            Copy-Item $tmp $iniPath -Force
            Write-Log "swapped INI in place"
        }
        finally {
            try {
                Start-Service -Name TermService
                foreach ($d in $dependents) {
                    try { Start-Service -Name $d } catch { Write-Log "could not restart dependent ${d}: $($_.Exception.Message)" 'WARN' }
                }
                Write-Log "TermService restarted"
            }
            catch {
                Write-Log "FAILED to restart TermService: $($_.Exception.Message)" 'ERROR'
                exit 2
            }
        }

        Get-ChildItem $backupDir -Filter 'rdpwrap.ini.*.bak' |
            Sort-Object LastWriteTime -Descending |
            Select-Object -Skip $KeepBackups |
            Remove-Item -Force -ErrorAction SilentlyContinue

        Write-Log "update complete"
        exit 0
    }
    finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}
catch [System.Net.WebException], [Microsoft.PowerShell.Commands.HttpResponseException] {
    Write-Log "download failed: $($_.Exception.Message)" 'ERROR'
    exit 1
}
catch {
    Write-Log "unexpected error: $($_.Exception.Message)" 'ERROR'
    exit 3
}
