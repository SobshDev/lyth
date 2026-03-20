# Lyth Backup & Restore

Automated backup of Docker volumes using [restic](https://restic.net/) to S3-compatible storage.

## Backed-up volumes

| Volume | Service | Data |
|---|---|---|
| `prometheus-data` | Prometheus | Metrics TSDB (30-day retention) |
| `grafana-data` | Grafana | Dashboards, users, alert state |
| `loki-data` | Loki | Log index and chunks (14-day retention) |
| `uptime-kuma-data` | Uptime Kuma | SQLite database (monitors, status pages) |

Grafana dashboards and alert rules are also provisioned as code in the repo — they're always recoverable from git even without a backup.

## Prerequisites

- **restic** installed on the host (`apt install restic` / `brew install restic`)
- **jq** installed on the host (`apt install jq`)
- **Root access** (required to read Docker volume mount paths)
- S3-compatible storage bucket (or any [restic-supported backend](https://restic.readthedocs.io/en/latest/030_preparing_a_new_repo.html))

## Setup

### 1. Configure credentials

```bash
cp backup/.env.example backup/.env
# Edit backup/.env with your repository URL and credentials
```

### 2. Initialize the restic repository

```bash
source backup/.env
restic init
```

### 3. Set up cron

```bash
# Daily backup at 3am
sudo crontab -e
# Add:
0 3 * * * cd /path/to/lyth && backup/backup.sh >> /var/log/lyth-backup.log 2>&1
```

## Usage

### Manual backup

```bash
sudo backup/backup.sh
```

The script will:
1. Stop each service one at a time (to flush WAL/journal for consistent snapshots)
2. Back up the volume with restic (tagged by project and volume name)
3. Restart the service immediately (minimizes per-service downtime)
4. Apply the retention policy after all volumes are backed up

### Restore

```bash
# Restore latest snapshot for a volume
sudo backup/restore.sh --volume grafana-data

# Restore a specific snapshot
sudo backup/restore.sh --volume grafana-data --snapshot abc123de

# Preview without restoring
sudo backup/restore.sh --volume grafana-data --dry-run
```

The restore script stops the owning service, clears the volume, restores from the snapshot, then restarts the service.

### List snapshots

```bash
source backup/.env
restic snapshots --tag "lyth/grafana-data"
```

## Retention policy

| Keep | Count |
|---|---|
| Daily | 7 |
| Weekly | 4 |
| Monthly | 6 |

Retention is scoped per volume and per host, so multiple Lyth deployments sharing a restic repository won't interfere with each other.

## How it works

- Volumes are resolved dynamically via `docker volume inspect` (no hardcoded paths)
- Each snapshot is tagged with `<project>/<volume>` (e.g., `lyth/prometheus-data`) and the machine hostname
- Services are stopped before backup to ensure data consistency (TSDB and SQLite stores require quiescing)
- The script tracks which services were running before backup and only restarts those — a service that was already stopped won't be started
- An EXIT trap ensures services are restarted even if the script fails mid-run
