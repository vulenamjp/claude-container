# Tasks — Implement specs.md v2

Theo dõi việc thực thi checklist `specs.md §14` theo thứ tự PR đề xuất.

**Trạng thái:** `not started` | `working` | `done`

Mỗi PR khi hoàn thành sẽ có ghi chú **What was done** + commit/diff highlight.

---

## PR1 — CORS + Auth + Error envelope chuẩn hoá ✅

Mục tiêu: trước khi frontend tách rời gọi được, backend phải cho phép
cross-origin và xác thực bằng API key.

| # | Item | Status | Note |
|---|------|--------|------|
| 1.1 | Middleware CORS (đọc `ALLOWED_ORIGINS`, xử lý preflight `OPTIONS`) | done | `applyCorsHeaders()` + xử lý OPTIONS trả 204/403; echo `Origin` nếu match whitelist hoặc `*` nếu wildcard |
| 1.2 | Middleware auth (Bearer `API_KEY`, timing-safe, bỏ qua `/health`) | done | `checkAuth()` dùng `crypto.timingSafeEqual`; dev mode khi `API_KEY` không set |
| 1.3 | Chuẩn hoá error envelope: thêm field `code` machine-readable | done | `sendError()` helper; tất cả lỗi cũ đã đổi sang dùng kèm code (`unauthorized`, `forbidden`, `bad_request`, `not_found`, `gone`, `payload_too_large`, `claude_failed`, `internal_error`) |
| 1.4 | Bổ sung `auth_required` + `version` vào `/health` response | done | |

**What was done (PR1):**
- `server.js`: thêm consts `API_KEY`, `ALLOWED_ORIGINS`, `ALLOW_ALL_ORIGINS`, `SERVER_VERSION`.
- Thêm 3 helper: `sendError`, `applyCorsHeaders`, `checkAuth`.
- Echo `X-Client-Request-Id` (nếu hợp lệ).
- Main handler: CORS → OPTIONS → auth → route → handler.
- Cập nhật mọi `sendJson(res, 4xx/5xx, {status:error,...})` sang `sendError()` với `code`.
- Error trong NDJSON stream (`{type:end,status:error}`) cũng có thêm `code`.
- Log khởi động in trạng thái auth + CORS.

**Smoke test pass:**
- `GET /api/v1/health` (no auth) → 200 + `auth_required:true`
- `POST /chat/sync` thiếu header → 401 `unauthorized`
- `POST /chat/sync` Bearer sai → 403 `forbidden`
- `OPTIONS` từ allowed origin → 204 + đủ CORS headers
- `OPTIONS` từ disallowed origin → 403
- JSON sai cú pháp → 400 `bad_request`
- Thiếu `prompt` → 400 `bad_request`
- `session_id` sai format → 400 `bad_request`

---

## PR2 — Sessions table + history endpoints ✅

Mục tiêu: frontend có sidebar lịch sử chat.

| # | Item | Status | Note |
|---|------|--------|------|
| 2.1 | Bảng `sessions` trong SQLite + migration backfill từ `files` | done | `CREATE TABLE IF NOT EXISTS sessions(...)` + `INSERT OR IGNORE` backfill từ `files GROUP BY session_id` với title `(legacy session)` |
| 2.2 | Cập nhật `last_active_at`/`message_count` mỗi turn | done | `bumpSessionActivity()` gọi sau khi child claude exit 0 ở cả `/chat/stream` và `/chat/sync` |
| 2.3 | `GET /api/v1/sessions` (list, query `limit/offset/q`) | done | `listSessionsStmt` join file_count, sort `last_active_at DESC`; limit clamp 1..200 |
| 2.4 | `GET /api/v1/sessions/:id` (metadata + files) | done | Trả 404 nếu không tồn tại |
| 2.5 | `DELETE /api/v1/sessions/:id` (xoá output + DB rows) | done | Unlink từng file vật lý + `fs.rm -rf` thư mục `output/<sid>/` + xoá rows `files` + xoá row `sessions` |
| 2.6 | Title auto-gen từ `prompt` hoặc `title_hint` ở turn 1 | done | `deriveSessionTitle()`: ưu tiên `title_hint`, fallback 120 ký tự đầu của prompt; chỉ áp dụng khi tạo row mới |
| 2.7 | Header `X-Session-Id` trong response `/chat/stream` | done | Đưa vào `writeHead` của `/chat/stream` |

