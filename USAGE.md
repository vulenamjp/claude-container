# Hướng dẫn sử dụng API

Backend HTTP đơn giản proxy prompt sang Claude Code CLI, hỗ trợ streaming, upload file kèm, lưu file Claude tạo ra vào SQLite + cho end-user download, và giữ ngữ cảnh hội thoại qua nhiều turn.

Base URL mặc định: `http://localhost:8080`

---

## 1. Setup

```bash
# Build image (lần đầu hoặc sau khi sửa code)
docker compose build

# Chạy server background
docker compose up -d

# Xem log
docker compose logs -f claude-code

# Tắt
docker compose down
```

Yêu cầu trước khi chạy:
- File credentials Claude: `~/.claude/.credentials.json` (mount read-only vào container)
- Đăng nhập Claude Code 1 lần trên host trước đó (`claude login`)

---

## 2. Endpoints

| Method | Path                                | Mục đích                                    |
|--------|-------------------------------------|---------------------------------------------|
| GET    | `/api/v1/health`                    | Health check                                |
| POST   | `/api/v1/chat/stream`               | Chat streaming (NDJSON)                     |
| POST   | `/api/v1/chat/sync`                 | Chat đồng bộ (trả 1 lần khi xong)          |
| GET    | `/api/v1/files/:id`                 | Download file Claude đã tạo                 |
| GET    | `/api/v1/sessions/:id/files`        | Liệt kê file của 1 session                  |

Cả `/chat/stream` và `/chat/sync` đều nhận `Content-Type`:
- `application/json` — chỉ prompt + session_id
- `multipart/form-data` — kèm file upload

---

## 3. Chat Stream

### Request

**JSON (không có file):**
```bash
curl -N -X POST http://localhost:8080/api/v1/chat/stream \
  -H 'Content-Type: application/json' \
  -d '{
    "prompt": "Tóm tắt React hooks trong 3 câu",
    "session_id": "OPTIONAL-uuid-từ-lần-trước"
  }'
```

**Multipart (có file đính kèm):**
```bash
curl -N -X POST http://localhost:8080/api/v1/chat/stream \
  -F 'prompt=Đọc file và tóm tắt nội dung' \
  -F 'session_id=optional-uuid' \
  -F 'files=@./report.pdf' \
  -F 'files=@./notes.md'
```

### Response (NDJSON — mỗi dòng 1 JSON object)

```jsonc
{"type":"system","message":"Starting new session...","session_id":"abc-123-...","resumed":false}
{"type":"system","message":"Received 2 file(s)","files":[{"name":"report.pdf","path":"/workspace/supportFiles/upload-.../report.pdf","size":12345}]}
{"type":"text","text":"Đang đọc file..."}
{"type":"text","text":"\n\nTóm tắt: ..."}
{"type":"file","id":"file-uuid","name":"summary.md","mime":"text/markdown","size":456,"sha256":"...","url":"/api/v1/files/file-uuid"}
{"type":"end","status":"success","session_id":"abc-123-..."}
```

Các loại event:
- `system` — thông báo trạng thái (start, resume, file nhận được)
- `text` — token text từ Claude (stream token-by-token)
- `file` — Claude vừa tạo/sửa 1 file, có sẵn URL download
- `end` — kết thúc (status: success/error)

### Client JS (fetch streaming)

```javascript
const res = await fetch('http://localhost:8080/api/v1/chat/stream', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ prompt: 'hello', session_id: cachedSessionId }),
});

const reader = res.body.getReader();
const decoder = new TextDecoder();
let buf = '';
while (true) {
  const { value, done } = await reader.read();
  if (done) break;
  buf += decoder.decode(value, { stream: true });
  let nl;
  while ((nl = buf.indexOf('\n')) !== -1) {
    const line = buf.slice(0, nl).trim();
    buf = buf.slice(nl + 1);
    if (!line) continue;
    const evt = JSON.parse(line);
    if (evt.type === 'system' && evt.session_id) cachedSessionId = evt.session_id;
    if (evt.type === 'text') ui.appendText(evt.text);
    if (evt.type === 'file') ui.addDownloadLink(evt.name, evt.url);
    if (evt.type === 'end') ui.markDone(evt.status);
  }
}
```

