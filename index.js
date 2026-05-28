const http = require('http');
const { spawn } = require('child_process');

const PORT = process.env.PORT || 8080;
const CLAUDE_BIN = process.env.CLAUDE_BIN || 'claude';

function sendJson(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(payload),
  });
  res.end(payload);
}

function readJsonBody(req, limitBytes = 1 * 1024 * 1024) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let total = 0;
    req.on('data', (chunk) => {
      total += chunk.length;
      if (total > limitBytes) {
        reject(Object.assign(new Error('Payload too large'), { statusCode: 413 }));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      const raw = Buffer.concat(chunks).toString('utf8');
      if (!raw) return resolve({});
      try {
        resolve(JSON.parse(raw));
      } catch (err) {
        reject(Object.assign(new Error('Invalid JSON body'), { statusCode: 400 }));
      }
    });
    req.on('error', reject);
  });
}

function spawnClaude(prompt, { stream }) {
  const args = ['--print', '--permission-mode', 'bypassPermissions'];
  if (stream) {
    args.push('--output-format', 'stream-json', '--verbose', '--include-partial-messages');
  } else {
    args.push('--output-format', 'text');
  }
  args.push(prompt);
  return spawn(CLAUDE_BIN, args, { stdio: ['ignore', 'pipe', 'pipe'] });
}

function splitLines(buffer, onLine) {
  let start = 0;
  for (let i = 0; i < buffer.length; i++) {
    if (buffer[i] === '\n') {
      onLine(buffer.slice(start, i));
      start = i + 1;
    }
  }
  return buffer.slice(start);
}

function extractText(evt) {
  if (!evt || typeof evt !== 'object') return null;
  if (evt.type === 'assistant' && evt.message && Array.isArray(evt.message.content)) {
    return evt.message.content
      .filter((c) => c && c.type === 'text' && typeof c.text === 'string')
      .map((c) => c.text)
      .join('') || null;
  }
  if (evt.type === 'stream_event' && evt.event) {
    const e = evt.event;
    if (e.type === 'content_block_delta' && e.delta && e.delta.type === 'text_delta') {
      return e.delta.text || null;
    }
  }
  return null;
}

async function handleHealth(req, res) {
  sendJson(res, 200, {
    status: 'online',
    message: 'Claude Code Backend is running',
    timestamp: new Date().toISOString(),
  });
}

async function handleStream(req, res) {
  let body;
  try {
    body = await readJsonBody(req);
  } catch (err) {
    return sendJson(res, err.statusCode || 400, { status: 'error', message: err.message });
  }
  const prompt = body && typeof body.prompt === 'string' ? body.prompt.trim() : '';
  if (!prompt) {
    return sendJson(res, 400, { status: 'error', message: 'Field "prompt" is required' });
  }

  res.writeHead(200, {
    'Content-Type': 'application/x-ndjson',
    'Transfer-Encoding': 'chunked',
    'Cache-Control': 'no-cache, no-transform',
    'X-Accel-Buffering': 'no',
  });

  const write = (obj) => res.write(JSON.stringify(obj) + '\n');
  write({ type: 'system', message: 'Starting process...' });

  const child = spawnClaude(prompt, { stream: true });
  let stdoutBuf = Buffer.alloc(0);
  let stderrBuf = '';
  let clientGone = false;

  req.on('close', () => {
    if (!res.writableEnded) {
      clientGone = true;
      child.kill('SIGTERM');
    }
  });

  child.stdout.on('data', (chunk) => {
    stdoutBuf = Buffer.concat([stdoutBuf, chunk]);
    stdoutBuf = splitLines(stdoutBuf, (lineBuf) => {
      const line = lineBuf.toString('utf8').trim();
      if (!line) return;
      let evt;
      try {
        evt = JSON.parse(line);
      } catch {
        return;
      }
      const text = extractText(evt);
      if (text) write({ type: 'text', text });
    });
  });

  child.stderr.on('data', (chunk) => {
    stderrBuf += chunk.toString('utf8');
  });

  child.on('error', (err) => {
    if (clientGone) return;
    write({ type: 'end', status: 'error', message: `Failed to spawn claude: ${err.message}` });
    res.end();
  });

  child.on('close', (code) => {
    if (clientGone || res.writableEnded) return;
    if (code === 0) {
      write({ type: 'end', status: 'success' });
    } else {
      write({
        type: 'end',
        status: 'error',
        exit_code: code,
        message: stderrBuf.trim() || `claude exited with code ${code}`,
      });
    }
    res.end();
  });
}

async function handleSync(req, res) {
  let body;
  try {
    body = await readJsonBody(req);
  } catch (err) {
    return sendJson(res, err.statusCode || 400, { status: 'error', message: err.message });
  }
  const prompt = body && typeof body.prompt === 'string' ? body.prompt.trim() : '';
  if (!prompt) {
    return sendJson(res, 400, { status: 'error', message: 'Field "prompt" is required' });
  }

  const startedAt = Date.now();
  const child = spawnClaude(prompt, { stream: false });
  const stdoutChunks = [];
  const stderrChunks = [];

  req.on('close', () => {
    if (!res.writableEnded) child.kill('SIGTERM');
  });

  child.stdout.on('data', (c) => stdoutChunks.push(c));
  child.stderr.on('data', (c) => stderrChunks.push(c));

  child.on('error', (err) => {
    sendJson(res, 500, { status: 'error', message: `Failed to spawn claude: ${err.message}` });
  });

  child.on('close', (code) => {
    const execution_time_ms = Date.now() - startedAt;
    if (code === 0) {
      sendJson(res, 200, {
        status: 'success',
        full_response: Buffer.concat(stdoutChunks).toString('utf8').replace(/\n+$/, ''),
        execution_time_ms,
      });
    } else {
      sendJson(res, 500, {
        status: 'error',
        exit_code: code,
        message: Buffer.concat(stderrChunks).toString('utf8').trim() || `claude exited with code ${code}`,
        execution_time_ms,
      });
    }
  });
}

const routes = [
  { method: 'GET', path: '/api/v1/health', handler: handleHealth },
  { method: 'POST', path: '/api/chat/stream', handler: handleStream },
  { method: 'POST', path: '/api/chat/sync', handler: handleSync },
];

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const route = routes.find((r) => r.method === req.method && r.path === url.pathname);
  if (!route) {
    return sendJson(res, 404, { status: 'error', message: 'Not found' });
  }
  try {
    await route.handler(req, res);
  } catch (err) {
    if (!res.headersSent) {
      sendJson(res, 500, { status: 'error', message: err.message || 'Internal error' });
    } else if (!res.writableEnded) {
      res.end();
    }
  }
});

server.listen(PORT, () => {
  console.log(`Claude Code Backend listening on http://0.0.0.0:${PORT}`);
});

const shutdown = (signal) => {
  console.log(`Received ${signal}, shutting down...`);
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 5000).unref();
};
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