**What was done (PR2):**
- DB schema: thêm bảng `sessions` (id PK, title, created_at, last_active_at, message_count) + index `last_active_at DESC`.
- Migration backfill 1 lần từ bảng `files` cho data v1 cũ.
- 7 prepared statements mới: `getSession`, `insertSession`, `touchSession`, `listSessions`, `countSessions`, `deleteSession`, `deleteSessionFiles`, `listSessionFilesAll`.
- 3 helper: `deriveSessionTitle`, `ensureSessionRow`, `bumpSessionActivity`.
- `readRequestPayload` parse thêm `title_hint`.
- `handleStream` + `handleSync`: `ensureSessionRow` ở đầu, `bumpSessionActivity` khi success.
- 3 handler mới: `handleSessionsList`, `handleSessionGet`, `handleSessionDelete`.
- `matchRoute` thêm route `GET /sessions`, `GET /sessions/:id`, `DELETE /sessions/:id`.
- `handleStream` thêm `X-Session-Id` vào `writeHead`.
.

**Smoke test pass:**
- `GET /sessions` → list đúng order + file_count
- `?q=fibo` filter đúng
- `?limit=1&offset=1` pagination đúng
- `GET /sessions/:id` trả metadata + files
- `GET /sessions/nonexistent` → 404 `not_found`
- `DELETE /sessions/:id` → xoá file vật lý, dir, DB rows; trả counts

---

## PR3 — Tool-use events trong stream ✅

Mục tiêu: UI hiển thị "🔧 Reading file X" / "Bash..." live khi Claude
đang dùng tool.

| # | Item | Status | Note |
|---|------|--------|------|
| 3.1 | Emit event `{type:"tool_use", ...}` với summary an toàn | done | `extractToolEvents()` + `makeToolSummary()` cho Read/Write/Edit/Bash/Grep/Glob/WebFetch/WebSearch/TodoWrite/Task |
| 3.2 | Emit event `{type:"tool_result", ...}` (không kèm content) | done | Chỉ forward `tool_use_id` + `is_error`, KHÔNG kèm content (có thể to / chứa secret) |
| 3.3 | Sync API: tổng hợp `tool_calls[]` vào response | done | Map `pendingTools` để match use→result, tính `duration_ms` |

**What was done (PR3):**
- Helper `makeToolSummary(tool, input)`: tạo string UI-safe theo tool (basename file path, truncate command 80 ký tự...).
- Helper `sanitizeToolInput(input)`: chỉ forward string/number/boolean fields, truncate string ≥ 500 chars.
- Helper `extractToolEvents(evt)`: trả mảng events từ assistant/user content blocks.
- `handleStream`: emit từng tool event qua `write()`.
- `handleSync`: tích lũy `pendingTools` Map → ghép use+result thành `tool_calls[]` trong response.

**Bug fix kèm theo (foundational, ảnh hưởng cả PR1 trước nữa):**
- `splitLines()` so sánh `buffer[i] === '\n'` (Number vs String) → luôn false → mọi event từ stream-json của claude bị bỏ qua. Sửa thành `buffer[i] === 0x0a`. **Bug này có trong cả v1 — text/tool/file events thực ra chưa từng được emit đúng.** Sau fix, stream giờ phát đầy đủ.

**Smoke test pass (mock claude CLI):**
- Stream output: `system → text → tool_use(Read) → tool_result → tool_use(Bash) → tool_result(is_error:true) → text → end`
- Sync output: `tool_calls: [{tool:"Read",summary:"Reading foo.md",is_error:false,duration_ms:0}, {tool:"Bash",summary:"Running: ls -la /tmp/path",is_error:true,duration_ms:0}]`

---

## PR4 — Cancel endpoint ✅

Mục tiêu: nút "Stop generating" trên UI.

| # | Item | Status | Note |
|---|------|--------|------|
| 4.1 | `Map<session_id, ChildProcess>` cho streams đang active | done | `activeStreams` Map ở module-level, track cả `/chat/stream` và `/chat/sync` |
| 4.2 | `POST /api/v1/chat/cancel` (SIGTERM + emit `end:cancelled`) | done | `handleCancel`: tìm trong Map → set `streamCtx.cancelled=true` → `child.kill('SIGTERM')` → 200 với `cancelled:true/false` |
| 4.3 | Cleanup Map khi child close | done | `activeStreams.delete(sessionId)` ở cả `on('error')` và `on('close')` |

