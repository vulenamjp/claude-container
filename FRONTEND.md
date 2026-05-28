# Frontend Integration Guide

Hướng dẫn build chat UI **tách rời** gọi vào Claude Code Backend (v2).

> Spec API: xem [`specs.md`](./specs.md). File này tập trung vào **cách
> dùng** từ phía client — pattern, sample code, troubleshooting.

---

## 0. Kiến trúc giả định

```
┌────────────────────────────┐    HTTPS    ┌──────────────────────────┐
│ Frontend Chat UI           │ ─────────▶ │ Caddy (TLS)              │
│ (React/Vue/Svelte/vanilla) │            │ namvule....azure.com     │
│ origin ≠ backend           │ ◀───────── │     │                    │
│                            │            │     ▼                    │
│ - lưu API_KEY + sid ở      │            │ Node.js server.js        │
│   localStorage             │            │ (claude CLI subprocess)  │
└────────────────────────────┘            └──────────────────────────┘
```

- Frontend host bất kỳ đâu (Vercel, Netlify, S3+CloudFront, GitHub Pages, ...).
- Backend chỉ trả JSON / NDJSON; KHÔNG render UI.
- Mọi state thuộc về frontend (current session, lịch sử list, draft, …);
  backend chỉ lưu **lịch sử chat của Claude + file output**.

---

## 1. Setup phía backend (kiểm tra trước)

Trước khi viết frontend, đảm bảo backend đã bật:

```bash
# Trên máy đã có backend container:
docker compose up -d

# Kiểm tra:
curl https://your-backend-domain/api/v1/health
# → {"status":"online","auth_required":true,"version":"2.0.0",...}
```

Cấu hình env quan trọng (`docker-compose.yml` → `environment:`):

```yaml
environment:
  - API_KEY=<chuỗi-random-dài-32-ký-tự>          # bắt buộc cho prod
  - ALLOWED_ORIGINS=https://chat.example.com     # CSV, KHÔNG dùng *
  - RATE_LIMIT_RPM=60                             # tuỳ chọn
```

Sinh `API_KEY` đơn giản:
```bash
openssl rand -hex 32
```

> ⚠️ Production: **PHẢI** set `API_KEY` và **KHÔNG** để `ALLOWED_ORIGINS=*`.
> Wildcard origin biến API thành public proxy, ai cũng đốt token được.

---

## 2. Frontend config

`.env.local` (Vite/Next):
```bash
VITE_API_BASE=https://your-backend-domain
VITE_API_KEY=<chuỗi-API_KEY-y-hệt-backend>
```

> ⚠️ Vì là API key **dùng chung**, nó sẽ lộ trong bundle JS — bất kỳ ai mở
> DevTools đều thấy được. OK cho:
> - Demo nội bộ / staging
> - Backend đã có firewall IP allowlist
> - Khi cost của Claude do bạn chịu mọi cách
>
> Nếu cần **per-user auth** thật → đặt một middle-layer (API gateway riêng
> với JWT user) ở giữa frontend và backend này. Spec hiện tại chỉ hỗ trợ
> 1 shared key.

---

## 3. Client helper (vanilla JS, copy-paste được)

Một file `claude-client.js` ~150 dòng, đầy đủ chức năng. Đặt vào project,
import dùng.

