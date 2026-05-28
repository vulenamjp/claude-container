# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A containerized harness for running Claude Code. The image installs `@anthropic-ai/claude-code` on top of `node:24-slim` and the entrypoint launches `claude` in stream-json mode against a bind-mounted workspace, using credentials and personalization (skills/plugins/agents) mounted from the host's `~/.claude`.

There are only three files here: `Dockerfile`, `entrypoint.sh`, `docker-compose.yml`. Most of the behavior lives in `entrypoint.sh`.

## Commands

Build and run with docker compose (the compose service is `claude-code`, container name `claude_code_env`):

```bash
docker compose build
docker compose run --rm claude-code            # interactive (stdin_open + tty are set in compose)
LAIDA_PERMISSION_MODE=plan docker compose run --rm claude-code   # override permission mode
```

`LAIDA_PERMISSION_MODE` accepts `auto` (default), `plan`, or `default`, and is passed straight to `claude --permission-mode`.

## Build-context files the Dockerfile expects

The Dockerfile `COPY`s two files that do not currently exist in this repo — `docker compose build` will fail until they are added next to the Dockerfile:

- `settings.json` → baked into the image at `/home/node/.claude/settings.json` (Dockerfile:37)
- `CLAUDE.md` → baked at `/home/node/CLAUDE.md.default`, used as the seed for the per-workspace `CLAUDE.md` on every start (Dockerfile:52, entrypoint.sh:60-68)

When editing the Dockerfile, keep in mind that `/workspace` is bind-mounted at runtime, so anything baked into that path in the image is hidden. That is why `CLAUDE.md` is baked to `/home/node/` and reassembled at start time instead.

## Runtime composition (entrypoint.sh)

The entrypoint runs as **root** first, then drops to the `node` user via `gosu` for the final `exec`. The order matters:

1. **Credentials gate** (entrypoint.sh:5-11). Hard-fails if `/home/node/.claude/.credentials.json` is not mounted. The host file is mounted read-only in `docker-compose.yml`.
2. **RO → RW copy for personalization** (entrypoint.sh:13-30). `~/.claude/{skills,plugins,agents}` are mounted from the host as `*-ro` (read-only), then copied into the writable `~/.claude/{skills,plugins,agents}` paths and `chown`ed to `node`. Shell scripts under `skills/` are made executable. Add new personalization categories here if you mount more.
3. **Config restore** (entrypoint.sh:32-39). If `~/.claude.json` is missing, the newest `~/.claude/backups/.claude.json.backup.*` is restored.
4. **Workspace seeding** (entrypoint.sh:45-55). `gosu node` creates `/workspace/{supportFiles,output}` and seeds `/workspace/CLAUDE.local.md` (only if absent) — this is the user-editable file that survives across sessions.
5. **CLAUDE.md regeneration** (entrypoint.sh:60-68). On every start, `/workspace/CLAUDE.md` is rewritten as `CLAUDE.md.default` + `---` + `CLAUDE.local.md`. **Never edit `/workspace/CLAUDE.md` — it is clobbered each run.** Edit `CLAUDE.local.md` (per-workspace, persists) or the baked `CLAUDE.md` in the build context (global default).
6. **Final exec** (entrypoint.sh:75-83). `gosu node claude --print --verbose --input-format stream-json --output-format stream-json --permission-mode "$PERM_MODE" --no-session-persistence --include-partial-messages --append-system-prompt …`. The appended system prompt forbids the agent from reading/disclosing the contents of `~/.claude/{skills,plugins,agents}` (invocation is still allowed). Preserve that clause when editing the exec line.

## Host mounts (docker-compose.yml)

- `.:/workspace` — the project being worked on.
- `~/.claude/.credentials.json` → `/home/node/.claude/.credentials.json:ro` — required.
- `~/.claude/{skills,plugins,agents,backups}` → corresponding `*-ro` paths inside the container — optional; consumed by the RO→RW copy step above.

When adding a new optional mount, mirror the `*-ro` naming and add a matching copy block in the entrypoint, otherwise `node` won't have write access and Claude Code won't see the files at the path it expects.

---

# Project Notes

Add project-specific instructions for Claude Code here. This file persists
across sessions. /workspace/CLAUDE.md is auto-generated on every start — do
not edit it directly; edit this file instead.

---

# Project Notes

Add project-specific instructions for Claude Code here. This file persists
across sessions. /workspace/CLAUDE.md is auto-generated on every start — do
not edit it directly; edit this file instead.

---

# Project Notes

Add project-specific instructions for Claude Code here. This file persists
across sessions. /workspace/CLAUDE.md is auto-generated on every start — do
not edit it directly; edit this file instead.

---

# Project Notes

Add project-specific instructions for Claude Code here. This file persists
across sessions. /workspace/CLAUDE.md is auto-generated on every start — do
not edit it directly; edit this file instead.

---

# Project Notes

Add project-specific instructions for Claude Code here. This file persists
across sessions. /workspace/CLAUDE.md is auto-generated on every start — do
not edit it directly; edit this file instead.

---

# Project Notes

Add project-specific instructions for Claude Code here. This file persists
across sessions. /workspace/CLAUDE.md is auto-generated on every start — do
not edit it directly; edit this file instead.

---

# Project Notes

Add project-specific instructions for Claude Code here. This file persists
across sessions. /workspace/CLAUDE.md is auto-generated on every start — do
not edit it directly; edit this file instead.

---

# Project Notes

Add project-specific instructions for Claude Code here. This file persists
across sessions. /workspace/CLAUDE.md is auto-generated on every start — do
not edit it directly; edit this file instead.

---

# Project Notes

Add project-specific instructions for Claude Code here. This file persists
across sessions. /workspace/CLAUDE.md is auto-generated on every start — do
not edit it directly; edit this file instead.

---

# Project Notes

Add project-specific instructions for Claude Code here. This file persists
across sessions. /workspace/CLAUDE.md is auto-generated on every start — do
not edit it directly; edit this file instead.

---

# Project Notes

Add project-specific instructions for Claude Code here. This file persists
across sessions. /workspace/CLAUDE.md is auto-generated on every start — do
not edit it directly; edit this file instead.

---

# Project Notes

Add project-specific instructions for Claude Code here. This file persists
across sessions. /workspace/CLAUDE.md is auto-generated on every start — do
not edit it directly; edit this file instead.
