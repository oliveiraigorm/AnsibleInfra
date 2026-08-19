# windows-scripts

Standalone Windows scripts (PowerShell / batch) that are **not** managed by
Ansible. The Ansible setup in this repo targets Linux hosts; these live here
so they're version-controlled alongside the rest of the infra without being
tangled into a playbook.

Each subfolder is self-contained: a worker script, an `Install-Task.ps1` that
registers a scheduled task, an `Uninstall-Task.ps1`, and a `README.md` with
the install one-liner.

## Layout

| Folder | What it does |
| --- | --- |
| [`rdpwrap-autoupdate/`](./rdpwrap-autoupdate/) | Daily pull of `rdpwrap.ini` from `sebaxakerhtc/rdpwrap.ini`; swaps it in and restarts `TermService` when upstream changes. |

## Conventions

- **No Ansible.** These are run/installed by hand on a Windows box (typically
  via an elevated PowerShell). The `Install-Task.ps1` in each folder handles
  scheduled-task registration so the day-to-day operation is hands-off.
- **Stage out of the repo.** Installers copy the worker script into
  `C:\ProgramData\<name>\` so moving or editing this checkout can't break a
  registered task. Logs and backups live next to the staged worker.
- **Idempotent workers.** Safe to invoke by hand any number of times; the
  scheduled task is just an automatic trigger.
- **SYSTEM, highest privileges.** Anything that touches `Program Files` or
  Windows services runs as SYSTEM via Task Scheduler.

## Adding a new script

1. Create `windows-scripts/<name>/` with the four files above.
2. Document the install command in that folder's README.
3. Add a one-line row to the table above.