```javascript
// claude-client.js
const BASE = import.meta.env?.VITE_API_BASE || 'http://localhost:8080';
const KEY  = import.meta.env?.VITE_API_KEY  || '';

const authHeader = () => (KEY ? { Authorization: `Bearer ${KEY}` } : {});

async function jsonFetch(path, opts = {}) {
  const res = await fetch(`${BASE}${path}`, {
    ...opts,
    headers: { ...authHeader(), 'Content-Type': 'application/json', ...opts.headers },
  });
  const ct = res.headers.get('content-type') || '';
  const body = ct.includes('json') ? await res.json() : await res.text();
  if (!res.ok) throw Object.assign(new Error(body.message || res.statusText), {
    status: res.status, code: body.code, body,
  });
  return body;
}

export const claudeClient = {
  health: () => jsonFetch('/api/v1/health'),

  // --- Streaming chat ---
  // onEvent(evt) được gọi cho từng NDJSON event.
  // Trả về { sessionId, status } khi stream kết thúc.
  async chatStream({ prompt, sessionId, titleHint, files }, onEvent, signal) {
    let body, headers = { ...authHeader() };
    if (files && files.length) {
      // multipart
      const fd = new FormData();
      fd.set('prompt', prompt);
      if (sessionId) fd.set('session_id', sessionId);
      if (titleHint) fd.set('title_hint', titleHint);
      for (const f of files) fd.append('files', f);
      body = fd;
      // KHÔNG set Content-Type cho FormData — browser tự thêm boundary
    } else {
      headers['Content-Type'] = 'application/json';
      body = JSON.stringify({ prompt, session_id: sessionId, title_hint: titleHint });
    }
    const res = await fetch(`${BASE}/api/v1/chat/stream`, { method: 'POST', headers, body, signal });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw Object.assign(new Error(err.message || res.statusText), { status: res.status, code: err.code });
    }
    const sid = res.headers.get('X-Session-Id') || sessionId;
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buf = '';
    let endStatus = 'unknown';
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buf += decoder.decode(value, { stream: true });
      let nl;
      while ((nl = buf.indexOf('\n')) !== -1) {
        const line = buf.slice(0, nl).trim();
        buf = buf.slice(nl + 1);
        if (!line) continue;
        let evt;
        try { evt = JSON.parse(line); } catch { continue; }
        if (evt.type === 'end') endStatus = evt.status;
        onEvent(evt);
      }
    }
    return { sessionId: sid, status: endStatus };
  },

  chatSync({ prompt, sessionId, titleHint }) {
    return jsonFetch('/api/v1/chat/sync', {
      method: 'POST',
      body: JSON.stringify({ prompt, session_id: sessionId, title_hint: titleHint }),
    });
  },

  cancel: (sessionId) => jsonFetch('/api/v1/chat/cancel', {
    method: 'POST', body: JSON.stringify({ session_id: sessionId }),
  }),

  // --- Sessions ---
  listSessions: ({ limit = 50, offset = 0, q = '' } = {}) => {
    const qs = new URLSearchParams({ limit, offset, ...(q ? { q } : {}) });
    return jsonFetch(`/api/v1/sessions?${qs}`);
  },
  getSession:    (id) => jsonFetch(`/api/v1/sessions/${id}`),
  deleteSession: (id) => jsonFetch(`/api/v1/sessions/${id}`, { method: 'DELETE' }),
  listSessionFiles: (id) => jsonFetch(`/api/v1/sessions/${id}/files`),

  // --- Files ---
  fileDownloadUrl: (id, { inline = false } = {}) =>
    `${BASE}/api/v1/files/${id}${inline ? '?inline=1' : ''}`,

  // Signed URL — cho <img>/<iframe> khi backend có API_KEY:
  signFileUrl: async (id, { inline = true, expiresIn = 3600 } = {}) => {
    const { url } = await jsonFetch(`/api/v1/files/${id}/sign`, {
      method: 'POST', body: JSON.stringify({ inline, expires_in: expiresIn }),
    });
    return `${BASE}${url}`;
  },
};
```

---

## 4. Session lifecycle

Backend nhớ context theo `session_id`. Frontend **bắt buộc** phải:

1. **Cache `session_id` của hội thoại đang mở** vào memory + (optional)
   `localStorage` để reload trang vẫn tiếp tục được.
2. **Gửi kèm `session_id` ở turn ≥ 2** để Claude nhớ ngữ cảnh.
3. **Bắt error `claude_failed`** khi resume — có thể session đã hết hạn,
   bị xoá, hoặc Claude CLI nội bộ không tìm thấy. Fallback: bỏ
   `session_id` và retry (sẽ tạo session mới).

### 4.1 Pattern khuyến nghị

```javascript
const STORE_KEY = 'currentSessionId';

function getCurrentSid() { return localStorage.getItem(STORE_KEY) || null; }
function setCurrentSid(sid) {
  if (sid) localStorage.setItem(STORE_KEY, sid);
  else localStorage.removeItem(STORE_KEY);
}

async function sendMessage(text) {
  let sid = getCurrentSid();
  try {
    const result = await claudeClient.chatStream(
      { prompt: text, sessionId: sid },
      onEvent,
    );
    setCurrentSid(result.sessionId);
  } catch (err) {
    if (err.code === 'claude_failed' && sid) {
      // session hỏng → retry không có sid
      setCurrentSid(null);
      return sendMessage(text);
    }
    throw err;
  }
}

function newConversation() { setCurrentSid(null); }
```

### 4.2 Lưu ý