---

## 4. Chat Sync

Giống stream về input nhưng trả 1 JSON response duy nhất khi Claude làm xong.

```bash
curl -X POST http://localhost:8080/api/v1/chat/sync \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"Viết hàm Python tính fibonacci"}'
```

**Response:**
```json
{
  "status": "success",
  "session_id": "abc-123-...",
  "resumed": false,
  "full_response": "Đây là hàm fibonacci...\n```python\ndef fib(n):...\n```",
  "execution_time_ms": 4523,
  "attached_files": [],
  "created_files": [
    { "id": "...", "name": "fib.py", "mime": "text/plain", "size": 89, "url": "/api/v1/files/..." }
  ]
}
```

Dùng `/chat/sync` khi cần đợi kết quả cuối (vd: batch, automation script). Dùng `/chat/stream` cho UI live.

---

## 5. Giữ ngữ cảnh hội thoại (multi-turn)

Mỗi response có `session_id` — client cache lại, gửi kèm lần sau để Claude nhớ context:

```bash
# Turn 1: tạo session mới
$ curl ... -d '{"prompt":"Tôi tên Nam"}'
# → {"session_id":"abc-123-...","resumed":false, ...}

# Turn 2: gửi lại session_id
$ curl ... -d '{"prompt":"Tôi tên gì?","session_id":"abc-123-..."}'
# → {"resumed":true, ..., "full_response":"Bạn tên Nam"}
```

**Lưu ý:**
- Session lưu trong volume `~/.claude` của container. Reset volume → mất lịch sử.
- Nếu gửi `session_id` không tồn tại → claude exit error → response `status: error`. Client nên fallback bằng cách bỏ `session_id` và retry.
- `session_id` cũng đồng thời là khoá nhóm cho file đầu ra (xem mục 7).

---

## 6. Upload file đính kèm (input)

Dùng `multipart/form-data` với field `prompt` + 1 hoặc nhiều field `files`:

```bash
curl -X POST http://localhost:8080/api/v1/chat/stream \
  -F 'prompt=So sánh 2 file CSV này' \
  -F 'files=@./a.csv' \
  -F 'files=@./b.csv'
```

File được lưu vào `/workspace/supportFiles/upload-<timestamp>-<rand>/<sanitized-name>` và path được tự động chèn vào cuối prompt để Claude `Read`.

**Giới hạn** (override bằng env):
- `MAX_FILE_BYTES` — mỗi file, mặc định 50MB
- `MAX_TOTAL_BYTES` — tổng cộng, mặc định 200MB
- `MAX_FILES` — số file/request, mặc định 20

---

## 7. Download file Claude tạo ra (output)

Khi Claude dùng tool `Write`/`Edit`/`MultiEdit`/`NotebookEdit`, server tự copy file vào `/workspace/output/<session_id>/`, lưu metadata SQLite, và emit event `file` xuống stream.

**Download trực tiếp:**
```bash
curl -OJ http://localhost:8080/api/v1/files/<file-id>
# -OJ = lấy filename từ Content-Disposition
```

**Response headers:**
```
Content-Type: text/markdown
Content-Length: 456
Content-Disposition: attachment; filename="summary.md"
X-File-SHA256: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
```

**Trong browser:** chỉ cần link `<a href="/api/v1/files/<id>">Tải về</a>` — header `Content-Disposition: attachment` sẽ trigger download tự động.

**Liệt kê file của 1 session:**
```bash
curl http://localhost:8080/api/v1/sessions/<session-id>/files
```
```json
{
  "session_id": "abc-123-...",
  "files": [
    { "id": "...", "name": "summary.md", "mime": "text/markdown", "size": 456, "created_at": "...", "url": "/api/v1/files/..." }
  ]
}
```

