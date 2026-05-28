#!/usr/bin/env bash
# migrate-import.sh — restore export bundle trên server mới.
# Chạy trên SERVER MỚI sau khi đã transfer xong export dir qua scp.
#
# Usage:
#   ./migrate-import.sh /tmp/claude-migrate-<ts>
#
# Env vars (optional):
#   PROJECT_DIR=/path/to/install      # default: /home/$USER/claude-container
#   HOST_HOME=/home/$USER             # nơi extract ~/.claude + ~/doc-parser
#   SKIP_BUILD=1                      # bỏ qua docker compose build (test only)
#   SKIP_START=1                      # bỏ qua docker compose up
#   AUTO_YES=1                        # skip prompt
set -euo pipefail

# ─── Args + config ─────────────────────────────────────────────────────────
BUNDLE="${1:-}"
if [ -z "$BUNDLE" ]; then
  echo "Usage: $0 <path-to-export-dir>" >&2
  echo "  vd: $0 /tmp/claude-migrate-20260528-160000" >&2
  exit 2
fi
[ -d "$BUNDLE" ] || { echo "ERROR: $BUNDLE không phải dir" >&2; exit 1; }

PROJECT_DIR="${PROJECT_DIR:-/home/$USER/claude-container}"
HOST_HOME="${HOST_HOME:-$HOME}"
SKIP_BUILD="${SKIP_BUILD:-0}"
SKIP_START="${SKIP_START:-0}"
AUTO_YES="${AUTO_YES:-0}"

log() { echo -e "[\033[1;34m$(date +%H:%M:%S)\033[0m] $*"; }
err() { echo -e "[\033[1;31mERROR\033[0m] $*" >&2; }

# ─── Sanity checks ─────────────────────────────────────────────────────────
command -v docker >/dev/null || { err "docker chưa cài: curl -fsSL https://get.docker.com | sh"; exit 1; }
docker compose version >/dev/null 2>&1 || { err "docker compose plugin chưa có"; exit 1; }
command -v tar >/dev/null || { err "tar không có"; exit 1; }

MIGRATE_TAR="$BUNDLE/claude-migrate.tar.gz"
HOST_TAR="$BUNDLE/claude-host.tar.gz"
CADDY_TAR="$BUNDLE/caddy-data.tar.gz"
MANIFEST="$BUNDLE/MANIFEST.txt"

[ -f "$MIGRATE_TAR" ] || { err "Missing $MIGRATE_TAR"; exit 1; }

log "Bundle:       $BUNDLE"
log "Project dir:  $PROJECT_DIR (sẽ extract vào đây)"
log "Host home:    $HOST_HOME"
[ -f "$MANIFEST" ] && { echo; cat "$MANIFEST"; echo; }

# ─── Verify checksums (if manifest provides) ──────────────────────────────
if [ -f "$MANIFEST" ] && grep -q sha256= "$MANIFEST"; then
  log "Verifying sha256 checksums..."
  while IFS= read -r line; do
    fname=$(echo "$line" | awk '{print $1}')
    expected=$(echo "$line" | grep -oP 'sha256=\K[a-f0-9]+')
    fpath="$BUNDLE/$fname"
    [ -f "$fpath" ] || continue
    actual=$(sha256sum "$fpath" | awk '{print $1}')
    if [ "$actual" = "$expected" ]; then
      log "  ✓ $fname"
    else
      err "  ✗ $fname mismatch! expected=$expected actual=$actual"
      exit 1
    fi
  done < <(grep -E '\.tar\.gz\s+' "$MANIFEST" | awk '{$1=$1; print}')
fi

# ─── Confirm ───────────────────────────────────────────────────────────────
if [ -d "$PROJECT_DIR" ] && [ "$(ls -A "$PROJECT_DIR" 2>/dev/null)" ]; then
  echo "⚠️  $PROJECT_DIR đã tồn tại + có data. Extract sẽ overwrite một số file."
  if [ "$AUTO_YES" != "1" ]; then
    read -p "Tiếp tục? [y/N] " ans
    case "$ans" in y|Y|yes) ;; *) err "Aborted"; exit 1 ;; esac
  fi
fi

# ─── 1. Restore project ────────────────────────────────────────────────────
log "Extracting project state..."
mkdir -p "$PROJECT_DIR"
tar xzf "$MIGRATE_TAR" -C "$PROJECT_DIR"

# Verify critical files
for f in docker-compose.yml Dockerfile entrypoint.sh server.js; do
  [ -f "$PROJECT_DIR/$f" ] || { err "Sau khi extract, $f vẫn missing"; exit 1; }
