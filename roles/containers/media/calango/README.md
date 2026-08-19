# calango role

Deploys **calango** — a web UI to search & download movies/TV/anime — as a
container on the ThinkPad, on the
`docker_default` network, writing into the shared transmission downloads dir so
Sonarr/Radarr can import the results.

## What it does
- Clones the calango repo to `{{ docker_dir }}/calango/src` (`git pull` on
  re-run; restarts the container on change).
- Runs it from the Playwright Python image (Chromium preinstalled); Python deps
  are pip-installed at boot. State persists in `{{ docker_dir }}/calango/state`.
- Publishes `8765` on the host (Caddy proxies `calango.yourdomain.duckdns.org`).
- Finished files land in `/home/igor/transmission-daemon/downloads/calango`.

## Prerequisites
1. **TMDB token** — add to the vault:
   ```
   ansible-vault edit group_vars/all/vault.yml
   # vault_calango_tmdb_token: "<your TMDB v4 Read Access Token>"
   ```
2. **Repo access** — set `calango_repo` to the git URL you deploy from and
   make sure the host can read it (e.g. an SSH deploy key). Without it the
   `git` task fails.

## Usage
```bash
# Full deploy
ansible-playbook playbooks/main.yaml --tags calango
```

> Sonarr/Radarr Torznab integration is parked for now (the app still ships the
> endpoints behind a flag) and is intentionally **not** wired into this role.
