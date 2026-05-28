# Claude Code Backend — API Specification (v2)

> Hợp đồng API giữa **Backend Container** (Node.js HTTP server đóng gói trong
> docker-compose, proxy lên `claude` CLI) và **Frontend Chat UI** được phát
> triển/triển khai như một ứng dụng độc lập (khác origin: vd. Vercel, Netlify,
> static host).
>
> Spec này là phiên bản v2: bao trùm những gì `server.js` đang làm (giữ tương
> thích) cộng với các endpoint/sự kiện mới cần bổ sung trước khi frontend tách
> rời có thể vận hành tốt (list session, cancel, tool-use visibility, CORS,
> API key auth).

---

## 0. Kiến trúc tổng thể

```
┌──────────────────────────┐      HTTPS (CORS)       ┌──────────────────────────┐
│  Frontend Chat UI        │  ───────────────────▶   │  Caddy (TLS + proxy)     │
│  (origin ≠ backend)      │  ◀───────────────────   │  namvule....azure.com    │
│  - React/Next/Vue/...    │     NDJSON stream        │           │              │
│  - localStorage:         │                          │           ▼              │
│      • API key           │                          │  claude_code_env:8080    │
│      • current session   │                          │  (Node.js server.js)     │
│      • cached sessions   │                          │           │              │
└──────────────────────────┘                          │           ▼              │
                                                      │  spawn(claude --print    │
                                                      │       --stream-json ...) │
                                                      └──────────────────────────┘
```

- Backend KHÔNG render UI; chỉ trả JSON / NDJSON.
- State lâu dài (file output, metadata, session list) ở SQLite + filesystem
  trong volume container.
- Frontend là client thuần: tự lưu API key + `session_id` hiện hành ở
  `localStorage`, gọi REST + đọc NDJSON stream qua `fetch` streaming.

---

## 1. Cross-Origin & Authentication

### 1.1 CORS

Frontend host khác origin → backend BẮT BUỘC trả CORS headers cho **mọi**
response và xử lý preflight `OPTIONS`.

**Cấu hình qua env `ALLOWED_ORIGINS`** (CSV, mặc định `*` cho dev):

```
ALLOWED_ORIGINS=https://chat.example.com,https://chat-staging.example.com
```

**Response headers (áp dụng mọi route `/api/*`):**

| Header                              | Giá trị                                                   |
|-------------------------------------|-----------------------------------------------------------|
| `Access-Control-Allow-Origin`       | echo lại `Origin` nếu nằm trong allowlist, ngược lại 403  |
| `Access-Control-Allow-Methods`      | `GET, POST, DELETE, OPTIONS`                              |
| `Access-Control-Allow-Headers`      | `Authorization, Content-Type, X-Client-Request-Id`        |
| `Access-Control-Expose-Headers`     | `X-File-SHA256, X-Session-Id, Content-Disposition`        |
| `Access-Control-Max-Age`            | `600`                                                     |
| `Vary`                              | `Origin`                                                  |

**Preflight (`OPTIONS /api/...`):** trả 204, headers như trên, không body.

> ⚠️ KHÔNG dùng `Access-Control-Allow-Credentials: true` — auth qua Bearer
> token trong header, không qua cookie, nên không cần credentialed CORS
> (tránh cấm wildcard origin).

### 1.2 API key

Auth tĩnh, đơn giản đủ chặn lạm dụng public.

**Server đọc env `API_KEY`:**
- Nếu `API_KEY` không set → server chạy **chế độ open** (dev). Log cảnh báo.
- Nếu set → MỌI request tới `/api/v1/*` trừ `/api/v1/health` đều phải có:

```
Authorization: Bearer <API_KEY>
```

**Lỗi auth:**

| Trường hợp                                     | HTTP | Body                                                |
|-----------------------------------------------|------|-----------------------------------------------------|
| Thiếu header `Authorization`                   | 401  | `{"status":"error","code":"unauthorized","message":"Missing Authorization header"}` |
| Header sai format                              | 401  | `{"status":"error","code":"unauthorized","message":"Invalid Authorization scheme"}` |
| Bearer token không khớp `API_KEY`              | 403  | `{"status":"error","code":"forbidden","message":"Invalid API key"}` |

So sánh bằng `crypto.timingSafeEqual` để chống timing attack.

### 1.3 Request ID (khuyến nghị)

Frontend có thể gửi `X-Client-Request-Id: <uuid>` để dễ trace log. Server
echo lại cùng giá trị trong response header `X-Client-Request-Id` và log
mỗi request kèm ID này.

