const http     = require('http');
const net      = require('net');
const fs       = require('fs');
const path     = require('path');
const { URL }  = require('url');
const { exec } = require('child_process');

const APP_DIR    = '/opt/homelab-dashboard';
const HTML_FILE  = path.join(APP_DIR, 'index.html');
const STATE_FILE = path.join(APP_DIR, 'state.json');
const PORT       = parseInt(process.env.PORT || '7575', 10);
const MAX_BODY   = 200 * 1024; // 200 KB

const RAW_BASE = 'https://raw.githubusercontent.com/damiaan111/ProxDash/main/homelab-dashboard/main/app';

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

// TCP ping — geeft { status, latency } terug
function tcpPing(host, port) {
  return new Promise(resolve => {
    const sock  = new net.Socket();
    const start = Date.now();
    const done  = status => {
      sock.destroy();
      resolve({ status, latency: Date.now() - start });
    };
    sock.setTimeout(3000);
    sock.connect(port, host, () => done('online'));
    sock.on('error',   () => done('offline'));
    sock.on('timeout', () => done('offline'));
  });
}

// Eenvoudige HTTP GET helper voor update endpoint
function httpGet(url) {
  return new Promise((resolve, reject) => {
    const mod = url.startsWith('https') ? require('https') : require('http');
    mod.get(url, res => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => resolve(data));
    }).on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin',  req.headers.origin || '*');
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

  // GET /health — voor Uptime Kuma e.d.
  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', uptime: process.uptime() }));
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

  // GET /api/ping?url=... — server-side TCP check met latency
  if (req.method === 'GET' && req.url.startsWith('/api/ping')) {
    const qs     = new URL(req.url, 'http://localhost').searchParams;
    const rawUrl = qs.get('url');
    if (!rawUrl) { res.writeHead(400); res.end(JSON.stringify({ error: 'url ontbreekt' })); return; }
    try {
      const parsed  = new URL(rawUrl);
      const host    = parsed.hostname;
      const port    = parsed.port
        ? parseInt(parsed.port, 10)
        : (parsed.protocol === 'https:' ? 443 : 80);
      const result  = await tcpPing(host, port);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(result));
    } catch {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'offline', latency: null }));
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
        res.end(JSON.stringify({ error: 'Payload te groot' }));
        req.destroy(); return;
      }
      body += chunk;
    });
    req.on('end', () => {
      try {
        const data = JSON.parse(body);
        if (!data.categories || !data.services) throw new Error('Ongeldige structuur');
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

  // POST /api/update — download nieuwste index.html + server.js en herstart
  if (req.method === 'POST' && req.url === '/api/update') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, message: 'Update gestart, service herstart over ~3s' }));
    setTimeout(async () => {
      try {
        const html = await httpGet(`${RAW_BASE}/index.html`);
        const srv  = await httpGet(`${RAW_BASE}/server.js`);
        fs.writeFileSync(HTML_FILE, html, 'utf8');
        fs.writeFileSync(path.join(APP_DIR, 'server.js'), srv, 'utf8');
        htmlCache = null;
        exec('systemctl restart proxdash', () => {});
      } catch (e) {
        console.error('Update mislukt:', e.message);
      }
    }, 300);
    return;
  }

  res.writeHead(404); res.end('Not found');
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`ProxDash draait op http://0.0.0.0:${PORT}`);
  console.log(`State: ${STATE_FILE}`);
});