done
[ -f "$PROJECT_DIR/.env" ] || log "  ⚠️  .env không có — bạn phải tạo lại (đặc biệt API_KEY)"
[ -f "$PROJECT_DIR/.db/files.sqlite" ] && log "  ✓ DB restored ($(du -h "$PROJECT_DIR/.db/files.sqlite" | cut -f1))"

# ─── 2. Restore host config ────────────────────────────────────────────────
if [ -f "$HOST_TAR" ]; then
  log "Extracting host ~/.claude + ~/doc-parser..."
  mkdir -p "$HOST_HOME"
  tar xzf "$HOST_TAR" -C "$HOST_HOME"
  [ -f "$HOST_HOME/.claude/.credentials.json" ] && log "  ✓ Claude credentials"
  [ -d "$HOST_HOME/doc-parser/src" ] && log "  ✓ doc-parser source"
else
  log "  (no claude-host.tar.gz — skipping)"
fi

# ─── 3. Restore Caddy SSL (optional) ───────────────────────────────────────
if [ -f "$CADDY_TAR" ]; then
  log "Restoring Caddy SSL data into named volume..."
  docker volume create claude-container_caddy_data >/dev/null
  docker run --rm \
    -v claude-container_caddy_data:/data \
    -v "$BUNDLE:/backup:ro" \
    alpine sh -c 'cd /data && tar xzf /backup/caddy-data.tar.gz'
  log "  ✓ Caddy cert volume populated"
else
  log "  (no caddy-data.tar.gz — Let's Encrypt sẽ issue cert mới khi DNS resolve)"
fi

# ─── 4. Check doc-parser mount path ────────────────────────────────────────
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
if grep -q 'home/namvule/doc-parser' "$COMPOSE_FILE"; then
  if [ "$HOST_HOME" != "/home/namvule" ]; then
    log "⚠️  docker-compose.yml hardcode /home/namvule/doc-parser nhưng HOST_HOME=$HOST_HOME"
    log "    → Sửa mount path trong $COMPOSE_FILE trước khi build, vd:"
    echo "       sed -i 's|/home/namvule/doc-parser|$HOST_HOME/doc-parser|g' $COMPOSE_FILE"
  fi
fi

# ─── 5. Build + start ──────────────────────────────────────────────────────
cd "$PROJECT_DIR"

if [ "$SKIP_BUILD" = "1" ]; then
  log "Skipping build (SKIP_BUILD=1)"
else
  log "Building Docker image (~3–5 phút lần đầu)..."
  docker compose build claude-code
fi

if [ "$SKIP_START" = "1" ]; then
  log "Skipping start (SKIP_START=1). Để khởi động:"
  echo "  cd $PROJECT_DIR && docker compose up -d"
  exit 0
fi

log "Starting containers..."
docker compose up -d

# ─── 6. Wait for health ────────────────────────────────────────────────────
log "Waiting for backend to come up (max 60s)..."
for i in $(seq 1 30); do
  if docker compose exec -T claude-code curl -sf http://127.0.0.1:8080/api/v1/health >/dev/null 2>&1; then
    log "  ✓ /health responds OK"
    break
  fi
  sleep 2
done

# ─── 7. Verify doc-parser MCP venv ─────────────────────────────────────────
log "Checking doc-parser MCP venv (entrypoint bootstrap ~2 phút lần đầu)..."
for i in $(seq 1 60); do
  if docker compose logs claude-code 2>&1 | grep -q 'doc-parser venv ready\|pip install failed'; then
    if docker compose logs claude-code 2>&1 | grep -q 'doc-parser venv ready'; then
      log "  ✓ doc-parser MCP ready"
    else
      log "  ⚠️  doc-parser bootstrap FAILED — xem log:"
      docker compose logs claude-code 2>&1 | grep -E 'doc-parser|pip install' | tail -10
    fi
    break
  fi
  sleep 2
done

# ─── Done ──────────────────────────────────────────────────────────────────
echo
log "Migration import done."
echo
log "Verify từng phần:"
echo "  • Health:    curl http://localhost:8080/api/v1/health"
echo "  • Login:     curl -X POST -H 'Content-Type: application/json' \\"
echo "                  -d '{\"username\":\"admin\",\"password\":\"...\"}' \\"
echo "                  http://localhost:8080/api/v1/auth/login"
echo "  • Logs:      cd $PROJECT_DIR && docker compose logs claude-code -f"
echo "  • DB tables: docker compose exec claude-code node -e \\"
echo "                  \"const{DatabaseSync}=require('node:sqlite'); \\"
echo "                  const db=new DatabaseSync('/workspace/.db/files.sqlite'); \\"
echo "                  console.log(db.prepare('SELECT username,is_admin FROM users').all())\""
echo
log "Nếu Mendix PAT login fail → check .env có đúng API_KEY giống server cũ không."
