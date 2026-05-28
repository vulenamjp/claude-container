# Migrate container claude-code sang server khác

Hướng dẫn chi tiết để di chuyển toàn bộ stack (claude-code container + Caddy +
SQLite DB + uploads + outputs + host config) sang một server Linux khác.

## 1. State CẦN bring sang server mới

| State | Đường dẫn host | Quan trọng |
|---|---|---|
| Code repo | `/home/namvule/claude-container/` (Dockerfile, server.js, compose, entrypoint, settings.json, Caddyfile…) | ⭐⭐⭐ |
| **DB SQLite** | `./.db/files.sqlite` (users, auth_tokens, workspaces, user_configs, user_mendix_apps) | ⭐⭐⭐ MẤT là mất hết user/login/Mendix PAT |
| User uploads | `./supportFiles/` | ⭐⭐ files đã upload qua chat |
| Claude outputs | `./output/` | ⭐⭐ files Claude đã tạo |
| Project notes | `./CLAUDE.local.md` | ⭐ |
| **`.env`** | `/home/namvule/claude-container/.env` | ⭐⭐⭐ chứa `API_KEY` — dùng để mã hoá Mendix PAT trong DB. Mất là **không decrypt được** Mendix PAT cũ |
| Claude credentials | `~/.claude/.credentials.json` | ⭐⭐⭐ login Claude API |
| Personalization | `~/.claude/{skills,plugins,agents,backups}/` | ⭐⭐ skills custom (mx-bd-builder, …) |
| doc-parser source | `~/doc-parser/` | ⭐⭐ MCP server code |
| Caddy SSL cert | docker volume `caddy_data` | ⭐ nếu dùng HTTPS, không backup thì Let's Encrypt issue lại |

## 2. State KHÔNG cần migrate (rebuild được)

- `node_modules/` — npm install lại
- Docker images — `docker compose build` lại trên server mới
- `doc-parser-venv` volume — entrypoint tự bootstrap lần đầu start (~2 phút)
- `claude-data` volume — entrypoint khôi phục từ `~/.claude/backups/`

## 3. State auto-wipe mỗi restart (không cần migrate)

Server.js drop mỗi lần start (server.js:55–58):

- Bảng `sessions`, `files`, `messages` — chat history sẽ mất khi restart. Đây
  là behavior hiện tại, migration không thay đổi gì.

---

## Migration playbook

### A. Trên server CŨ — đóng gói

```bash
cd /home/namvule/claude-container

# Stop để DB không bị write giữa lúc tar
docker compose down

# Snapshot DB consistent (đã làm) hoặc cp trực tiếp khi đã stop
cp .db/files.sqlite .db/files.sqlite.bak-migrate

# Tar project state
tar czf /tmp/claude-migrate.tar.gz \
  --exclude='node_modules' \
  --exclude='.git' \
  .

# Tar host-level Claude config + doc-parser
tar czf /tmp/claude-host.tar.gz \
  -C /home/namvule \
  .claude/.credentials.json \
  .claude/skills .claude/plugins .claude/agents .claude/backups \
  doc-parser

# Optional: Caddy SSL data (nếu dùng HTTPS với domain)
docker run --rm -v claude-container_caddy_data:/data -v /tmp:/backup \
  alpine tar czf /backup/caddy-data.tar.gz -C /data .
```

### B. Chuyển file

```bash
scp /tmp/claude-migrate.tar.gz /tmp/claude-host.tar.gz /tmp/caddy-data.tar.gz \
  user@new-server:/tmp/
```

### C. Trên server MỚI — restore

```bash
# 1. Cài Docker + docker compose (skip nếu đã có)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER && newgrp docker

# 2. Restore project
mkdir -p /home/namvule/claude-container
tar xzf /tmp/claude-migrate.tar.gz -C /home/namvule/claude-container

# 3. Restore host config
tar xzf /tmp/claude-host.tar.gz -C /home/namvule/

# 4. Optional: restore Caddy cert
docker volume create claude-container_caddy_data
docker run --rm -v claude-container_caddy_data:/data -v /tmp:/backup \
  alpine sh -c 'cd /data && tar xzf /backup/caddy-data.tar.gz'

# 5. Đổi DNS A record sang IP server mới (nếu có domain)

# 6. Build + start
cd /home/namvule/claude-container
docker compose build      # ~3-5 phút lần đầu (apt + npm)
docker compose up -d      # entrypoint bootstrap doc-parser venv ~2 phút

# 7. Verify
curl http://localhost:8080/api/v1/health
docker compose logs claude-code | tail -30
```

---

## Lưu ý quan trọng

1. **`API_KEY` trong `.env` là master key cho secret encryption**. Mendix PAT
   trong DB được mã hoá AES-256-GCM với key derive từ `API_KEY`. Nếu để key
   khác trên server mới → tất cả PAT cũ unreadable (login Mendix fail, phải
   re-enter PAT cho từng user).

2. **Auth tokens vẫn valid** sau migrate — token là random hex lưu plaintext
   trong DB, không phụ thuộc `API_KEY`. Users không cần login lại.

3. **Path `~/doc-parser` trong `docker-compose.yml` hardcoded
   `/home/namvule/doc-parser`**. Nếu user trên server mới khác name → sửa
   mount path trong `docker-compose.yml`
   (`- ~/doc-parser:/home/namvule/doc-parser:ro`).

4. **Caddy SSL**: nếu không backup `caddy_data`, Let's Encrypt sẽ issue cert
   mới ngay khi DNS resolved. Có rate limit (5 cert/tuần/domain) — chỉ là vấn
   đề nếu test migrate nhiều lần.

5. **Image size**: `node:24-trixie-slim` + apt deps + npm + Python deps cho
   doc-parser ~ 3–4 GB. Lần build đầu trên server mới hơi lâu.
