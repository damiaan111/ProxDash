const http = require('http');
const net  = require('net');
const fs   = require('fs');
const path = require('path');
const { URL } = require('url');

const APP_DIR   = '/opt/homelab-dashboard';
const HTML_FILE = path.join(APP_DIR, 'index.html');
const STATE_FILE= path.join(APP_DIR, 'state.json');
const PORT      = parseInt(process.env.PORT || '7575', 10);
const MAX_BODY  = 100 * 1024;

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

// TCP ping: probeert verbinding op host:port, timeout 3 seconden
// Geeft 'online' als de TCP handshake lukt, anders 'offline'
function tcpPing(host, port) {
  return new Promise(resolve => {
    const sock = new net.Socket();
    const done = status => { sock.destroy(); resolve(status); };
    sock.setTimeout(3000);
    sock.connect(port, host, () => done('online'));
    sock.on('error', () => done('offline'));
    sock.on('timeout', () => done('offline'));
  });
}

const server = http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', req.headers.origin || '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Vary', 'Origin');
  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  // GET / — HTML
  if (req.method === 'GET' && req.url === '/') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(getHtml());
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

  // GET /api/ping?url=http://... — server-side TCP check
  if (req.method === 'GET' && req.url.startsWith('/api/ping')) {
    const qs = new URL(req.url, 'http://localhost').searchParams;
    const rawUrl = qs.get('url');
    if (!rawUrl) { res.writeHead(400); res.end(JSON.stringify({ error: 'url param ontbreekt' })); return; }
    try {
      const parsed = new URL(rawUrl);
      const host   = parsed.hostname;
      const port   = parsed.port
        ? parseInt(parsed.port, 10)
        : (parsed.protocol === 'https:' ? 443 : 80);
      const status = await tcpPing(host, port);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status }));
    } catch {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'offline' }));
    }
    return;
  }

  // POST /api/save
  if (req.method === 'POST' && req.url === '/api/save') {
    let body = '', size = 0;
    req.on('data', chunk => {
      size += chunk.length;
      if (size > MAX_BODY) {
        res.writeHead(413, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Payload te groot (max 100KB)' }));
        req.destroy(); return;
      }
      body += chunk;
    });
    req.on('end', () => {
      try {
        const data = JSON.parse(body);
        if (!data.categories || !data.services) throw new Error('Ongeldige state structuur');
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

  res.writeHead(404); res.end('Not found');
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`ProxDash draait op http://0.0.0.0:${PORT}`);
  console.log(`State bestand: ${STATE_FILE}`);
});