- **Đừng tự sinh `session_id` ở turn 1.** Backend sẽ tự tạo UUID và trả
  về qua header `X-Session-Id` + trong event `{type:"system"}` đầu tiên.
- `session_id` phải match regex `[A-Za-z0-9_-]{8,128}` nếu bạn muốn tự
  chỉ định.
- 1 `session_id` tại 1 thời điểm chỉ có 1 stream chạy. Cố gắng gửi
  message thứ 2 khi turn trước chưa xong → cancel hoặc đợi.

---

## 5. Render từng loại event trong stream

NDJSON events:

```jsonc
{"type":"system","subtype":"session_start","session_id":"...","resumed":false}
{"type":"system","subtype":"files_received","files":[{...}]}
{"type":"text","text":"Đang đọc file..."}
{"type":"tool_use","id":"toolu_1","tool":"Read","summary":"Reading report.pdf","input":{...}}
{"type":"tool_result","tool_use_id":"toolu_1","is_error":false}
{"type":"file","id":"file-uuid","name":"summary.md","mime":"text/markdown","url":"/api/v1/files/..."}
{"type":"end","status":"success","session_id":"..."}
```

### 5.1 Handler skeleton

```javascript
function makeStreamHandler(ui) {
  let currentText = '';                       // assistant text đang build
  const toolChips = new Map();                // tool_use_id → DOM ref

  return (evt) => {
    switch (evt.type) {
      case 'system':
        if (evt.subtype === 'files_received') ui.showInfo(evt.message);
        break;

      case 'text':
        currentText += evt.text;
        ui.appendAssistantText(evt.text);
        break;

      case 'tool_use': {
        const chip = ui.addToolChip({ tool: evt.tool, summary: evt.summary, status: 'running' });
        toolChips.set(evt.id, chip);
        break;
      }

      case 'tool_result': {
        const chip = toolChips.get(evt.tool_use_id);
        if (chip) ui.updateToolChip(chip, { status: evt.is_error ? 'error' : 'done' });
        break;
      }

      case 'file':
        ui.addFileCard({ name: evt.name, mime: evt.mime, size: evt.size, url: evt.url, id: evt.id });
        break;

      case 'end':
        if (evt.status === 'success')   ui.markComplete();
        if (evt.status === 'cancelled') ui.markCancelled();
        if (evt.status === 'error')     ui.showError(evt.message || 'Stream error');
        break;

      default:
        // forward-compatible: bỏ qua event chưa biết
    }
  };
}
```

### 5.2 Render Markdown an toàn

`evt.text` là Markdown thô (Claude xuất ra `**bold**`, ` ```code``` `, …).
Đừng `innerHTML` trực tiếp. Dùng `marked` / `markdown-it` + DOMPurify:

```javascript
import { marked } from 'marked';
import DOMPurify from 'dompurify';

ui.appendAssistantText = (chunk) => {
  currentText += chunk;
  el.innerHTML = DOMPurify.sanitize(marked.parse(currentText));
};
```

---

## 6. Cancel ("Stop generating")

```javascript
let abortCtl = null;

async function startTurn(prompt) {
  abortCtl = new AbortController();
  try {
    await claudeClient.chatStream(
      { prompt, sessionId: getCurrentSid() },
      handler,
      abortCtl.signal,                    // truyền cho fetch
    );
  } catch (err) {
    if (err.name === 'AbortError') return;  // user bấm stop
    throw err;
  } finally {
    abortCtl = null;
  }
}

async function stopTurn() {
  const sid = getCurrentSid();
  if (!sid) return;
  // 1. Bảo backend SIGTERM child claude — trả về sớm cho UI mượt
  await claudeClient.cancel(sid).catch(() => {});
  // 2. Cắt kết nối fetch — fetch sẽ throw AbortError ở chỗ chờ
  if (abortCtl) abortCtl.abort();
}
```

> `claudeClient.cancel(sid)` **idempotent** — gọi nhiều lần cũng OK,
> trả về `cancelled: false` nếu không có stream active.

---

## 7. Multi-turn + sidebar history

