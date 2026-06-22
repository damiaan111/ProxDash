const http = require('http');
const fs   = require('fs');
const path = require('path');

const APP_DIR   = '/opt/homelab-dashboard';
const HTML_FILE = path.join(APP_DIR, 'index.html');
const STATE_FILE= path.join(APP_DIR, 'state.json');
const PORT      = parseInt(process.env.PORT || '7575', 10);
const MAX_BODY  = 100 * 1024; // 100 KB limiet

// HTML eenmalig in memory cachen — alleen herladen na /api/save
let htmlCache = null;
function getHtml() {
  if (!htmlCache) htmlCache = fs.readFileSync(HTML_FILE, 'utf8');
  return htmlCache;
}

// State lezen
function readState() {
  try {
    return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
  } catch {
    return null;
  }
}

// State wegschrijven naar state.json (los van de HTML)
function writeState(data) {
  fs.writeFileSync(STATE_FILE, JSON.stringify(data, null, 2), 'utf8');
}

const server = http.createServer((req, res) => {
  // Geen wildcard CORS nodig op lokaal netwerk, maar geef expliciete origin terug
  const origin = req.headers.origin || '*';
  res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Vary', 'Origin');

  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  // ── GET / — geeft HTML terug (gecached)
  if (req.method === 'GET' && req.url === '/') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(getHtml());
    return;
  }

  // ── GET /api/state — geeft opgeslagen state terug als JSON
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

  // ── POST /api/save — sla state op in state.json
  if (req.method === 'POST' && req.url === '/api/save') {
    let body = '';
    let size = 0;
    req.on('data', chunk => {
      size += chunk.length;
      if (size > MAX_BODY) {
        res.writeHead(413, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Payload te groot (max 100KB)' }));
        req.destroy();
        return;
      }
      body += chunk;
    });
    req.on('end', () => {
      try {
        const data = JSON.parse(body);
        if (!data.categories || !data.services) throw new Error('Ongeldige state structuur');
        writeState(data);
        htmlCache = null; // reset cache zodat volgende GET verse HTML levert
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
