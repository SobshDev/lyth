# Lyth

Self-hosted monitoring stack for tracking client websites — uptime, latency, TLS certificate expiry, host/container metrics, and logs. Designed for deployment on [Dokploy](https://dokploy.com) with Traefik handling reverse proxy and TLS.

## Stack

| Service | Role | Exposure |
|---|---|---|
| **Grafana** | Dashboards, infrastructure & TLS alerting | Public (TLS + auth) |
| **Uptime Kuma** | Uptime/latency checks, status pages, availability alerts | Public (TLS + auth) |
| **Prometheus** | Metrics scraping & storage | Internal |
| **Loki** | Log aggregation | Internal |
| **Grafana Alloy** | Log collection agent (ships to Loki) | Internal |
| **Blackbox Exporter** | HTTP/HTTPS/TCP/DNS/TLS probing | Internal |
| **Node Exporter** | Host metrics (CPU, memory, disk, network) | Internal |
| **cAdvisor** | Container-level metrics | Internal |

## Prerequisites

- Docker and Dokploy installed on a VPS/server
- A domain pointing to the server
- Docker daemon using the `json-file` logging driver (verify: `docker info | grep "Logging Driver"`)

## Quick Start

1. Clone the repo:
   ```sh
   git clone https://github.com/yourusername/lyth.git
   cd lyth
   ```

2. Copy and fill in environment variables:
   ```sh
   cp .env.example .env
   ```

3. Deploy via Dokploy:
   - Create a new **Docker Compose** project in Dokploy
   - Set environment variables in the Dokploy UI
   - Configure domains:
     - `grafana.yourdomain.com` → Grafana (port 3000)
     - `uptime.yourdomain.com` → Uptime Kuma (port 3001)
   - Deploy

4. Post-deployment setup:
   - **Uptime Kuma** — add HTTP(S) monitors per client site, configure notification channels
   - **Grafana** — configure alert contact points and notification policies

## Adding a Client Website

1. Add the URL to `prometheus/prometheus.yml` under the blackbox-http and blackbox-tls target lists
2. Add an HTTP(S) monitor in Uptime Kuma via the UI
3. Optionally create a status page in Uptime Kuma for the client
4. Redeploy (or wait for Prometheus to pick up config changes on reload)

## Environment Variables

### Grafana (`.env`)

| Variable | Required | Description |
|---|---|---|
| `GF_SECURITY_ADMIN_USER` | Yes | Grafana admin username |
| `GF_SECURITY_ADMIN_PASSWORD` | Yes | Grafana admin password |
| `GF_SMTP_ENABLED` | No | Enable SMTP for alert emails |
| `GF_SMTP_HOST` | No | SMTP server `host:port` |
| `GF_SMTP_USER` | No | SMTP username |
| `GF_SMTP_PASSWORD` | No | SMTP password |
| `GF_SMTP_FROM_ADDRESS` | No | Sender email address |
| `GF_SMTP_FROM_NAME` | No | Sender display name |

### Backups (`backup/.env`)

| Variable | Required | Description |
|---|---|---|
| `RESTIC_REPOSITORY` | Yes | Restic repo path (S3 URL or local path) |
| `RESTIC_PASSWORD` | Yes | Restic encryption password |
| `AWS_ACCESS_KEY_ID` | No | S3 credentials |
| `AWS_SECRET_ACCESS_KEY` | No | S3 credentials |

## Alerting

Alerting is split to avoid duplicate notifications:

- **Uptime Kuma** — site down/up, response time degradation
- **Grafana** — TLS cert expiring (<14 days), disk >85%, memory >90%, sustained CPU >90%

Grafana alert rules are provisioned as code. Contact points are configured via the Grafana UI post-deployment.

## Backups

Backup and restore scripts using [restic](https://restic.net) are in the `backup/` directory.

```sh
# Configure
cp backup/.env.example backup/.env
# Edit backup/.env with your restic repository and credentials

# Backup all volumes
./backup/backup.sh

# Restore
./backup/restore.sh
```

Volumes backed up: `grafana-data`, `uptime-kuma-data`, `prometheus-data`, `loki-data`.

Grafana dashboards are provisioned as code (JSON in `grafana/provisioning/`) and always recoverable from git.

## Project Structure

```
lyth/
├── docker-compose.yml
├── docker/                  # Dockerfiles for each service
│   ├── alloy/
│   ├── blackbox-exporter/
│   ├── cadvisor/
│   ├── grafana/
│   ├── loki/
│   ├── node-exporter/
│   ├── prometheus/
│   └── uptime-kuma/
├── prometheus/
│   └── prometheus.yml       # Scrape targets and jobs
├── blackbox/
│   └── blackbox.yml         # Probe modules
├── loki/
│   └── loki-config.yml
├── alloy/
│   └── config.alloy         # Log collection config
├── grafana/
│   └── provisioning/
│       ├── datasources/     # Auto-provisioned datasources
│       ├── dashboards/      # Dashboard JSON files
│       └── alerting/        # Alert rules
├── backup/
│   ├── backup.sh
│   └── restore.sh
├── .env.example
└── PLAN.md
```

## Security

This is a privileged monitoring deployment. Several services require Docker socket access and host filesystem mounts for metrics and log collection.

Mitigations in place:
- Internal services isolated on `monitoring-internal` network with `traefik.enable=false`
- All containers run with `no-new-privileges`, `cap_drop: ALL`, and `read_only: true` where possible
- All secrets via environment variables, never committed
- Images pinned to specific versions
- Resource limits on all services

See `PLAN.md` for full security details.

## License

MIT
