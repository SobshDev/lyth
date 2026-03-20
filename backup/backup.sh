#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Source restic credentials
if [[ -f backup/.env ]]; then
  set -a
  # shellcheck source=/dev/null
  source backup/.env
  set +a
else
  echo "ERROR: backup/.env not found. Copy backup/.env.example and fill in values." >&2
  exit 1
fi

# Validate restic repo is accessible
if ! restic snapshots --json --last >/dev/null 2>&1; then
  echo "ERROR: Cannot access restic repository. Run 'restic init' first." >&2
  exit 1
fi

BACKUP_HOST="$(hostname)"

# Compose project name — must match the deployed stack
COMPOSE_PROJECT="$(docker compose config --format json 2>/dev/null | jq -r '.name')"
if [[ -z "$COMPOSE_PROJECT" || "$COMPOSE_PROJECT" == "null" ]]; then
  echo "ERROR: Could not determine Compose project name." >&2
  exit 1
fi

# Service-to-volume mapping
declare -A SERVICE_VOLUMES=(
  [prometheus]=prometheus-data
  [grafana]=grafana-data
  [loki]=loki-data
  [uptime-kuma]=uptime-kuma-data
)

# Record which services are currently running before we touch anything
RUNNING_BEFORE=()
for svc in "${!SERVICE_VOLUMES[@]}"; do
  if docker compose ps --format json "$svc" 2>/dev/null | grep -q '"running"'; then
    RUNNING_BEFORE+=("$svc")
  fi
done

# Track services we stopped so the EXIT trap can clean up on failure
STOPPED_BY_US=()

cleanup() {
  local exit_code=$?
  if [[ ${#STOPPED_BY_US[@]} -gt 0 ]]; then
    echo "Restarting services stopped by backup..."
    for svc in "${STOPPED_BY_US[@]}"; do
      docker compose start "$svc" 2>/dev/null || true
    done
  fi
  exit "$exit_code"
}
trap cleanup EXIT

# Resolve the full Docker volume name (project_volume)
resolve_volume() {
  local vol="$1"
  local expected="${COMPOSE_PROJECT}_${vol}"
  if docker volume inspect "$expected" >/dev/null 2>&1; then
    echo "$expected"
  fi
}

echo "=== Lyth Backup — $(date -u '+%Y-%m-%d %H:%M:%S UTC') ==="
echo "Host: $BACKUP_HOST | Project: $COMPOSE_PROJECT"

for svc in "${!SERVICE_VOLUMES[@]}"; do
  vol="${SERVICE_VOLUMES[$svc]}"
  tag="${COMPOSE_PROJECT}/${vol}"

  full_vol="$(resolve_volume "$vol")"
  if [[ -z "$full_vol" ]]; then
    echo "WARNING: Volume $vol not found, skipping" >&2
    continue
  fi

  mountpoint="$(docker volume inspect --format '{{.Mountpoint}}' "$full_vol")"

  # Only stop if the service was running
  was_running=false
  for r in "${RUNNING_BEFORE[@]}"; do
    if [[ "$r" == "$svc" ]]; then
      was_running=true
      break
    fi
  done

  if $was_running; then
    echo "Stopping $svc..."
    docker compose stop "$svc"
    STOPPED_BY_US+=("$svc")
  fi

  echo "Backing up $vol ($mountpoint) [tag: $tag]..."
  restic backup "$mountpoint" --tag "$tag" --host "$BACKUP_HOST"

  # Restart immediately to minimize downtime
  if $was_running; then
    echo "Starting $svc..."
    docker compose start "$svc"
    # Remove from STOPPED_BY_US — service is back up
    STOPPED_BY_US=("${STOPPED_BY_US[@]/$svc/}")
  fi
done

# Retention — scoped per volume tag AND host
echo "Applying retention policy..."
for vol in "${SERVICE_VOLUMES[@]}"; do
  tag="${COMPOSE_PROJECT}/${vol}"
  restic forget \
    --tag "$tag" \
    --host "$BACKUP_HOST" \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 6 \
    --prune
done

echo "=== Backup complete — $(date -u '+%Y-%m-%d %H:%M:%S UTC') ==="