Hữu ích cho UI "history" — load lại các file đã tạo trong 1 cuộc hội thoại cũ.

---

## 8. Health check

```bash
curl http://localhost:8080/api/v1/health
```
```json
{ "status": "online", "message": "Claude Code Backend is running", "timestamp": "2026-05-22T..." }
```

---

## 9. Biến môi trường

| Var                | Default                              | Mô tả                                   |
|--------------------|--------------------------------------|------------------------------------------|
| `PORT`             | `8080`                               | Cổng HTTP server                         |
| `CLAUDE_BIN`       | `claude`                             | Path tới claude CLI                      |
| `UPLOAD_DIR`       | `/workspace/supportFiles`            | Nơi lưu file upload từ client            |
| `OUTPUT_DIR`       | `/workspace/output`                  | Nơi copy file Claude tạo                 |
| `DB_PATH`          | `/workspace/.db/files.sqlite`        | SQLite metadata                          |
| `MAX_FILE_BYTES`   | `52428800` (50MB)                    | Giới hạn từng file upload                |
| `MAX_TOTAL_BYTES`  | `209715200` (200MB)                  | Giới hạn tổng dung lượng/request         |
| `MAX_FILES`        | `20`                                 | Số file tối đa mỗi request               |
| `LAIDA_PERMISSION_MODE` | `auto`                          | Permission mode cho claude (entrypoint)  |

---

## 10. Schema DB

```sql
CREATE TABLE files (
  id TEXT PRIMARY KEY,            -- UUID
  session_id TEXT NOT NULL,       -- gắn với session claude/DB
  original_path TEXT NOT NULL,    -- path Claude ghi (vd: /workspace/foo.md)
  stored_path TEXT NOT NULL,      -- bản copy bền vững (vd: /workspace/output/<sid>/foo.md)
  name TEXT NOT NULL,
  mime TEXT,
  size INTEGER NOT NULL,
  sha256 TEXT NOT NULL,           -- để dedup + verify
  created_at TEXT NOT NULL
);
CREATE INDEX idx_files_session ON files(session_id);
```

DB file trên host: `./workspace/.db/files.sqlite` (theo bind mount `.:/workspace`). Backup bằng cách copy file này + thư mục `output/`.

---

## 11. Mã lỗi thường gặp

| HTTP | Khi nào                                                        |
|------|----------------------------------------------------------------|
| 400  | Thiếu `prompt`, `session_id` sai format, multipart hỏng        |
| 404  | Endpoint không tồn tại, hoặc file id không có trong DB          |
| 410  | Row DB còn nhưng file vật lý bị xoá                             |
| 413  | Upload vượt `MAX_FILE_BYTES`/`MAX_TOTAL_BYTES`/`MAX_FILES`     |
| 500  | claude CLI exit non-zero (vd: --resume session không tồn tại)   |

---

## 12. Ví dụ full flow (multi-turn + file output)

```bash
# Turn 1: yêu cầu Claude viết script
RESP=$(curl -s -X POST http://localhost:8080/api/v1/chat/sync \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"Viết script bash đếm dòng trong thư mục hiện tại, lưu vào count.sh"}')

SID=$(echo "$RESP" | jq -r .session_id)
FILE_URL=$(echo "$RESP" | jq -r '.created_files[0].url')

# Tải file Claude vừa tạo về
curl -OJ "http://localhost:8080${FILE_URL}"

# Turn 2: nhờ Claude refactor — gửi lại session_id để giữ context
curl -X POST http://localhost:8080/api/v1/chat/sync \
  -H 'Content-Type: application/json' \
  -d "{\"prompt\":\"Thêm option -r để recursive vào script bạn vừa viết\",\"session_id\":\"$SID\"}"

# Liệt kê tất cả file của session
curl "http://localhost:8080/api/v1/sessions/${SID}/files" | jq
```
