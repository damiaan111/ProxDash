const http = require('http');
const net  = require('net');
const fs   = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { URL } = require('url');

const APP_DIR   = '/opt/homelab-dashboard';
const HTML_FILE = path.join(APP_DIR, 'index.html');
const STATE_FILE= path.join(APP_DIR, 'state.json');
const PORT      = parseInt(process.env.PORT || '7575', 10);
const MAX_BODY  = 200 * 1024;

// Max 288 punten per service = 1 per 5 min over 24u
const HISTORY_MAX = 288;

let htmlCache = null;
function getHtml() {
  if (!htmlCache) htmlCache = fs.readFileSync(HTML_FILE, 'utf8');
  return htmlCache;
}

function readState() {
  try { return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8')); } catch { return null; }
}

function writeState(data) {
  fs.writeFileSync(STATE_FILE, JSON.stringify(data, null, 2), 'utf8');
}

// TCP ping — geeft { status, ms } terug
function tcpPing(host, port) {
  return new Promise(resolve => {
    const sock  = new net.Socket();
    const start = Date.now();
    const done  = status => { sock.destroy(); resolve({ status, ms: Date.now() - start }); };
    sock.setTimeout(3000);
    sock.connect(port, host, () => done('online'));
    sock.on('error',   () => done('offline'));
    sock.on('timeout', () => done('offline'));
  });
}

function appendHistory(state, serviceId, status, ms) {
  if (!state.history) state.history = {};
  if (!state.history[serviceId]) state.history[serviceId] = [];
  state.history[serviceId].push({ t: Date.now(), s: status === 'online' ? 1 : 0, ms: ms || 0 });
  if (state.history[serviceId].length > HISTORY_MAX)
    state.history[serviceId] = state.history[serviceId].slice(-HISTORY_MAX);
}

const server = http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin',  req.headers.origin || '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Vary', 'Origin');
  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  // GET /
  if (req.method === 'GET' && req.url === '/') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(getHtml());
    return;
  }

  // GET /health — voor Uptime Kuma e.d.
  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, uptime: Math.floor(process.uptime()), ts: Date.now() }));
    return;
  }

  // GET /api/state
  if (req.method === 'GET' && req.url === '/api/state') {
    const saved = readState();
    if (saved) {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(saved));
    } else {
      res.writeHead(204); res.end();
    }
    return;
  }

  // GET /api/ping?url=...&id=...
  if (req.method === 'GET' && req.url.startsWith('/api/ping')) {
    const qs     = new URL(req.url, 'http://localhost').searchParams;
    const rawUrl = qs.get('url');
    const sid    = qs.get('id');
    if (!rawUrl) { res.writeHead(400); res.end(JSON.stringify({ error: 'url param ontbreekt' })); return; }
    try {
      const parsed = new URL(rawUrl);
      const host   = parsed.hostname;
      const port   = parsed.port ? parseInt(parsed.port, 10) : (parsed.protocol === 'https:' ? 443 : 80);
      const result = await tcpPing(host, port);
      if (sid) {
        const state = readState();
        if (state) { appendHistory(state, sid, result.status, result.ms); writeState(state); }
      }
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(result));
    } catch {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'offline', ms: 0 }));
    }
    return;
  }

  // GET /api/history?id=...
  if (req.method === 'GET' && req.url.startsWith('/api/history')) {
    const qs    = new URL(req.url, 'http://localhost').searchParams;
    const sid   = qs.get('id');
    const state = readState();
    const hist  = state?.history?.[sid] || [];
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(hist));
    return;
  }

  // POST /api/save
  if (req.method === 'POST' && req.url === '/api/save') {
    let body = '', size = 0;
    req.on('data', chunk => {
      size += chunk.length;
      if (size > MAX_BODY) { res.writeHead(413); res.end(JSON.stringify({ error: 'Payload te groot' })); req.destroy(); return; }
      body += chunk;
    });
    req.on('end', () => {
      try {
        const data = JSON.parse(body);
        if (!data.categories || !data.services) throw new Error('Ongeldige state structuur');
        const existing = readState();
        if (existing?.history) data.history = existing.history;
        writeState(data);
        htmlCache = null;
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
      }
    });
    return;
  }

  // POST /api/update — download nieuwste bestanden van GitHub en herstart
  if (req.method === 'POST' && req.url === '/api/update') {
    const BASE = 'https://raw.githubusercontent.com/damiaan111/ProxDash/main/homelab-dashboard/main/app';
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, msg: 'Update gestart — dashboard herstart binnen enkele seconden.' }));
    setTimeout(() => {
      try {
        execSync(`curl -fsSL "${BASE}/server.js"  -o ${APP_DIR}/server.js`);
        execSync(`curl -fsSL "${BASE}/index.html" -o ${APP_DIR}/index.html`);
        execSync('systemctl restart proxdash');
      } catch (e) { console.error('Auto-update mislukt:', e.message); }
    }, 300);
    return;
  }

  res.writeHead(404); res.end('Not found');
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`ProxDash draait op http://0.0.0.0:${PORT}`);
  console.log(`State:         ${STATE_FILE}`);
  console.log(`Health check:  http://0.0.0.0:${PORT}/health`);
});
