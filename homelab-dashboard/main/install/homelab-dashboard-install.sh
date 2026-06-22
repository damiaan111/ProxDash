#!/usr/bin/env bash
# ============================================================
#  ProxDash — Install script (draait BINNEN de LXC container)
#  Auteur:  damiaan111
#  Licentie: MIT
# ============================================================
set -euo pipefail

APP_DIR="/opt/homelab-dashboard"
PORT=7575
RAW_BASE="https://raw.githubusercontent.com/damiaan111/ProxDash/main/homelab-dashboard/main/app"

YW=$(echo "\033[33m"); GN=$(echo "\033[1;92m"); RD=$(echo "\033[01;31m")
BL=$(echo "\033[36m"); CL=$(echo "\033[m");     BOLD=$(echo "\033[1m")

msg_info()  { echo -e " ${BL}[INFO]${CL}  $*"; }
msg_ok()    { echo -e " ${GN}[ OK ]${CL}  $*"; }
msg_error() { echo -e " ${RD}[ERR ]${CL}  $*" >&2; exit 1; }

# ── Systeem updaten
msg_info "Systeem updaten..."
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq curl ca-certificates gnupg
msg_ok "Systeem bijgewerkt"

# ── Node.js 20.x
msg_info "Node.js 20.x installeren..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
apt-get install -y -qq nodejs >/dev/null 2>&1
msg_ok "Node.js $(node -v) geinstalleerd"

# ── App bestanden
msg_info "App bestanden ophalen..."
mkdir -p "$APP_DIR"
curl -fsSL "${RAW_BASE}/index.html" -o "${APP_DIR}/index.html"
curl -fsSL "${RAW_BASE}/server.js"  -o "${APP_DIR}/server.js"
msg_ok "Bestanden gedownload naar ${APP_DIR}"

# ── Systemd service
msg_info "Systemd service aanmaken..."
cat > /etc/systemd/system/proxdash.service << EOF
[Unit]
Description=ProxDash HomeLab Dashboard
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}
ExecStart=/usr/bin/node ${APP_DIR}/server.js
Restart=always
RestartSec=5
Environment=PORT=${PORT}
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable proxdash >/dev/null 2>&1
systemctl start proxdash
msg_ok "Service gestart"

# ── Verificatie
sleep 2
if systemctl is-active --quiet proxdash; then
  IP=$(hostname -I | awk '{print $1}')
  echo ""
  msg_ok "${BOLD}ProxDash draait op http://${IP}:${PORT}${CL}"
else
  msg_error "Service start mislukt — controleer: journalctl -u proxdash -n 30"
fi