```javascript
// Khi mở app: load list session, hiển thị sidebar
const { sessions } = await claudeClient.listSessions({ limit: 50 });
ui.renderSidebar(sessions);   // [{id, title, last_active_at, message_count, file_count}]

// User click 1 session → resume
async function openSession(id) {
  setCurrentSid(id);
  const { session } = await claudeClient.getSession(id);
  ui.setHeader(session.title);
  ui.renderFiles(session.files);     // file đã tạo trong session
  // Tin nhắn cũ KHÔNG có trong backend (Claude CLI nội bộ giữ, không
  // expose qua API hiện tại). Frontend tự nhớ qua localStorage nếu cần
  // re-render bubble cũ; hoặc chỉ hiện file output + cho user gõ tiếp.
}

// User bấm "Xoá":
async function deleteSession(id) {
  await claudeClient.deleteSession(id);   // xoá file output + DB row
  if (getCurrentSid() === id) setCurrentSid(null);
  ui.refreshSidebar();
}
```

### 7.1 Lưu ý quan trọng về "tin nhắn cũ"

Backend hiện chỉ lưu:
- Metadata session (id, title, counts, timestamps)
- File output Claude đã tạo
- (Nội bộ) Claude CLI giữ context để resume — nhưng KHÔNG expose
  history messages qua API.

Frontend muốn show lại bubble cũ trong session → **phải tự lưu** (vd.
IndexedDB keyed theo `session_id`). Đây là design choice: backend lo
state minimum, frontend lo render state.

---

## 8. Upload file kèm message

```javascript
// User chọn file từ <input type="file" multiple>:
function onSubmit(text, fileList /* File[] */) {
  return claudeClient.chatStream(
    {
      prompt: text,
      sessionId: getCurrentSid(),
      files: fileList,                  // mảng File từ <input>
    },
    handler,
  );
}
```

- Multipart tự được dùng khi có `files`.
- Server lưu file ở `/workspace/supportFiles/upload-<ts>-<rand>/` và
  CHÈN path vào cuối prompt → Claude tự `Read`.
- Giới hạn default: 50MB/file, 200MB/request, 20 file. Vượt → HTTP 413
  `payload_too_large`.

---

## 9. Hiển thị file output (ảnh / PDF / text)

```javascript
function renderFileCard(file) {
  const isImage = file.mime?.startsWith('image/');
  const isPdf   = file.mime === 'application/pdf';

  if (isImage) {
    // Cần signed URL vì <img> không gửi header Authorization
    claudeClient.signFileUrl(file.id, { inline: true }).then((url) => {
      imgEl.src = url;
    });
  } else if (isPdf) {
    claudeClient.signFileUrl(file.id, { inline: true }).then((url) => {
      iframeEl.src = url;
    });
  } else {
    // text/code/zip... → nút Download
    aEl.href = claudeClient.fileDownloadUrl(file.id);
    aEl.setAttribute('download', file.name);
    // ⚠️ Click vào <a href> sẽ KHÔNG gửi Bearer; cần đổi sang
    // window.open(signedUrl) hoặc fetch+blob nếu API_KEY bật.
  }
}

async function downloadFile(file) {
  // Cách an toàn nhất: fetch có header, blob, then trigger download
  const res = await fetch(`${BASE}/api/v1/files/${file.id}`, {
    headers: { Authorization: `Bearer ${KEY}` },
  });
  const blob = await res.blob();
  const blobUrl = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = blobUrl;
  a.download = file.name;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(blobUrl);
}
```

### Khi nào cần signed URL?

| Trường hợp                                  | Cách dùng                                   |
|---------------------------------------------|----------------------------------------------|
| `<img src=...>`, `<iframe src=...>`        | **signed URL** (vì không gửi được header)    |
| `<a href=...>` để download                 | Cũng phải signed URL (link sẽ mở mới, không header) |
| `fetch(...)` rồi xử lý blob                | Header `Authorization` bình thường — KHÔNG cần signed |

---

## 10. Error handling chuẩn

Mọi response lỗi có format:
```json
{ "status": "error", "code": "<machine>", "message": "<human>" }
```

Trong stream, lỗi tới qua event `{type:"end","status":"error","code":"...","message":"..."}`.

Code reference (xem `specs.md §10`):