---

## 2. Bảng tóm tắt endpoint

| Method | Path                                       | Auth | Mô tả                                                  | Trạng thái   |
|--------|--------------------------------------------|:----:|--------------------------------------------------------|--------------|
| GET    | `/api/v1/health`                           |  ✗   | Health check                                           | đã có        |
| POST   | `/api/v1/chat/stream`                      |  ✓   | Chat streaming (NDJSON)                                | đã có        |
| POST   | `/api/v1/chat/sync`                        |  ✓   | Chat đồng bộ                                           | đã có        |
| POST   | `/api/v1/chat/cancel`                      |  ✓   | Huỷ stream đang chạy của 1 session                     | **mới**      |
| GET    | `/api/v1/sessions`                         |  ✓   | Liệt kê toàn bộ session để vẽ sidebar history          | **mới**      |
| GET    | `/api/v1/sessions/:id`                     |  ✓   | Metadata 1 session (title, counts, last activity)      | **mới**      |
| DELETE | `/api/v1/sessions/:id`                     |  ✓   | Xoá session + file output (không xoá log Claude nội bộ)| **mới**      |
| GET    | `/api/v1/sessions/:id/files`               |  ✓   | Liệt kê file output của 1 session                      | đã có        |
| GET    | `/api/v1/files/:id`                        |  ✓¹  | Download file Claude tạo (`?inline=1` để xem inline)   | đã có + flag |
| POST   | `/api/v1/files/:id/sign`                   |  ✓   | Cấp signed URL ngắn hạn (cho `<img>`/`<iframe>`)       | **mới**      |

¹ `GET /files/:id` chấp nhận **hoặc** Bearer token, **hoặc** signed URL
(`?token=&exp=&inline=`) — xem §9.3.

> **Đường dẫn legacy** trong `specs.md` cũ (`/api/chat/stream`, `/api/chat/sync`
> không có `/v1`) bị **bỏ**. Toàn bộ API ở dưới `/api/v1/`.

---

## 3. Common conventions

- **Encoding:** UTF-8 toàn bộ JSON.
- **Datetime:** ISO 8601 với timezone (vd. `2026-05-25T10:30:00.000Z`).
- **session_id:** chuỗi `[A-Za-z0-9_-]{8,128}`. Client tạo random hoặc dùng
  giá trị server gen ở turn 1.
- **file_id:** UUID v4.
- **Error envelope:** mọi response lỗi (HTTP ≥ 400) đều có format:
  ```json
  { "status": "error", "code": "<machine-readable>", "message": "<human>" }
  ```
- **Success envelope:** endpoint trả JSON thuần (không stream) có `status: "success"` ở top-level (ngoại trừ download nhị phân).

---

## 4. `GET /api/v1/health`

Không yêu cầu auth. Dùng cho load balancer / uptime check.

**Response 200:**
```json
{
  "status": "online",
  "message": "Claude Code Backend is running",
  "timestamp": "2026-05-25T10:30:00.000Z",
  "version": "2.0.0",
  "auth_required": true
}
```

`auth_required` cho frontend biết có cần API key hay không (tiện cho dev mode).

---

## 5. `POST /api/v1/chat/stream` — streaming NDJSON

### 5.1 Request

`Content-Type`: `application/json` HOẶC `multipart/form-data`.

**JSON body:**
```json
{
  "prompt": "Tóm tắt React hooks trong 3 câu",
  "session_id": "abc-123-...",     // optional, để resume
  "title_hint": "React hooks"      // optional, dùng cho turn đầu tiên để set title
}
```

**Multipart:** giữ nguyên cũ — field `prompt`, optional `session_id`,
`title_hint`, và 0..N field `files=@...`.

### 5.2 Response headers

```
HTTP/1.1 200 OK
Content-Type: application/x-ndjson; charset=utf-8
Transfer-Encoding: chunked
Cache-Control: no-cache, no-transform
X-Accel-Buffering: no
X-Session-Id: <session_id of this stream>
```

`X-Session-Id` được trả ngay trong header để frontend biết session_id mà
không phải đợi event `system` đầu tiên (nhỏ nhưng giúp simplify cancel
flow nếu client muốn cancel ngay).

### 5.3 NDJSON event schema

Mỗi dòng là 1 JSON object, kết thúc bằng `\n`. Frontend phải tolerant với
event chưa biết (forward-compatible).

