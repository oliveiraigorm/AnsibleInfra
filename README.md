# My Personal Infrastructure

> **⚠️ Important Notice**: This repository is a sanitized, public mirror of my private infrastructure repo. Personal information, secrets and encrypted vault files have been removed, and every host-specific value (domains, IPs, Healthchecks.io IDs, emails) is a **placeholder** — e.g. `yourdomain.duckdns.org`, `192.168.1.100`, `<your-unique-uuid>`. Create your own `vault.yml` files and replace the placeholders before using these playbooks.

This repository contains the Ansible playbooks and roles I use to manage my personal infrastructure, primarily my home server (`thinkpad`). It follows the principles of Infrastructure as Code (IaC) to ensure a reproducible, version-controlled, and automated setup.

## Overview

The main goal of this project is to automate the configuration of a home media and utility server. The setup is heavily based on Docker, with various services running in containers.

The core components managed by these playbooks are:

*   **System Configuration**: Base system setup, user management, timezone, etc.
*   **Docker Environment**: Installation and configuration of Docker and Docker Compose.
*   **Containerized Services**: Deployment of various media and utility applications.
*   **Backup Strategy**: A multi-tiered backup system using `rsync` and `restic`.
*   **Reverse Proxy**: Caddy setup for accessing services with automatic HTTPS.
*   **Scheduled Tasks**: Cron jobs for backups and system maintenance, with monitoring via Healthchecks.io.

## Technology Stack

*   **Configuration Management**: Ansible
*   **Containerization**: Docker
*   **Key Services**:
    *   **Media**: Plex, Sonarr, Radarr, Jackett, Prowlarr, Transmission, Tautulli, xTeVe
    *   **Photos**: Immich
    *   **PDF Tools**: Bento PDF
    *   **Dashboard**: Homer
    *   **Database**: PostgreSQL (shared container)
    *   **Network**: Unifi Controller, DuckDNS, Caddy
    *   **Monitoring**: Netdata (system + HTTP availability checks), Scrutiny (disk S.M.A.R.T.)
    *   **Security**: ClamAV (on-demand, scan-on-arrival antivirus)
    *   **Backups**: Restic, rclone

## Backup Strategy

The topology assumes one **primary** external drive plus one or more local
replica drives. The primary holds the restic repository and the `Backup/`
folder that the replicas mirror; drive labels (`wd-1000`, `sk-1000`, `es-500`
in the examples) are just mount names — set your own in `host_vars/`.

**restic** — app data, databases and dotfiles:

*   Every host backs up daily to the repository on the primary drive; remote
    hosts do it over SFTP (see `restic_backup_repository` in `host_vars/`).
*   Per-service source paths are declared as `restic_backup_source_paths`, so
    each service lands in its own tagged snapshot.
*   Optionally, configured Postgres databases are dumped via the shared
    `postgres` container immediately before the run
    (`restic_backup_pg_dump_dbs`).
*   A weekly `restic check` validates repository integrity and reports the
    latest snapshot per tag, flagging stale ones — pushed as a notification,
    with a Healthchecks.io dead-man's switch on failure.

**File replication** — `rsync` (no `--delete`) from the primary out to each
replica, on a staggered schedule. Every job is guarded by a `mountpoint` check
so an unmounted drive fails loudly instead of silently replicating nothing, and
each pings Healthchecks.io on start/success/failure.

> Replicas are all on-site, so this protects against drive failure rather than
> against loss of the location. An off-site copy (e.g. `rclone` to a cloud
> remote — there is a commented-out cron entry for it) is the missing piece.

## Repository Structure

```
infra/
├── group_vars/         # Variables for groups of hosts (e.g., all)
│   ├── all/
│   │   ├── vars.yml    # Common variables
│   │   └── vault.yml   # Encrypted secrets (using Ansible Vault)
├── playbooks/
│   ├── main.yaml       # The main playbook to run
│   └── immich-import.yaml  # Standalone playbook for photo import
├── roles/              # Ansible roles for each component
│   ├── system/
│   ├── docker/
│   ├── cron/
│   ├── restic_backup/
│   ├── containers/
│   │   ├── caddy/
│   │   ├── clamav/
│   │   ├── homer/
│   │   ├── netdata/
│   │   ├── postgres/
│   │   ├── scrutiny/
│   │   └── media/      # plex, sonarr, radarr, immich, ...
│   └── ...
└── windows-scripts/    # Standalone Windows scripts (not managed by Ansible)
```

*   `playbooks/main.yaml`: The main entry point that applies all roles to hosts.
*   `playbooks/immich-import.yaml`: Standalone playbook to import photos to Immich.
*   `group_vars/` and `host_vars/`: Contain all the variables. Sensitive data like passwords and API keys is stored in encrypted `vault.yml` files.
*   `roles/`: Each role is responsible for a specific piece of the infrastructure (e.g., installing Docker, deploying Plex, setting up cron jobs).
*   `windows-scripts/`: Self-contained PowerShell scripts run by hand on a Windows box.

## Setup and Usage

### Prerequisites

1.  **Ansible**: Ensure Ansible is installed on the machine you're running the playbooks from.
2.  **SSH Access**: You need passwordless SSH access to the target hosts (e.g., `thinkpad`, `nodes`) using SSH keys.

### Secrets Management

This repository uses Ansible Vault to manage secrets. The files `group_vars/all/vault.yml` and the host-specific `vault.yml` files should be created and encrypted. They contain all `vault_*` variables referenced in the `vars.yml` files.

1.  **Create a vault password file**:
    This file should be added to your `.gitignore` to prevent it from being committed to version control.
    ```bash
    echo "your-vault-password" > .ansible_vault_pass
    ```

2.  **Create and edit the vault files**:
    ```bash
    ansible-vault create group_vars/all/vault.yml --vault-password-file .ansible_vault_pass
    ansible-vault create host_vars/thinkpad.local/vault.yml --vault-password-file .ansible_vault_pass
    ansible-vault create host_vars/ally/vault.yml --vault-password-file .ansible_vault_pass
    ansible-vault create host_vars/localhost/vault.yml --vault-password-file .ansible_vault_pass
    ```

3.  **Populate the `vault.yml`** files with your secrets:
    ```yaml
    # group_vars/all/vault.yml
    vault_ssh_public_key: "ssh-rsa AAAA..."
    vault_pushbullet_key: "o.xxxxxxxxxx"
    vault_plex_token: "your-plex-token"
    vault_caddy_admin_password_hash: "$2a$14$..."   # caddy hash-password
    # ... and so on for all other secrets
    ```

### Running the Playbook

To apply the configuration, run the main playbook. You will need to provide the vault password.

```bash
# Run against all hosts defined in your inventory
ansible-playbook playbooks/main.yaml --vault-password-file .ansible_vault_pass

# Run only specific tasks using tags
ansible-playbook playbooks/main.yaml --vault-password-file .ansible_vault_pass --tags "docker,plex"

# Run on specific host only
ansible-playbook playbooks/main.yaml --vault-password-file .ansible_vault_pass --limit thinkpad.local
```

### Importing Photos to Immich

To import photos from a folder into Immich using the CLI:

```bash
ansible-playbook playbooks/immich-import.yaml -e import_path=/path/to/photos --vault-password-file .ansible_vault_pass
```

Replace `/path/to/photos` with the folder containing photos you want to import.

## Author

*   Igor Oliveira
