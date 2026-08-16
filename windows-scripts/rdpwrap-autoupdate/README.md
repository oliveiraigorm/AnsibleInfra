# rdpwrap-autoupdate

Keeps `C:\Program Files\RDP Wrapper\rdpwrap.ini` in sync with upstream
[`sebaxakerhtc/rdpwrap.ini`](https://github.com/sebaxakerhtc/rdpwrap.ini) so
RDP Wrapper keeps working across Windows builds without manual edits.

## What it does

Daily, as SYSTEM:

1. Downloads the latest `rdpwrap.ini` from sebaxakerhtc/master.
2. SHA-256 compares against the installed copy. No diff → exits 0.
3. On diff: backs up the current INI, stops `TermService` (+ running
   dependents), swaps in the new INI, restarts `TermService` (+ deps).
4. Keeps the last 10 backups; everything is logged.

State lives under `C:\ProgramData\rdpwrap-autoupdate\`:
- `update.log` — rolling log
- `backups/rdpwrap.ini.<timestamp>.bak` — previous INIs
- `Update-RdpwrapIni.ps1` — the worker (copied by `Install-Task.ps1`)

The scheduled task is named **`RDPWrap INI Autoupdate`**, triggers daily at
03:17 with a 30-minute random delay, and uses `StartWhenAvailable` so a
missed run catches up on next wake.

## Files

| File | Purpose |
| --- | --- |
| `Update-RdpwrapIni.ps1` | The worker. Idempotent. Safe to run by hand. |
| `Install-Task.ps1` | Copies the worker to `C:\ProgramData\…` and registers the scheduled task. Requires admin. |
| `Uninstall-Task.ps1` | Removes the task and the staged worker. Keeps logs/backups. |

## Install

From an **elevated** PowerShell:

```powershell
cd '\\wsl$\<distro>\home\<user>\ansible-infra\windows-scripts\rdpwrap-autoupdate'
# or copy the folder to a Windows path first if you don't want WSL coupling
powershell -ExecutionPolicy Bypass -File .\Install-Task.ps1
```

Optional: run the worker once immediately to confirm:

```powershell
Start-ScheduledTask -TaskName 'RDPWrap INI Autoupdate'
Get-Content C:\ProgramData\rdpwrap-autoupdate\update.log -Tail 20
```

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\Uninstall-Task.ps1
```

## Manual run

```powershell
powershell -ExecutionPolicy Bypass -File .\Update-RdpwrapIni.ps1
```

Override defaults if needed:

```powershell
.\Update-RdpwrapIni.ps1 -InstallDir 'D:\Tools\RDP Wrapper' `
                        -SourceUrl 'https://example/rdpwrap.ini' `
                        -KeepBackups 5
```

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | No change, or update succeeded |
| 1 | Download failed |
| 2 | INI swapped but `TermService` failed to restart (manual recovery needed) |
| 3 | Unexpected error |

## Why a separate target dir?

The worker is staged into `C:\ProgramData\rdpwrap-autoupdate\` rather than
pointed straight at this repo, so editing/moving the infra checkout can't
silently break the scheduled task.
