#!/usr/bin/env bash
# ============================================================
#  ProxDash — HomeLab Dashboard LXC Installer
#  Auteur:  damiaan111
#  Licentie: MIT
#  Gebruik:  bash -c "$(curl -fsSL https://raw.githubusercontent.com/damiaan111/ProxDash/main/homelab-dashboard/main/ct/homelab-dashboard.sh)"
#  Vereist:  Proxmox VE 7+ host, root rechten
# ============================================================
set -euo pipefail

# ── Kleuren
YW=$(echo "\033[33m");  GN=$(echo "\033[1;92m"); RD=$(echo "\033[01;31m")
BL=$(echo "\033[36m");  CL=$(echo "\033[m");      BOLD=$(echo "\033[1m")

msg_info()  { echo -e " ${BL}[INFO]${CL}  $*"; }
msg_ok()    { echo -e " ${GN}[ OK ]${CL}  $*"; }
msg_error() { echo -e " ${RD}[ERR ]${CL}  $*" >&2; exit 1; }

clear
cat << "BANNER"

  ██████╗ ██████╗  ██████╗ ██╗  ██╗██████╗  █████╗ ███████╗██╗  ██╗
  ██╔══██╗██╔══██╗██╔═══██╗╚██╗██╔╝██╔══██╗██╔══██╗██╔════╝██║  ██║
  ██████╔╝██████╔╝██║   ██║ ╚███╔╝ ██║  ██║███████║███████╗███████║
  ██╔═══╝ ██╔══██╗██║   ██║ ██╔██╗ ██║  ██║██╔══██║╚════██║██╔══██║
  ██║     ██║  ██║╚██████╔╝██╔╝ ██╗██████╔╝██║  ██║███████║██║  ██║
  ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝

           HomeLab Dashboard — Proxmox LXC Installer v2.0
BANNER
echo ""

# ── Vereisten
[[ "$(id -u)" != "0" ]]          && msg_error "Draai dit script als root"
command -v pct &>/dev/null        || msg_error "Dit script vereist Proxmox VE (pct niet gevonden)"
command -v pveam &>/dev/null      || msg_error "pveam niet gevonden — is dit een Proxmox host?"

# ── Configuratie
CT_ID=$(pvesh get /cluster/nextid)
HOSTNAME="proxdash"
MEMORY=256
SWAP=256
DISK=2
CORES=1
OS_TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
STORAGE=$(pvesm status -content rootdir | awk 'NR>1 && $2=="active" {print $1; exit}')
BRIDGE="vmbr0"
PORT=7575
INSTALL_URL="https://raw.githubusercontent.com/damiaan111/ProxDash/main/homelab-dashboard/main/install/homelab-dashboard-install.sh"

[[ -z "$STORAGE" ]] && msg_error "Geen actieve storage gevonden — controleer pvesm status"

msg_info "Container ID  : ${BOLD}${CT_ID}${CL}"
msg_info "Hostname      : ${BOLD}${HOSTNAME}${CL}"
msg_info "Storage       : ${BOLD}${STORAGE}${CL}"
msg_info "RAM / Disk    : ${BOLD}${MEMORY}MB / ${DISK}GB${CL}"
echo ""

# ── Template
TEMPLATE_PATH="/var/lib/vz/template/cache/${OS_TEMPLATE}"
if [[ ! -f "$TEMPLATE_PATH" ]]; then
  msg_info "Debian 12 template downloaden..."
  pveam update >/dev/null 2>&1
  pveam download local "$OS_TEMPLATE" >/dev/null 2>&1 \
    || msg_error "Download mislukt — controleer: pveam available --section system"
  msg_ok "Template gedownload"
else
  msg_ok "Template al aanwezig"
fi

# ── Container aanmaken
msg_info "LXC container aanmaken..."
pct create "${CT_ID}" "local:vztmpl/${OS_TEMPLATE}" \
  --hostname  "${HOSTNAME}" \
  --memory    "${MEMORY}" \
  --swap      "${SWAP}" \
  --rootfs    "${STORAGE}:${DISK}" \
  --cores     "${CORES}" \
  --net0      "name=eth0,bridge=${BRIDGE},ip=dhcp" \
  --unprivileged 1 \
  --features  "nesting=1" \
  --start     1 \
  --onboot    1 \
  >/dev/null 2>&1
msg_ok "Container ${CT_ID} aangemaakt en gestart"

# ── Wacht op IP
msg_info "Wachten op netwerk..."
IP=""
for i in {1..20}; do
  IP=$(pct exec "${CT_ID}" -- hostname -I 2>/dev/null | awk '{print $1}' || true)
  [[ -n "$IP" ]] && break
  sleep 2
done
[[ -z "$IP" ]] && msg_error "Container kreeg geen IP — controleer DHCP op bridge ${BRIDGE}"
msg_ok "IP-adres: ${BOLD}${IP}${CL}"

# ── Installatie
msg_info "ProxDash installeren in container..."
pct exec "${CT_ID}" -- bash -c "$(curl -fsSL ${INSTALL_URL})"
msg_ok "Installatie voltooid"

# ── Klaar
echo ""
echo -e " ${GN}${BOLD}✅ ProxDash is succesvol geinstalleerd!${CL}"
echo -e " ${BL}🌐 Open in je browser:${CL}  ${GN}${BOLD}http://${IP}:${PORT}${CL}"
echo -e " ${YW}📦 Container ID: ${CT_ID} | Beheer via Proxmox GUI${CL}"
echo ""
