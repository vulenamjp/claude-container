#!/usr/bin/env bash
# migrate-export.sh — đóng gói toàn bộ state để chuyển sang server mới.
# Chạy trên SERVER CŨ, trong thư mục project (chứa docker-compose.yml).
#
# Output:
#   /tmp/claude-migrate-<ts>/claude-migrate.tar.gz   (project state)
#   /tmp/claude-migrate-<ts>/claude-host.tar.gz      (host ~/.claude + ~/doc-parser)
#   /tmp/claude-migrate-<ts>/caddy-data.tar.gz       (SSL certs, optional)
#   /tmp/claude-migrate-<ts>/MANIFEST.txt            (checklist + checksums)
#
# Usage:
#   ./migrate-export.sh            # interactive — sẽ prompt confirm stop container
#   ./migrate-export.sh --yes      # skip prompt (cho automation)
#   SKIP_CADDY=1 ./migrate-export.sh   # bỏ qua Caddy SSL backup
#   OUT_DIR=/path/to/output ./migrate-export.sh
set -euo pipefail

# ─── Config ────────────────────────────────────────────────────────────────
TS=$(date +%Y%m%d-%H%M%S)
OUT_DIR="${OUT_DIR:-/tmp/claude-migrate-$TS}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST_HOME="${HOME:-/home/$USER}"
SKIP_CADDY="${SKIP_CADDY:-0}"
AUTO_YES=0

for arg in "$@"; do
  case "$arg" in
    --yes|-y) AUTO_YES=1 ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

log() { echo -e "[\033[1;34m$(date +%H:%M:%S)\033[0m] $*"; }
err() { echo -e "[\033[1;31mERROR\033[0m] $*" >&2; }

# ─── Sanity checks ─────────────────────────────────────────────────────────
[ -f "$PROJECT_DIR/docker-compose.yml" ] || { err "Not in project dir (missing docker-compose.yml)"; exit 1; }
command -v docker >/dev/null || { err "docker not installed"; exit 1; }
docker compose version >/dev/null 2>&1 || { err "docker compose plugin not available"; exit 1; }

cd "$PROJECT_DIR"
mkdir -p "$OUT_DIR"

log "Project dir: $PROJECT_DIR"
log "Output dir:  $OUT_DIR"
log "Host home:   $HOST_HOME"
echo

# ─── Confirm container stop ────────────────────────────────────────────────
if [ "$AUTO_YES" -ne 1 ]; then
  echo "⚠️  Script này sẽ STOP container (downtime ~5–10 phút) để snapshot DB an toàn."
  read -p "Tiếp tục? [y/N] " ans
  case "$ans" in y|Y|yes) ;; *) err "Aborted by user"; exit 1 ;; esac
fi

# ─── 1. Stop containers ────────────────────────────────────────────────────
log "Stopping containers..."
docker compose down

# ─── 2. Tar project state ──────────────────────────────────────────────────
log "Tarring project state (exclude node_modules, .git, *.bak-*)..."
tar czf "$OUT_DIR/claude-migrate.tar.gz" \
  --exclude='./node_modules' \
  --exclude='./.git' \
  --exclude='./.db/files.sqlite.bak-*' \
  --exclude='./migrate-export.sh' \
  -C "$PROJECT_DIR" .
# Note: migrate-import.sh CỐ Ý được include vào tar để server mới có sẵn script chạy.

# ─── 3. Tar host config ────────────────────────────────────────────────────
log "Tarring host ~/.claude + ~/doc-parser..."
HOST_PATHS=()
[ -f "$HOST_HOME/.claude/.credentials.json" ] && HOST_PATHS+=(.claude/.credentials.json)
for d in skills plugins agents backups; do
  [ -d "$HOST_HOME/.claude/$d" ] && HOST_PATHS+=(".claude/$d")
done
[ -d "$HOST_HOME/doc-parser" ] && HOST_PATHS+=(doc-parser)

if [ ${#HOST_PATHS[@]} -eq 0 ]; then
  log "  (no host config to tar)"
else
  # Exclude doc-parser/myenv (host-specific Python venv, container rebuilds)
  tar czf "$OUT_DIR/claude-host.tar.gz" \
    --exclude='doc-parser/myenv' \
    --exclude='doc-parser/.pytest_cache' \
    --exclude='doc-parser/src/*.egg-info' \
    -C "$HOST_HOME" "${HOST_PATHS[@]}"
fi

# ─── 4. Caddy SSL data (optional) ──────────────────────────────────────────
if [ "$SKIP_CADDY" = "1" ]; then
  log "Skipping Caddy SSL backup (SKIP_CADDY=1)"
else
  CADDY_VOL=$(docker volume ls -q | grep -E 'claude-container_caddy_data$' || true)
  if [ -n "$CADDY_VOL" ]; then
    log "Tarring Caddy SSL data from volume '$CADDY_VOL'..."
    docker run --rm \
      -v "$CADDY_VOL:/data:ro" \
      -v "$OUT_DIR:/backup" \
      alpine tar czf /backup/caddy-data.tar.gz -C /data .
  else
    log "  (no claude-container_caddy_data volume — skipping)"
  fi
fi

# ─── 5. Manifest ──────────────────────────────────────────────────────────
log "Generating manifest..."
{
  echo "=== Claude container migration export ==="
  echo "Timestamp:    $(date -Iseconds)"
  echo "Source host:  $(hostname)"
  echo "Source dir:   $PROJECT_DIR"
  echo "Docker:       $(docker --version)"
  echo
  echo "=== Files ==="
  for f in claude-migrate.tar.gz claude-host.tar.gz caddy-data.tar.gz; do
    if [ -f "$OUT_DIR/$f" ]; then
      size=$(du -h "$OUT_DIR/$f" | cut -f1)
      sha=$(sha256sum "$OUT_DIR/$f" | awk '{print $1}')
      printf '  %-25s  %8s  sha256=%s\n' "$f" "$size" "$sha"
    fi
  done
  echo
  echo "=== Reminders cho server mới ==="
  echo "  - .env có chứa API_KEY (master key cho Mendix PAT encryption). Phải copy chính xác."
  echo "  - DNS A record cần trỏ sang IP server mới (nếu dùng HTTPS qua Caddy)."
  echo "  - Path mount '~/doc-parser' trong docker-compose.yml hardcoded '/home/namvule/doc-parser'."
  echo "    Nếu username trên server mới khác → sửa docker-compose.yml trước khi 'docker compose up'."
} > "$OUT_DIR/MANIFEST.txt"

# ─── Done ──────────────────────────────────────────────────────────────────
echo
log "Done. Files trong: $OUT_DIR"
ls -la "$OUT_DIR"
echo
log "Next steps:"
echo "  1. scp -r $OUT_DIR user@new-server:/tmp/"
echo "  2. Trên server mới:"
echo "     tar xzf /tmp/$(basename "$OUT_DIR")/claude-migrate.tar.gz -C /tmp/extract-helper"
echo "     bash /tmp/extract-helper/migrate-import.sh /tmp/$(basename "$OUT_DIR")"
echo "  (script migrate-import.sh đã được nhúng vào claude-migrate.tar.gz)"
echo
log "Container đang STOPPED. Để khởi động lại trên server cũ:"
echo "  cd $PROJECT_DIR && docker compose up -d"
