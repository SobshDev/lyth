#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

usage() {
  cat <<EOF
Usage: backup/restore.sh --volume <name> [--snapshot <id>] [--dry-run]

Options:
  --volume    Volume to restore (prometheus-data, grafana-data, loki-data, uptime-kuma-data)
  --snapshot  Snapshot ID to restore from (default: latest for that volume)
  --dry-run   Preview snapshot contents without restoring

Examples:
  backup/restore.sh --volume grafana-data
  backup/restore.sh --volume grafana-data --snapshot abc123de
  backup/restore.sh --volume loki-data --dry-run
EOF
  exit 1
}

VOLUME=""
SNAPSHOT=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --volume) [[ $# -ge 2 ]] || { echo "ERROR: --volume requires a value" >&2; usage; }; VOLUME="$2"; shift 2 ;;
    --snapshot) [[ $# -ge 2 ]] || { echo "ERROR: --snapshot requires a value" >&2; usage; }; SNAPSHOT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
done

[[ -z "$VOLUME" ]] && { echo "ERROR: --volume is required" >&2; usage; }

# Source restic credentials
if [[ -f backup/.env ]]; then
  set -a
  # shellcheck source=/dev/null
  source backup/.env
  set +a
else
  echo "ERROR: backup/.env not found." >&2
  exit 1
fi

BACKUP_HOST="$(hostname)"

COMPOSE_PROJECT="$(docker compose config --format json 2>/dev/null | jq -r '.name')"
if [[ -z "$COMPOSE_PROJECT" || "$COMPOSE_PROJECT" == "null" ]]; then
  echo "ERROR: Could not determine Compose project name." >&2
  exit 1
fi

# Volume-to-service mapping
declare -A VOLUME_SERVICES=(
  [prometheus-data]=prometheus
  [grafana-data]=grafana
  [loki-data]=loki
  [uptime-kuma-data]=uptime-kuma
)

svc="${VOLUME_SERVICES[$VOLUME]:-}"
if [[ -z "$svc" ]]; then
  echo "ERROR: Unknown volume '$VOLUME'" >&2
  echo "Valid volumes: ${!VOLUME_SERVICES[*]}" >&2
  exit 1
fi

tag="${COMPOSE_PROJECT}/${VOLUME}"

# Resolve snapshot — filter by host + tag, pick latest if not specified
if [[ -z "$SNAPSHOT" ]]; then
  SNAPSHOT="$(restic snapshots --json --tag "$tag" --host "$BACKUP_HOST" --latest 1 | jq -r '.[0].id // empty')"
  if [[ -z "$SNAPSHOT" ]]; then
    echo "ERROR: No snapshots found for $VOLUME (tag=$tag, host=$BACKUP_HOST)" >&2
    exit 1
  fi
  echo "Using latest snapshot for $VOLUME: $SNAPSHOT"
else
  # Validate that the user-provided snapshot belongs to this volume/host
  snap_tag="$(restic snapshots --json "$SNAPSHOT" 2>/dev/null | jq -r '.[0].tags[0] // empty')"
  if [[ "$snap_tag" != "$tag" ]]; then
    echo "ERROR: Snapshot $SNAPSHOT does not belong to $VOLUME (expected tag=$tag, got=$snap_tag)" >&2
    exit 1
  fi
fi

# Resolve full Docker volume name and mountpoint
full_vol="${COMPOSE_PROJECT}_${VOLUME}"
if ! docker volume inspect "$full_vol" >/dev/null 2>&1; then
  echo "ERROR: Docker volume $full_vol not found" >&2
  exit 1
fi
mountpoint="$(docker volume inspect --format '{{.Mountpoint}}' "$full_vol")"

if $DRY_RUN; then
  echo "=== DRY RUN ==="
  echo "Would restore snapshot $SNAPSHOT to $mountpoint (service: $svc)"
  echo ""
  echo "Snapshot contents (first 30 entries):"
  restic ls "$SNAPSHOT" | head -30
  exit 0
fi

echo "=== Lyth Restore ==="
echo "Volume:   $VOLUME"
echo "Service:  $svc"
echo "Snapshot: $SNAPSHOT"
echo "Target:   $mountpoint"
echo ""

# Stop the service (mandatory)
echo "Stopping $svc..."
docker compose stop "$svc"

# Clear existing data and restore
echo "Clearing volume contents..."
find "${mountpoint:?}" -mindepth 1 -delete

echo "Restoring from snapshot $SNAPSHOT..."
restic restore "$SNAPSHOT" --target /

# Start the service
echo "Starting $svc..."
docker compose start "$svc"

echo "=== Restore complete ==="
