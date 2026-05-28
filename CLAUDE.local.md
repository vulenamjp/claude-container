# Project Notes

Add project-specific instructions for Claude Code here. This file persists
across sessions. /workspace/CLAUDE.md is auto-generated on every start — do
not edit it directly; edit this file instead.

## doc-parser MCP (in-container setup)

doc-parser là Python MCP server (Unstructured) cho phép parse PDF/DOCX/PPTX.
Đã được tích hợp vào container theo cách:

- Base image: `node:24-trixie-slim` (Debian 13, Python 3.13). KHÔNG dùng
  `node:24-slim` (bookworm, Python 3.11) — doc-parser yêu cầu Python >= 3.12.
- Source code mount RO từ host: `~/doc-parser:/home/namvule/doc-parser:ro`
- Venv build container-side ở `/opt/doc-parser-venv` (named volume
  `doc-parser-venv` — cache qua các lần restart)
- Bootstrap tự động trong `entrypoint.sh` step 3.5:
  - Rsync source ra `/tmp/doc-parser-src` (writable), exclude
    `*.egg-info`/`myenv`/`__pycache__` — vì mount RO + setuptools cố touch
    `src/*.egg-info/` sẽ fail
  - `python3 -m venv` + `pip install /tmp/doc-parser-src` (KHÔNG `-e`, sẽ fail
    do RO mount + setuptools egg_info step)
  - Lần đầu: ~2 phút (kéo transformers, torch, opencv, …)
  - Lần sau: skip vì binary đã có ở `/opt/doc-parser-venv/bin/python`
- `entrypoint.sh` bake `/workspace/.mcp.json` (project scope) trỏ vào container
  venv. Path này override `~/.claude.json` host-level (nếu có restore vào
  container) — vì path `/home/namvule/doc-parser/myenv/bin/python` của host
  KHÔNG dùng được trong container (symlink trỏ ra `/usr/bin/python3.12`).

### Build & run

```bash
docker compose build      # rebuild — layer apt invalidates lần đầu, sau đó cache
docker compose up -d      # entrypoint bootstrap venv lần đầu nếu volume empty
```

### Force rebuild venv

Khi update source doc-parser hoặc đổi Python deps:

```bash
docker volume rm claude-container_doc-parser-venv
docker compose up -d      # entrypoint sẽ tạo lại venv
```

### Disk footprint

OS deps thêm vào image khoảng ~200MB (tesseract + 3 languages + poppler-utils
+ libmagic1). Có thể trim:

- Bỏ `tesseract-ocr-vie` nếu không OCR tiếng Việt
- Bỏ `tesseract-ocr-jpn` nếu không OCR tiếng Nhật
- Giữ tối thiểu `tesseract-ocr` + `tesseract-ocr-eng` + `poppler-utils` +
  `libmagic1`

### Khi nào doc-parser KHÔNG hoạt động trong container

1. `~/doc-parser` chưa tồn tại trên host → entrypoint skip bootstrap (check
   `[ -d "/home/namvule/doc-parser/src" ]`).
2. `pip install` fail (mạng, conflict deps) → entrypoint log warning, MCP
   không lên. Check log: `docker compose logs claude-code | grep doc-parser`.
3. Volume `doc-parser-venv` được tạo từ trước với image cũ thiếu Python
   → cần `docker volume rm` rồi rebuild.