**What was done (PR4):**
- Module-level `activeStreams = new Map<sessionId, { child, ctx: { cancelled } }>`.
- `handleStream` + `handleSync` đăng ký entry sau spawn; xoá khi child kết thúc.
- `handleCancel`: validate `session_id`; nếu Map có → set flag + SIGTERM → trả `cancelled:true`; không có → trả `cancelled:false` (idempotent, không 404).
- Close handler check `streamCtx.cancelled`:
  - Stream: emit `{type:"end",status:"cancelled"}` thay vì error/success
  - Sync: trả 200 `{status:"cancelled", full_response: <partial>, tool_calls: <partial>}`
- Cancelled KHÔNG bump message_count (vì không phải turn completed).
- Route mới: `POST /api/v1/chat/cancel`.

**Smoke test pass (mock claude với `sleep 5`):**
- Stream chạy → curl cancel → response cancelled:true → stream client nhận `end:cancelled`
- Cancel session không tồn tại → 200 `cancelled:false`
- Cancel thiếu `session_id` → 400 `bad_request`

---

## PR5 — Inline file serving + signed URL ✅

Mục tiêu: ảnh / PDF hiển thị thẳng trong chat bubble, kể cả khi backend
yêu cầu `API_KEY` (vì `<img>` / `<iframe>` không gửi được header
`Authorization`).

| # | Item | Status | Note |
|---|------|--------|------|
| 5.1 | `GET /api/v1/files/:id?inline=1` đổi `Content-Disposition: inline` | done | Khi `?inline=1`: `Content-Disposition: inline; ...` + `Cache-Control: private, max-age=3600`. Mặc định vẫn `attachment` + `no-store` |
| 5.2 | Signed URL ngắn hạn cho download không cần header `Authorization` | done | HMAC-SHA256(token), endpoint `POST /api/v1/files/:id/sign` cấp, `GET /files/:id?token=&exp=&inline=` bypass auth khi token hợp lệ. Default expiry 1h, max 24h. Dev mode (không có `API_KEY`/`FILE_SIGN_SECRET`) → sign endpoint trả 400 |

**What was done (PR5 — final):**

**5.1 — Inline:**
- `handleFileDownload`: parse `?inline=1` qua `URL.searchParams`.
- `Content-Disposition: inline; ...` + `Cache-Control: private, max-age=3600` khi inline.
- Mặc định attachment + no-store.

**5.2 — Signed URL:**
- Env mới `FILE_SIGN_SECRET`. Nếu không set nhưng có `API_KEY` → derive `HMAC(API_KEY, "file-sign:v1")` làm secret. Nếu cả 2 đều không có → signing disabled.
- Helper `signFileToken(fileId, exp, inline)` → HMAC-SHA256 hex.
- Helper `verifyFileToken(fileId, params)` → check expiry, `crypto.timingSafeEqual` so sánh token.
- Handler `handleFileSign` cho `POST /api/v1/files/:id/sign`:
  - Body `{ inline?: boolean, expires_in?: number }`
  - Default `expires_in` = 3600s, max 86400s.
  - Trả `{ url, token, exp, inline, expires_in, expires_at }`.
- Main handler: nếu `GET /files/:id?token=...` → verify token; valid → bypass Bearer auth.
- Token sai/hết hạn vẫn trả lỗi với `code: forbidden` hoặc `bad_request` (không fallthrough sang "missing Authorization").
- Route mới: `POST /api/v1/files/:id/sign`.

**Smoke test pass (API_KEY=secretkey-abc):**
- `GET /files/:id` không header → 401 unauthorized
- `POST /files/:id/sign` không header → 401 unauthorized
- `POST /files/:id/sign` với Bearer → 200, trả URL có `token`, `exp`, `inline`, `expires_at`
- `GET <signed URL>` không Authorization header → 200 + body file, `Content-Disposition: inline`
- `GET <signed URL>` token bị sửa → 403 `forbidden` ("Invalid signed URL")
- `GET <signed URL>` `exp` quá khứ → 403 `forbidden` ("Signed URL expired")
- `POST /files/<id-không-tồn-tại>/sign` → 404 `not_found`
- Dev mode (không `API_KEY`) → sign endpoint 400 với message hướng dẫn set env

