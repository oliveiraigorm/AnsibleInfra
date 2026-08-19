# clamav role

Antivirus for the download + media directories using [ClamAV](https://www.clamav.net/),
deployed **on-demand with a scan-on-arrival watcher** — there is no resident
daemon, so idle RAM/CPU is ~0 (a `clamd` daemon would have cost ~1.2 GB RAM).

## How it works
- **No long-running container.** Every scan is a throwaway `docker run --rm`
  of the official `clamav/clamav` image, which ships `clamscan` + `freshclam`.
- **Scan on arrival, not on a timer.** A small systemd service
  (`clamav-watch`) runs `inotifywait -m -r` over the watched dirs. inotify is
  passive — it reads no file contents, it just reacts to kernel events
  (`close_write` / `moved_to` = "a file finished being written / was moved in").
  Only the finished file is then scanned. Nothing polls or re-reads your disks.
- **Partials are ignored.** In-progress / temp files (calango's `.calango-tmp/`,
  `.part`, `.ytdl`, `.!qB`, `.crdownload`, `.tmp`, …) are filtered via
  `clamav_ignore_regex`, so a download in flight never triggers a scan.
- **Events are debounced.** A burst (a movie plus its sidecars) is coalesced
  into a single scan after `clamav_debounce_seconds` of quiet.
- **Moved-away files are dropped, not alarmed on.** Transmission and the *arrs
  routinely rename or move a finished download during the debounce window. The
  queue is re-checked immediately before scanning, and a path that vanished
  anyway (clamscan `rc=2` with only "can't access" output) is logged as
  `skipped` — no Pushbullet alert, no `/fail` ping.
- **First deploy scans nothing.** The watcher only reacts to *future* arrivals;
  existing files are left alone unless you run a full scan by hand.
- **Daily definition refresh.** A root cron runs `clamav-freshclam` (default
  04:30) to pull tiny DB deltas into `{{ clamav_db_dir }}` (persisted, ~0.5 GB).
  This only touches the DB dir — never the media drives.

## Components installed
Commands go to `{{ clamav_bin_dir }}` (`/usr/local/bin`), so they are on the
PATH for root's cron *and* for the login user.
- `clamav-scan <path…> | full` — runs the on-demand scan container,
  mounting the DB read-only and the scan roots (`clamav_scan_mounts`) read-only
  (or read-write if quarantine is enabled). Appends to `{{ clamav_log_dir }}/scan.log`.
- `clamav-watch` — the inotify loop; batches arrivals and calls `clamav-scan`.
- `clamav-freshclam` — the definition refresh (used by the daily cron). It
  mounts our own `freshclam.conf` over the image's, which otherwise sets
  `NotifyClamd` and warned "Clamd was NOT notified" on every single run —
  there is no clamd here by design.
- `clamav-watch.service` — systemd unit (Restart=always) that runs the watcher.

## Handling infections
Default is **non-destructive**: infections are only logged — files are never
touched. To *move* (not delete) hits into the quarantine dir instead, set:
```yaml
clamav_quarantine: true
```

## Notifications
On an infection or a scan error (never on a clean scan, so normal downloads are
silent) the scan script fires two independent, optional channels:
- **Pushbullet** (`clamav_pushbullet_cmd`, default `/usr/bin/pushbullet` — the
  host's existing command, token baked in). Sends a real push to your devices
  with the host name and the infected file paths. Set to `""` to disable.
- **Healthcheck ping** (`clamav_infection_ping_url`, default off). A bare
  `curl` GET with `/fail` appended — a passive dead-man's-switch signal for a
  healthchecks.io-style monitor. Carries no detail; empty = no ping.

## Notes
- ClamAV skips files larger than `clamav_max_file_size` (default 200M), so large
  video files are passed over — scans stay quick and focus on the kind of files
  that actually carry malware (archives, scripts, executables, documents).
- **No periodic full scan by default** — scan-on-arrival already covers new
  files, and a full sweep is the only thing that re-reads the disks. Enable a
  weekly baseline with `clamav_full_scan_enabled: true` if you ever want one.
- Deploy: `ansible-playbook playbooks/main.yaml --tags clamav --limit thinkpad`
- Scan by hand: `clamav-scan /path/to/file` or `clamav-scan full`
- Refresh definitions by hand: `clamav-freshclam`
- Watcher logs: `journalctl -u clamav-watch -f` and `{{ clamav_log_dir }}/scan.log`