| `code`                | Khi nào                                              | Frontend nên                                  |
|-----------------------|------------------------------------------------------|-----------------------------------------------|
| `unauthorized`        | Thiếu `Authorization`                                | Báo "API key chưa cấu hình", show settings    |
| `forbidden`           | API key sai / origin không trong allowlist / signed URL invalid | "Không có quyền". Không retry.   |
| `bad_request`         | Thiếu prompt, session_id sai format, JSON hỏng       | Hiển thị lỗi inline                           |
| `not_found`           | Session/file không tồn tại                           | Refresh sidebar, đề nghị tạo mới              |
| `gone`                | File DB còn nhưng disk mất                           | "File đã bị xoá khỏi server"                   |
| `payload_too_large`   | Upload quá to                                        | "File quá lớn (max 50MB)"                     |
| `rate_limited`        | Vượt RPM                                             | Đọc header `Retry-After`, disable nút N giây  |
| `claude_failed`       | Claude CLI exit ≠ 0                                  | Nếu resume session → retry không có `session_id` |
| `internal_error`      | Bug hoặc spawn fail                                  | Retry 1 lần, sau đó báo lỗi                   |

Wrapper:

```javascript
async function safeStream(opts, handler) {
  try {
    return await claudeClient.chatStream(opts, handler);
  } catch (err) {
    if (err.code === 'rate_limited') {
      const retry = err.body?.retry_after_seconds || 60;
      ui.showToast(`Quá nhanh, chờ ${retry}s`);
    } else if (err.code === 'unauthorized' || err.code === 'forbidden') {
      ui.showSettingsDialog();
    } else if (err.code === 'claude_failed' && opts.sessionId) {
      ui.showToast('Session lỗi, tạo mới...');
      return safeStream({ ...opts, sessionId: undefined }, handler);
    } else {
      ui.showError(err.message);
    }
    throw err;
  }
}
```

---

## 11. Troubleshooting

### 11.1 "CORS error" trong console

**Triệu chứng:** `Access to fetch at '...' from origin '...' has been blocked
by CORS policy: No 'Access-Control-Allow-Origin' header is present`

**Fix:**
1. Kiểm tra env `ALLOWED_ORIGINS` trên backend có chứa origin của frontend chưa.
2. Origin phải khớp **chính xác** (kể cả protocol). `https://chat.example.com`
   ≠ `http://chat.example.com` ≠ `https://chat.example.com:443`.
3. Bật wildcard `ALLOWED_ORIGINS=*` chỉ cho dev — không bao giờ prod.
4. Restart container sau khi đổi env.

### 11.2 "Mixed content"

**Triệu chứng:** Frontend trên HTTPS gọi backend HTTP → browser block.

**Fix:** dùng HTTPS cho backend. Caddy đã làm sẵn — chỉ cần trỏ DNS
đúng + mở cổng 80/443.

### 11.3 Streaming "đứng hình"

**Triệu chứng:** `fetch` resolve nhưng `reader.read()` không bao giờ trả.

**Nguyên nhân thường gặp:**
- Có proxy (Nginx/Cloudflare) buffer response → set `X-Accel-Buffering: no`
  hoặc tắt buffer ở proxy.
- Trình duyệt cũ không hỗ trợ ReadableStream → kiểm tra
  `'body' in Response.prototype`.

### 11.4 "Unauthorized" mặc dù có header

**Check:**
- Header đúng format: `Authorization: Bearer <KEY>` (có khoảng trắng,
  Bearer viết hoa B).
- `KEY` không có space thừa hoặc `\n` trailing (copy-paste hay dính).
- Backend có `API_KEY` set? Trong dev mode `auth_required:false` thì
  backend KHÔNG check.

### 11.5 Inline image không hiện

**Check:**
- Đã dùng signed URL chưa? `<img src="...?token=...&exp=...">`
- Token còn hạn? Backend trả 403 "Signed URL expired" sau TTL.
- Backend có signing không? Gọi `/health` xem `auth_required`. Nếu
  `true` mà sign endpoint 400 → set `FILE_SIGN_SECRET` env hoặc
  đảm bảo `API_KEY` đã set.

### 11.6 `claude_failed` ngay lập tức

**Nguyên nhân thường gặp:**
- Credentials Claude CLI hết hạn. SSH vào host, chạy `claude login`
  rồi restart container.
- Resume session_id không tồn tại trong `~/.claude` (vd. volume bị reset).
  Fix: bỏ `session_id` và retry.

### 11.7 Rate limit lỗi sớm

Header `Retry-After: <seconds>`. Frontend đọc và **disable** nút Send
trong khoảng thời gian đó:

```javascript
if (err.code === 'rate_limited') {
  const retry = parseInt(err.body.retry_after_seconds, 10);
  ui.disableSendFor(retry * 1000);
}
```

---

## 12. Checklist trước khi deploy frontend prod