#### 5.3.1 `system`
```json
{ "type": "system", "subtype": "session_start",
  "message": "Starting new session...",
  "session_id": "abc-123", "resumed": false, "ts": "2026-05-25T..." }
```
Subtypes: `session_start`, `session_resume`, `files_received`, `info`.

#### 5.3.2 `text` — token-by-token text
```json
{ "type": "text", "text": "Đang phân tích..." }
```
Frontend nối liên tiếp các `text.text` thành nội dung message.

#### 5.3.3 `tool_use` — **MỚI** (Claude bắt đầu dùng tool)
```json
{ "type": "tool_use", "id": "toolu_xxx",
  "tool": "Read", "summary": "Reading /workspace/supportFiles/report.pdf",
  "input": { "file_path": "/workspace/supportFiles/report.pdf" } }
```
- `tool` ∈ {`Read`, `Write`, `Edit`, `MultiEdit`, `NotebookEdit`, `Bash`,
  `Grep`, `Glob`, `WebFetch`, `WebSearch`, ...}.
- `summary` là string ngắn (đã được server render an toàn) cho UI hiển thị
  kiểu chip "🔧 Reading report.pdf".
- `input` có thể to — frontend có thể bỏ qua nếu không dùng.

#### 5.3.4 `tool_result` — **MỚI** (kết quả tool)
```json
{ "type": "tool_result", "tool_use_id": "toolu_xxx",
  "is_error": false, "duration_ms": 142 }
```
Không kèm content (có thể rất lớn). Frontend chỉ cần đánh dấu chip
"đã xong" hoặc đỏ nếu lỗi.

#### 5.3.5 `file` — Claude vừa tạo/sửa file (output)
```json
{ "type": "file", "id": "uuid", "name": "summary.md",
  "mime": "text/markdown", "size": 456, "sha256": "...",
  "url": "/api/v1/files/uuid" }
```
URL relative — frontend prepend `BACKEND_BASE_URL`.

#### 5.3.6 `end`
```json
{ "type": "end", "status": "success",
  "session_id": "abc-123",
  "stats": { "duration_ms": 4521, "tool_calls": 3, "tokens_out": 412 } }
```
Status: `success` | `error` | `cancelled`.

Khi `status: "error"` kèm field `message` và optional `exit_code`.

### 5.4 Cancel hành vi

- Client **đóng kết nối** TCP → backend SIGTERM child Claude → KHÔNG emit
  thêm event (vì client đã đi).
- Client gọi **POST `/api/v1/chat/cancel`** (xem §7) → backend SIGTERM
  child, emit 1 event cuối `{"type":"end","status":"cancelled"}` rồi đóng
  stream phía server.

### 5.5 Ví dụ client (fetch streaming + auth)