**Frontend pattern dùng signed URL cho ảnh:**
```javascript
// Khi gặp file event/created_files có mime image/* và backend có API_KEY:
async function getInlineUrl(fileId) {
  const res = await fetch(`${API}/api/v1/files/${fileId}/sign`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ inline: true, expires_in: 3600 }),
  });
  const { url } = await res.json();
  return API + url; // dùng cho <img src=...>
}
```

---

## PR6 — Rate limit (optional) ✅

Mục tiêu: chặn lạm dụng cho route `/chat/*`.

| # | Item | Status | Note |
|---|------|--------|------|
| 6.1 | In-memory rate limiter per-IP, `RATE_LIMIT_RPM` env, off khi = 0 | done | Sliding window 60s, `Map<ip, timestamps[]>`; default 60 rpm; setInterval cleanup mỗi phút |
| 6.2 | Response 429 `{code:"rate_limited"}` + header `Retry-After` | done | Header `Retry-After: <s>`, body có `retry_after_seconds` |

**What was done (PR6):**
- Env `RATE_LIMIT_RPM` (default 60, 0 = off).
- Helper `clientIp(req)`: ưu tiên `X-Forwarded-For[0]` (Caddy đặt), fallback `req.socket.remoteAddress`.
- Helper `checkRateLimit(ip)`: lọc timestamps trong cửa sổ 60s, tính `retry_after` từ timestamp cũ nhất.
- Áp dụng trước route dispatch CHỈ cho `/api/v1/chat/*` (health/sessions/files không bị limit).
- Cleanup interval (`.unref()` để không chặn process exit).

**Smoke test pass (RATE_LIMIT_RPM=3):**
- `/health` × 5 → 200 cả 5 (không bị limit)
- `/chat/sync` × 5: 200, 200, 200, 429, 429
- 429 response: `Retry-After: 60` + body `{"code":"rate_limited","retry_after_seconds":60}`
- `RATE_LIMIT_RPM=0`: tất cả 5 → 200 (off)
- Log khởi động in đúng setting

---

## Tổng tiến độ

- PR1: 4/4 ✅
- PR2: 7/7 ✅
- PR3: 3/3 ✅ (kèm bugfix splitLines từ v1)
- PR4: 3/3 ✅
- PR5: 2/2 ✅
- PR6: 2/2 ✅

**Total: 21/21** ✅

## Hoàn tất

Tất cả PR theo thứ tự đề xuất trong `specs.md §14` đã được hiện thực và
smoke test pass. Backend v2 sẵn sàng cho frontend chat UI tách rời gọi vào.

**Tóm tắt thay đổi `server.js`:**
- Config mới: `API_KEY`, `ALLOWED_ORIGINS`, `RATE_LIMIT_RPM`, `SERVER_VERSION`.
- 9 helper mới: `sendError`, `applyCorsHeaders`, `checkAuth`, `clientIp`,
  `checkRateLimit`, `deriveSessionTitle`, `ensureSessionRow`,
  `bumpSessionActivity`, `makeToolSummary`, `sanitizeToolInput`,
  `extractToolEvents`.
- Bảng `sessions` + 7 prepared statements mới + migration backfill.
- Module-level `activeStreams` Map cho cancel.
- 4 handler mới: `handleSessionsList`, `handleSessionGet`,
  `handleSessionDelete`, `handleCancel`.
- Bug fix `splitLines` (so sánh byte số thay vì chuỗi).
- Stream emit thêm `tool_use` / `tool_result` events; sync trả `tool_calls[]`.
- `X-Session-Id` header trong stream response.
- `?inline=1` cho file download.
- Health response: `auth_required`, `version`.

**Bước tiếp theo (ngoài scope):**
- 5.2 Signed URL ngắn hạn cho file (cho `<img>`/`<iframe>` không gửi
  được Authorization).
- PATCH session title.
- Per-user auth (JWT, owner per session).
- Endpoint xoá session log nội bộ của Claude CLI.