- [ ] `API_KEY` backend set và **không** lộ trong git history.
- [ ] `ALLOWED_ORIGINS` không có `*`.
- [ ] HTTPS cho cả frontend lẫn backend.
- [ ] Header `Content-Security-Policy` cho frontend (đặc biệt nếu
      render Markdown).
- [ ] DOMPurify (hoặc tương đương) cho mọi output Markdown từ Claude.
- [ ] `localStorage` không lưu API key nếu app dùng chung nhiều user
      trên cùng máy.
- [ ] Disable nút Send khi đang stream để tránh user spam Enter.
- [ ] Bắt `AbortError` riêng khỏi error generic (đó là user cancel,
      không phải lỗi).
- [ ] Test kịch bản network drop giữa stream (mobile chuyển wifi → 4G).
- [ ] Test với prompt to hơn 100KB và file output to hơn 10MB.
- [ ] Bật retry tự động cho `claude_failed` khi đang resume.

---

## 13. Mẫu demo nhỏ (HTML + vanilla JS)

Một trang `demo.html` chạy được ngay với backend đã bật CORS cho
`http://localhost:5500` (Live Server VS Code, hay tương tự):

```html
<!doctype html>
<html>
<head><meta charset="utf-8"><title>Claude chat demo</title></head>
<body>
  <div id="log" style="white-space:pre-wrap;border:1px solid #ccc;padding:8px;max-height:60vh;overflow:auto"></div>
  <input id="input" style="width:80%" placeholder="Type a message">
  <button id="send">Send</button>
  <button id="stop">Stop</button>
  <button id="new">New chat</button>

  <script type="module">
    const BASE = 'https://your-backend-domain';
    const KEY  = 'paste-API_KEY-here';
    const log  = document.getElementById('log');
    let sid    = localStorage.getItem('sid') || null;
    let abort  = null;

    function append(t) { log.textContent += t; log.scrollTop = log.scrollHeight; }
    function line(t)  { append('\n' + t + '\n'); }

    async function send() {
      const prompt = document.getElementById('input').value.trim();
      if (!prompt) return;
      document.getElementById('input').value = '';
      line('USER: ' + prompt);
      append('CLAUDE: ');
      abort = new AbortController();
      try {
        const res = await fetch(`${BASE}/api/v1/chat/stream`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ prompt, session_id: sid }),
          signal: abort.signal,
        });
        if (!res.ok) throw new Error('HTTP ' + res.status);
        sid = res.headers.get('X-Session-Id') || sid;
        localStorage.setItem('sid', sid);
        const reader = res.body.getReader();
        const dec = new TextDecoder();
        let buf = '';
        while (true) {
          const { value, done } = await reader.read();
          if (done) break;
          buf += dec.decode(value, { stream: true });
          let nl;
          while ((nl = buf.indexOf('\n')) !== -1) {
            const ln = buf.slice(0, nl).trim();
            buf = buf.slice(nl + 1);
            if (!ln) continue;
            const evt = JSON.parse(ln);
            if (evt.type === 'text') append(evt.text);
            if (evt.type === 'tool_use') line(`[🔧 ${evt.summary}]`);
            if (evt.type === 'tool_result' && evt.is_error) line('[❌ tool error]');
            if (evt.type === 'file') line(`[📎 ${evt.name} → ${BASE}${evt.url}]`);
            if (evt.type === 'end') line(`--- ${evt.status} ---`);
          }
        }
      } catch (e) {
        if (e.name !== 'AbortError') line('ERROR: ' + e.message);
      } finally { abort = null; }
    }

    document.getElementById('send').onclick = send;
    document.getElementById('stop').onclick = async () => {
      if (sid) await fetch(`${BASE}/api/v1/chat/cancel`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ session_id: sid }),
      }).catch(()=>{});
      if (abort) abort.abort();
    };
    document.getElementById('new').onclick = () => {
      sid = null; localStorage.removeItem('sid'); log.textContent = '';
    };
    document.getElementById('input').addEventListener('keydown', e => {
      if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(); }
    });
  </script>
</body>
</html>
```

Lưu thành `demo.html`, thay `BASE` + `KEY`, mở bằng Live Server. Test
basic chat / cancel / new chat.

---

## 14. Tham khảo thêm

- [`specs.md`](./specs.md) — API contract đầy đủ.
- [`USAGE.md`](./USAGE.md) — hướng dẫn vận hành container (legacy nhưng
  còn đúng phần setup).
- [`tasks.md`](./tasks.md) — log những gì đã build trong v2.
