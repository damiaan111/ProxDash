const http = require('http');
const fs = require('fs');
const path = require('path');

const HTML_FILE = '/opt/homelab-dashboard/index.html';
const PORT = 7575;

function injectState(html, state) {
  // Vervang de DEFAULT_SERVICES en DEFAULT_CATEGORIES in de HTML met opgeslagen state
  const marker = '// __STATE_INJECT__';
  const inject = `// __STATE_INJECT__\nstate = ${JSON.stringify(state)};`;
  if (html.includes(marker)) {
    return html.replace(/\/\/ __STATE_INJECT__[\s\S]*?;/, inject);
  }
  // Voeg inject toe voor render()
  return html.replace('render();\nupdateClock();', inject + '\nrender();\nupdateClock();');
}

const server = http.createServer((req, res) => {
  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  if (req.method === 'GET' && req.url === '/') {
    const html = fs.readFileSync(HTML_FILE, 'utf8');
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
    return;
  }

  if (req.method === 'POST' && req.url === '/api/save') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      try {
        const state = JSON.parse(body);
        let html = fs.readFileSync(HTML_FILE, 'utf8');
        html = injectState(html, state);
        fs.writeFileSync(HTML_FILE, html, 'utf8');
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true }));
      } catch(e) {
        res.writeHead(500);
        res.end(JSON.stringify({ error: e.message }));
      }
    });
    return;
  }

  if (req.method === 'GET' && req.url === '/api/state') {
    try {
      const html = fs.readFileSync(HTML_FILE, 'utf8');
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true }));
    } catch(e) {
      res.writeHead(500); res.end('{}');
    }
    return;
  }

  res.writeHead(404); res.end('Not found');
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`HomeLab Dashboard draait op http://0.0.0.0:${PORT}`);
});