```javascript
const API = 'https://namvule.japaneast.cloudapp.azure.com';
const KEY = localStorage.getItem('apiKey');

async function chat(prompt, sessionId, onEvent, abortSignal) {
  const res = await fetch(`${API}/api/v1/chat/stream`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${KEY}`,
      'Content-Type': 'application/json',
      'X-Client-Request-Id': crypto.randomUUID(),
    },
    body: JSON.stringify({ prompt, session_id: sessionId }),
    signal: abortSignal,                          // để cancel
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);

  const sid = res.headers.get('X-Session-Id');
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
      if (line) onEvent(JSON.parse(line));
    }
  }
  return sid;
}
```

---

## 6. `POST /api/v1/chat/sync`

Giống §5 về input. Trả 1 JSON khi xong.

**Response 200:**
```json
{
  "status": "success",
  "session_id": "abc-123",
  "resumed": false,
  "full_response": "Đây là hàm fibonacci...\n```python\ndef fib(n):...\n```",
  "execution_time_ms": 4523,
  "attached_files": [],
  "created_files": [
    { "id": "...", "name": "fib.py", "mime": "text/plain",
      "size": 89, "url": "/api/v1/files/..." }
  ],
  "tool_calls": [
    { "tool": "Write", "summary": "Writing fib.py", "is_error": false }
  ]
}
```

`tool_calls` là phiên bản tổng hợp của các event `tool_use`/`tool_result`
ở stream — tiện cho client sync hiển thị timeline.

---

## 7. `POST /api/v1/chat/cancel` — **MỚI**

Huỷ stream đang chạy của 1 session.

**Request:**
```json
{ "session_id": "abc-123" }
```

**Response:**
| Trường hợp                                | HTTP | Body                                                          |
|-------------------------------------------|------|---------------------------------------------------------------|
| Có stream đang chạy, đã gửi SIGTERM       | 200  | `{"status":"success","cancelled":true,"session_id":"..."}`    |
| Không có stream nào đang chạy với sid này | 200  | `{"status":"success","cancelled":false,"session_id":"..."}`   |
| `session_id` sai format                   | 400  | `{"status":"error","code":"bad_request",...}`                 |

**Note implementation:** server giữ `Map<session_id, ChildProcess>` cho
streams đang active, xoá khi child close.

---

## 8. Session management — **MỚI**

### 8.1 `GET /api/v1/sessions`

Liệt kê tất cả session để vẽ sidebar history.

**Query params (tuỳ chọn):**
- `limit` (default 50, max 200)
- `offset` (default 0)
- `q` — filter theo title (substring, case-insensitive)

**Response 200:**
```json
{
  "status": "success",
  "total": 27,
  "sessions": [
    {
      "id": "abc-123",
      "title": "Tóm tắt React hooks trong 3 câu",
      "created_at": "2026-05-25T09:00:00Z",
      "last_active_at": "2026-05-25T09:12:30Z",
      "message_count": 4,
      "file_count": 2
    }
  ]
}
```

Sắp xếp theo `last_active_at DESC`.

### 8.2 `GET /api/v1/sessions/:id`

```json
{
  "status": "success",
  "session": {
    "id": "abc-123",
    "title": "Tóm tắt React hooks",
    "created_at": "...",
    "last_active_at": "...",
    "message_count": 4,
    "file_count": 2,
    "files": [ /* same shape as §9 */ ]
  }
}
```

### 8.3 `DELETE /api/v1/sessions/:id`

Xoá session record + thư mục `output/<sid>/` + DB rows của file.

> **Không** xoá session log nội bộ của Claude CLI (`~/.claude/...`). Lần
> sau frontend resume cùng `session_id` này → Claude vẫn có thể trả lời
> theo context cũ. Nếu cần xoá triệt để, gọi thêm `claude --remove-session`
> (chưa implement, ghi nhận ở §13).

**Response 200:**
```json
{ "status": "success", "deleted": { "session_id": "abc-123", "files": 2 } }
```

### 8.4 Title sinh tự động

Turn 1 của 1 session mới:
- Nếu request có `title_hint` → dùng làm title (cắt 120 ký tự).
- Ngược lại lấy 120 ký tự đầu của `prompt`, normalize whitespace.
- Frontend có thể PATCH title sau (chưa implement, xem §13).

---

## 9. File output

### 9.1 `GET /api/v1/sessions/:id/files`

Giữ nguyên như USAGE.md §7 hiện tại.

### 9.2 `GET /api/v1/files/:id`

Mở rộng với query `?inline=1` để hỗ trợ hiển thị inline (ảnh trong chat
bubble, PDF trong iframe...).

**Response headers (default):**
```
Content-Type: <mime>
Content-Length: <size>
Content-Disposition: attachment; filename="..."
X-File-SHA256: <sha256>
Cache-Control: private, max-age=3600
```

**Với `?inline=1`:**
```
Content-Disposition: inline; filename="..."
```

Cho phép `<img src="/api/v1/files/:id?inline=1">` hoặc
`<iframe src=".../files/:id?inline=1">`.

> ⚠️ Frontend cần gửi API key. Nhưng `<img>`/`<iframe>` không gửi được
> custom header. Giải pháp: dùng **signed URL ngắn hạn** — xem §9.3.

### 9.3 `POST /api/v1/files/:id/sign` — cấp signed URL

Yêu cầu Bearer auth bình thường. Trả về URL chứa HMAC token có hạn,
dùng cho `<img>`/`<iframe>` (không cần Authorization header).

**Request:**
```json
{ "inline": true, "expires_in": 3600 }
```
- `inline` (default `false`) — bake `inline=1` vào URL; download response sẽ trả `Content-Disposition: inline`.
- `expires_in` (default `3600`, max `86400`) — thời gian sống tính bằng giây.

**Response 200:**
```json
{
  "status": "success",
  "url": "/api/v1/files/<id>?token=<hex>&exp=<unix>&inline=1",
  "token": "<hex>",
  "exp": 1779700000,
  "inline": true,
  "expires_in": 3600,
  "expires_at": "2026-05-25T08:30:00.000Z"
}
```

Frontend chỉ cần `url` field; còn `token`/`exp`/`inline` cung cấp riêng
để client dễ debug hoặc cache.

**Lỗi:**
| Trường hợp                                       | HTTP | Code              |
|--------------------------------------------------|------|-------------------|
| File id không tồn tại                            | 404  | `not_found`       |
| Server không có `API_KEY` / `FILE_SIGN_SECRET`   | 400  | `bad_request`     |

**Verify ở backend (`GET /files/:id?token=&exp=&inline=`):**
- Nếu `exp` quá khứ → 403 `forbidden` "Signed URL expired".
- Nếu HMAC không khớp → 403 `forbidden` "Invalid signed URL".
- Nếu hợp lệ → bypass Bearer auth, trả file như download bình thường.

**Token format:**
- `signature = HMAC_SHA256(FILE_SIGN_SECRET, "${file_id}\n${exp}\n${inline_flag}")`
- `FILE_SIGN_SECRET` lấy từ env cùng tên, hoặc nếu không có thì derive
  `HMAC(API_KEY, "file-sign:v1")` để không cần thêm secret cho dev.
- So sánh bằng `crypto.timingSafeEqual`.

**Bảo mật:**
- Token chỉ valid cho 1 file_id + 1 exp + 1 inline flag → không reuse được.
- Nằm trong query string → có thể vào access log; vì vậy giữ TTL ngắn (1h default).
- Không signing được nếu `API_KEY` (hoặc `FILE_SIGN_SECRET`) chưa set.

---

## 10. Mã lỗi chuẩn

| `code` (machine)          | HTTP | Khi nào                                                  |
|---------------------------|------|----------------------------------------------------------|
| `unauthorized`            | 401  | Thiếu/sai format `Authorization`                         |
| `forbidden`               | 403  | Bearer không khớp `API_KEY`, hoặc origin không trong CORS whitelist |
| `bad_request`             | 400  | Thiếu `prompt`, `session_id` sai format, JSON hỏng       |
| `not_found`               | 404  | Endpoint sai, file_id không tồn tại, session_id không có |
| `gone`                    | 410  | DB row file còn nhưng file vật lý mất                    |
| `payload_too_large`       | 413  | Vượt `MAX_FILE_BYTES` / `MAX_TOTAL_BYTES` / `MAX_FILES`  |
| `rate_limited`            | 429  | Vượt giới hạn req/min (xem §13)                          |
| `internal_error`          | 500  | Lỗi không xác định                                       |
| `claude_failed`           | 502  | `claude` CLI exit ≠ 0 (sai session_id, login expire…)    |

Frontend nên fallback: gặp `claude_failed` khi resume → bỏ `session_id` và
retry để tạo session mới.

---

## 11. Biến môi trường (server)

Bổ sung so với USAGE.md hiện tại:

| Var                  | Default                              | Mô tả                                       |
|----------------------|--------------------------------------|---------------------------------------------|
| `PORT`               | `8080`                               | Cổng HTTP server                            |
| `CLAUDE_BIN`         | `claude`                             | Path tới claude CLI                         |
| `UPLOAD_DIR`         | `/workspace/supportFiles`            | Nơi lưu file upload                         |
| `OUTPUT_DIR`         | `/workspace/output`                  | Nơi copy file Claude tạo                    |
| `DB_PATH`            | `/workspace/.db/files.sqlite`        | SQLite metadata                             |
| `MAX_FILE_BYTES`     | `52428800` (50MB)                    | Mỗi file upload                             |
| `MAX_TOTAL_BYTES`    | `209715200` (200MB)                  | Tổng/request                                |
| `MAX_FILES`          | `20`                                 | Số file/request                             |
| **`API_KEY`**        | (unset = dev open)                   | Bearer token bắt buộc cho `/api/v1/*`       |
| **`ALLOWED_ORIGINS`**| `*`                                  | CSV whitelist CORS origin                   |
| **`RATE_LIMIT_RPM`** | `60`                                 | Req/min per IP (0 = off). Áp dụng `/chat/*` |
| **`FILE_SIGN_SECRET`**| derived từ `API_KEY`                | HMAC key cho signed URL. Nếu cả 2 đều không set → signing disabled |

---

## 12. SQLite schema (v2)

Giữ bảng `files` cũ + thêm bảng `sessions`:

```sql
CREATE TABLE IF NOT EXISTS sessions (
  id              TEXT PRIMARY KEY,           -- session_id của Claude CLI
  title           TEXT NOT NULL,              -- auto từ prompt đầu hoặc title_hint
  created_at      TEXT NOT NULL,
  last_active_at  TEXT NOT NULL,
  message_count   INTEGER NOT NULL DEFAULT 0  -- tăng mỗi /chat/stream|sync thành công
);
CREATE INDEX IF NOT EXISTS idx_sessions_last_active ON sessions(last_active_at DESC);

-- Bảng files giữ nguyên schema cũ; thêm FK logic ở app layer (SQLite
-- không bật FK mặc định) — KHÔNG bật ON DELETE CASCADE để tránh xoá nhầm.

CREATE TABLE IF NOT EXISTS files (
  id            TEXT PRIMARY KEY,
  session_id    TEXT NOT NULL,
  original_path TEXT NOT NULL,
  stored_path   TEXT NOT NULL,
  name          TEXT NOT NULL,
  mime          TEXT,
  size          INTEGER NOT NULL,
  sha256        TEXT NOT NULL,
  created_at    TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_files_session ON files(session_id);
```

**Migration từ v1:** với DB hiện có, chạy 1 lần lúc start server:
```sql
-- Tạo bảng sessions
CREATE TABLE IF NOT EXISTS sessions (...);

-- Backfill từ bảng files (mỗi distinct session_id thành 1 row)
INSERT OR IGNORE INTO sessions (id, title, created_at, last_active_at, message_count)
SELECT session_id, '(legacy session)', MIN(created_at), MAX(created_at), 0
FROM files
GROUP BY session_id;
```

---

## 13. Future work / chưa nằm trong v2

Ghi nhận để backlog — frontend không nên rely vào những thứ này:

- **PATCH `/api/v1/sessions/:id`** đổi title thủ công.
- **Endpoint xoá Claude session log nội bộ** (`~/.claude/...`) — Claude
  CLI hiện chưa có flag clean dễ dùng từ ngoài.
- **Server-Sent Events (SSE)** alternative cho `/chat/stream` (chỉ hoạt
  động khi prompt chuyển sang GET hoặc kèm hack — hiện NDJSON đủ tốt).
- **Streaming upload progress** từ multipart.
- **Webhook** khi session/file thay đổi (cho multi-client sync).
- **Per-user auth** (JWT, owner per session) — hiện chỉ 1 API key dùng chung.
- **Rate limit phức tạp hơn** (per-token, per-session, sliding window).

---

## 14. Checklist gap so với `server.js` hiện tại

Để hiện thực v2, các thay đổi cần làm trong `server.js`:

- [ ] Middleware CORS (đọc `ALLOWED_ORIGINS`, xử lý preflight).
- [ ] Middleware auth (đọc `API_KEY`, check `Authorization`, timing-safe).
- [ ] Thêm `X-Session-Id` vào response header của `/chat/stream`.
- [ ] Emit event `tool_use` và `tool_result` trong stream (đang có data
      nhưng bị filter; chỉ cần forward kèm summary an toàn).
- [ ] Map `session_id → ChildProcess` đang active + endpoint
      `/chat/cancel`.
- [ ] Bảng `sessions` + migration backfill từ `files`.
- [ ] Endpoints `GET /sessions`, `GET /sessions/:id`, `DELETE /sessions/:id`.
- [ ] Hỗ trợ `?inline=1` ở `/files/:id` + endpoint `POST /files/:id/sign` cấp signed URL ngắn hạn (HMAC-SHA256).
- [ ] Chuẩn hoá error envelope (thêm field `code`).
- [ ] Optional rate limiter `/chat/*` (bỏ qua nếu `RATE_LIMIT_RPM=0`).

Mỗi gạch đầu dòng độc lập, có thể PR riêng. Thứ tự đề xuất:
1. CORS + auth (bắt buộc trước khi frontend tách rời gọi được).
2. Bảng sessions + 3 endpoint session (sidebar history).
3. Tool-use events (UX live).
4. Cancel endpoint (UX "Stop generating").
5. `?inline=1` + signed URL (UX hiển thị ảnh).

---

## 15. Versioning

- Spec hiện tại: **v2.0.0**.
- Prefix path: `/api/v1/` được giữ nguyên (không bump path) — v2 chỉ là
  bump tài liệu/feature, **không có breaking change** so với v1 đối với
  các endpoint đã tồn tại trong `USAGE.md`.
- Khi nào breaking change: chuyển prefix sang `/api/v2/` và giữ `/api/v1/`
  song song tối thiểu 1 release.
