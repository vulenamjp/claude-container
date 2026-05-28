#!/bin/bash
set -e

# ─── Sync function: copy read-only personalization mounts into writable paths ──
# Source of truth = host ~/.claude/{skills,plugins,agents}, mounted RO inside the
# container as *-ro. We rsync into the writable location Claude reads from.
# Uses --delete so files removed on the host disappear inside the container too.
sync_personalization() {
  for dir in skills plugins agents; do
    src="/home/node/.claude/${dir}-ro"
    dst="/home/node/.claude/${dir}"
    if [ -d "$src" ]; then
      mkdir -p "$dst"
      rsync -a --delete "${src}/" "${dst}/"
      chown -R node:node "$dst"
    fi
  done
  # Skill .sh scripts need exec bit (rsync preserves source perms; host may not have +x)
  find /home/node/.claude/skills -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

  # Backups: additive only, never delete (host may rotate them)
  if [ -d "/home/node/.claude/backups-ro" ]; then
    mkdir -p /home/node/.claude/backups
    rsync -a "/home/node/.claude/backups-ro/" "/home/node/.claude/backups/"
    chown -R node:node /home/node/.claude/backups
  fi
}

# ─── 1. Initial sync at container startup ─────────────────────────────────────
sync_personalization

# ─── 2. Background watcher: re-sync whenever a RO mount changes on the host ───
# Each Claude process spawned by server.js re-reads the skills/plugins/agents
# directory on startup, so an up-to-date copy on disk is enough — no need to
# notify running processes. Debounce by draining bursts of events within 300ms.
(
  watch_dirs=()
  for dir in skills-ro plugins-ro agents-ro; do
    [ -d "/home/node/.claude/$dir" ] && watch_dirs+=("/home/node/.claude/$dir")
  done
  if [ ${#watch_dirs[@]} -gt 0 ] && command -v inotifywait >/dev/null 2>&1; then
    inotifywait -r -m -q \
      -e modify -e create -e delete -e move -e attrib \
      "${watch_dirs[@]}" 2>/dev/null | \
    while read -r _; do
      while read -r -t 0.3 _; do :; done
      sync_personalization
      echo '{"type":"system","message":"Personalization re-synced from host."}'
    done
  fi
) &

# ─── 3. Khôi phục file cấu hình bảo mật từ Volume ───────────────────────────
# Đọc file lưu cứng, hoặc lấy từ backup tự động của Claude để giữ phiên đăng nhập
if [ -f "/home/node/.claude/real_config.json" ]; then
  cp /home/node/.claude/real_config.json /home/node/.claude.json
  chown node:node /home/node/.claude.json
elif ls /home/node/.claude/backups/.claude.json.backup.* 1> /dev/null 2>&1; then
  LATEST_BACKUP=$(ls -t /home/node/.claude/backups/.claude.json.backup.* | head -n 1)
  cp "$LATEST_BACKUP" /home/node/.claude.json
  chown node:node /home/node/.claude.json
fi

if [ -f "/home/node/.claude.json" ]; then
  echo '{"type":"system","message":"Claude credentials restored from volume."}'
else
  echo '{"type":"system","message":"Notice: No credentials found. You may need manual login."}'
fi

# ─── 3.5. Bootstrap doc-parser MCP (container-side venv + project .mcp.json) ─
# Venv được build vào /opt/doc-parser-venv (named volume) — chỉ chạy pip install
# 1 lần cho đến khi volume bị xóa hoặc source thay đổi. Mount source ở
# /home/namvule/doc-parser:ro — chúng ta không sửa thư mục host.
if [ -d "/home/namvule/doc-parser/src" ]; then
  if [ ! -x "/opt/doc-parser-venv/bin/python" ]; then
    echo '{"type":"system","message":"Bootstrapping doc-parser venv (one-time)..."}'
    # Source mounted RO + setuptools egg_info step cố touch src/*.egg-info → fail.
    # Rsync source vào writable temp dir, loại bỏ build artifacts từ host, rồi install từ đó.
    gosu node rm -rf /tmp/doc-parser-src
    gosu node rsync -a \
      --exclude=myenv --exclude=.git --exclude=.pytest_cache \
      --exclude='*.egg-info' --exclude=__pycache__ --exclude='*.pyc' \
      /home/namvule/doc-parser/ /tmp/doc-parser-src/
    gosu node python3 -m venv /opt/doc-parser-venv
    gosu node /opt/doc-parser-venv/bin/pip install --no-cache-dir --upgrade pip >/dev/null
    gosu node /opt/doc-parser-venv/bin/pip install --no-cache-dir /tmp/doc-parser-src \
      && echo '{"type":"system","message":"doc-parser venv ready at /opt/doc-parser-venv"}' \
      || echo '{"type":"system","message":"WARNING: doc-parser pip install failed — MCP will be unavailable."}'
    gosu node rm -rf /tmp/doc-parser-src
  fi

  # Bake project-level .mcp.json pointing at container venv (overrides host's
  # ~/.claude.json path which doesn't exist inside the container).
  gosu node bash -c 'cat > /workspace/.mcp.json <<EOF
{
  "mcpServers": {
    "doc-parser": {
      "command": "/opt/doc-parser-venv/bin/python",
      "args": ["-m", "doc_parser.server"]
    }
  }
}
EOF'
fi

# ─── 4. Workspace setup ─────────────────────────────────────────────────────
gosu node mkdir -p /workspace/supportFiles /workspace/output

gosu node bash -c 'if [ ! -f /workspace/CLAUDE.local.md ]; then cat > /workspace/CLAUDE.local.md <<EOF
# Project Notes
EOF
fi'

gosu node bash -c '{
  if [ -f /home/node/CLAUDE.md.default ]; then cat /home/node/CLAUDE.md.default; fi
  if [ -f /workspace/CLAUDE.local.md ]; then
    echo -e "\n---\n"
    cat /workspace/CLAUDE.local.md
  fi
} > /workspace/CLAUDE.md'

export LAIDA_PERMISSION_MODE="${LAIDA_PERMISSION_MODE:-auto}"

# ─── 5. Thực thi API Server & Chạy 24/7 ────────────────────────────────────
if [ $# -eq 0 ]; then
  # Nếu gọi `docker compose up -d` (không truyền lệnh phụ), khởi động Server
  echo '{"type":"system","message":"Starting API Server..."}'

  # Server.js được bake vào /opt/app (ngoài /workspace) để ẩn khỏi Claude agent
  exec gosu node node /opt/app/server.js
else
  # Nếu có truyền lệnh (ví dụ: docker compose run --rm claude-code bash)
  # Hệ thống sẽ linh hoạt bỏ qua việc bật server và chạy lệnh bạn yêu cầu
  exec gosu node "$@"
fi
