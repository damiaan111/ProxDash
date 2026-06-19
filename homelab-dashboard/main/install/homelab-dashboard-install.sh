#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/homelab-dashboard"
PORT=7575

msg_info()  { echo -e "\e[1;34m[INFO]\e[0m  $*"; }
msg_ok()    { echo -e "\e[1;32m[ OK ]\e[0m  $*"; }
msg_error() { echo -e "\e[1;31m[ERR ]\e[0m  $*"; exit 1; }

# ── 1. Systeem updaten
msg_info "Systeem updaten..."
apt-get update -qq
apt-get install -y -qq curl ca-certificates gnupg
msg_ok "Systeem bijgewerkt"

# ── 2. Node.js 20.x installeren
msg_info "Node.js 20.x installeren..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
apt-get install -y -qq nodejs >/dev/null 2>&1
msg_ok "Node.js $(node -v) geinstalleerd"

# ── 3. App directory
msg_info "App directory aanmaken..."
mkdir -p "$APP_DIR"
msg_ok "Directory: $APP_DIR"

# ── 4. HTML dashboard ophalen
msg_info "Dashboard HTML ophalen..."
curl -fsSL "https://raw.githubusercontent.com/damiaan111/ProxDash/main/homelab-dashboard/main/app/index.html" \
  -o "$APP_DIR/index.html"
msg_ok "index.html geschreven"

# ── 5. Backend server ophalen
msg_info "Backend server ophalen..."
curl -fsSL "https://raw.githubusercontent.com/damiaan111/ProxDash/main/homelab-dashboard/main/app/server.js" \
  -o "$APP_DIR/server.js"
msg_ok "server.js geschreven"

# ── 6. Systemd service aanmaken
msg_info "Systemd service aanmaken..."
cat > /etc/systemd/system/homelab-dashboard.service << EOF
[Unit]
Description=HomeLab Dashboard
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/node $APP_DIR/server.js
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable homelab-dashboard >/dev/null 2>&1
systemctl start homelab-dashboard
msg_ok "Systemd service gestart"

# ── 7. Verificatie
sleep 2
if systemctl is-active --quiet homelab-dashboard; then
  IP=$(hostname -I | awk '{print $1}')
  msg_ok "HomeLab Dashboard draait op http://${IP}:${PORT}"
else
  msg_error "Service start mislukt — controleer: journalctl -u homelab-dashboard -n 30"
fi
