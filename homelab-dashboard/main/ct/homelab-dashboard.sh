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
DIM=$(echo "\033[2m")

msg_info()  { echo -e " ${BL}[INFO]${CL}  $*"; }
msg_ok()    { echo -e " ${GN}[ OK ]${CL}  $*"; }
msg_error() { echo -e " ${RD}[ERR ]${CL}  $*" >&2; exit 1; }

# Vraag met standaardwaarde: ask "Vraag" "standaard" -> geeft invoer of standaard terug
ask() {
  local prompt="$1" default="$2" input
  echo -en " ${YW}▶${CL}  ${BOLD}${prompt}${CL} ${DIM}[${default}]${CL}: "
  read -r input
  echo "${input:-$default}"
}

# Ja/nee vraag: confirm "Vraag" -> 0=ja, 1=nee
confirm() {
  local prompt="$1" input
  echo -en " ${YW}▶${CL}  ${BOLD}${prompt}${CL} ${DIM}[j/N]${CL}: "
  read -r input
  [[ "${input,,}" =~ ^(j|ja|y|yes)$ ]]
}

clear
cat << "BANNER"

  ██████╗ ██████╗  ██████╗ ██╗  ██╗██████╗  █████╗ ███████╗██╗  ██╗
  ██╔══██╗██╔══██╗██╔═══██╗╚██╗██╔╝██╔══██╗██╔══██╗██╔════╝██║  ██║
  ██████╔╝██████╔╝██║   ██║ ╚███╔╝ ██║  ██║███████║██████╗███████║
  ██╔═══╝ ██╔══██╗██║   ██║ ██╔██╗ ██║  ██║██╔══██║╚════██║██╔══██║
  ██║     ██║  ██║╚██████╔╝██╔╝ ██╗██████╔╝██║  ██║███████║██║  ██║
  ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝

           HomeLab Dashboard — Proxmox LXC Installer v2.1
BANNER
echo ""

# ── Vereisten
[[ "$(id -u)" != "0" ]] && msg_error "Draai dit script als root"
command -v pct   &>/dev/null || msg_error "pct niet gevonden — is dit een Proxmox host?"
command -v pvesm &>/dev/null || msg_error "pvesm niet gevonden — is dit een Proxmox host?"

# ── Detecteer beschikbare storage pools (alle actieve)
mapfile -t STORAGE_LIST < <(pvesm status | awk 'NR>1 && $3=="active" {print $1}')
[[ ${#STORAGE_LIST[@]} -eq 0 ]] && msg_error "Geen actieve storage gevonden — controleer: pvesm status"

# Gebruik 'local-lvm' als default als die bestaat, anders de eerste actieve
DEFAULT_STORAGE="${STORAGE_LIST[0]}"
for s in "${STORAGE_LIST[@]}"; do
  [[ "$s" == "local-lvm" ]] && DEFAULT_STORAGE="local-lvm" && break
done

# ── Detecteer bridges
mapfile -t BRIDGE_LIST < <(ip link show | awk -F': ' '/^[0-9]+: vmbr/{print $2}')
DEFAULT_BRIDGE="${BRIDGE_LIST[0]:-vmbr0}"

# ── Setup wizard
echo -e " ${BOLD}Configureer je container — druk Enter om de standaardwaarde te gebruiken${CL}"
echo -e " ${DIM}──────────────────────────────────────────────────${CL}"
echo ""

DEFAULT_CT_ID=$(pvesh get /cluster/nextid 2>/dev/null || echo "200")

CT_ID=$(ask   "Container ID"          "$DEFAULT_CT_ID")
HOSTNAME=$(ask "Hostname"              "proxdash")

# Storage kiezen
echo -e " ${DIM}Beschikbare storage: ${STORAGE_LIST[*]}${CL}"
STORAGE=$(ask  "Storage pool"          "$DEFAULT_STORAGE")

# Valideer storage keuze
VALID_STORAGE=false
for s in "${STORAGE_LIST[@]}"; do [[ "$s" == "$STORAGE" ]] && VALID_STORAGE=true && break; done
[[ "$VALID_STORAGE" == false ]] && msg_error "Storage '${STORAGE}' niet gevonden. Kies uit: ${STORAGE_LIST[*]}"

DISK=$(ask     "Disk grootte (GB)"     "4")
MEMORY=$(ask   "RAM (MB)"             "256")
SWAP=$(ask     "Swap (MB)"            "256")
CORES=$(ask    "CPU cores"            "1")

# Bridge kiezen
[[ ${#BRIDGE_LIST[@]} -gt 0 ]] && echo -e " ${DIM}Gevonden bridges: ${BRIDGE_LIST[*]}${CL}"
BRIDGE=$(ask   "Netwerk bridge"       "$DEFAULT_BRIDGE")

# IP configuratie
echo ""
if confirm "Statisch IP instellen? (anders DHCP)"; then
  IP_ADDR=$(ask "IP-adres (CIDR, bijv. 192.168.1.50/24)" "")
  GATEWAY=$(ask "Gateway (bijv. 192.168.1.1)"            "")
  [[ -z "$IP_ADDR" || -z "$GATEWAY" ]] && msg_error "IP-adres en gateway zijn verplicht bij statisch IP"
  NET_CONFIG="name=eth0,bridge=${BRIDGE},ip=${IP_ADDR},gw=${GATEWAY}"
  STATIC_IP="${IP_ADDR%%/*}"
else
  NET_CONFIG="name=eth0,bridge=${BRIDGE},ip=dhcp"
  STATIC_IP=""
fi

echo ""
echo -e " ${BOLD}Overzicht${CL}"
echo -e " ${DIM}──────────────────────────────────────────────────${CL}"
msg_info "Container ID  : ${BOLD}${CT_ID}${CL}"
msg_info "Hostname      : ${BOLD}${HOSTNAME}${CL}"
msg_info "Storage       : ${BOLD}${STORAGE}${CL}"
msg_info "Disk          : ${BOLD}${DISK} GB${CL}"
msg_info "RAM / Swap    : ${BOLD}${MEMORY} MB / ${SWAP} MB${CL}"
msg_info "CPU cores     : ${BOLD}${CORES}${CL}"
msg_info "Netwerk       : ${BOLD}${NET_CONFIG}${CL}"
echo ""

confirm "Doorgaan met installatie?" || { echo " Geannuleerd."; exit 0; }
echo ""

# ── Constanten
OS_TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
INSTALL_URL="https://raw.githubusercontent.com/damiaan111/ProxDash/main/homelab-dashboard/main/install/homelab-dashboard-install.sh"
PORT=7575

# ── Template downloaden
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
  --hostname    "${HOSTNAME}" \
  --memory      "${MEMORY}" \
  --swap        "${SWAP}" \
  --rootfs      "${STORAGE}:${DISK}" \
  --cores       "${CORES}" \
  --net0        "${NET_CONFIG}" \
  --unprivileged 1 \
  --features    "nesting=1" \
  --start       1 \
  --onboot      1 \
  >/dev/null 2>&1
msg_ok "Container ${CT_ID} aangemaakt en gestart"

# ── Wacht op IP
msg_info "Wachten op netwerk..."
FINAL_IP=""
for i in {1..25}; do
  FINAL_IP=$(pct exec "${CT_ID}" -- hostname -I 2>/dev/null | awk '{print $1}' || true)
  [[ -n "$FINAL_IP" ]] && break
  sleep 2
done

# Bij statisch IP: gebruik het ingestelde adres als fallback
[[ -z "$FINAL_IP" && -n "$STATIC_IP" ]] && FINAL_IP="$STATIC_IP"
[[ -z "$FINAL_IP" ]] && msg_error "Container kreeg geen IP — controleer bridge ${BRIDGE} en DHCP"
msg_ok "IP-adres: ${BOLD}${FINAL_IP}${CL}"

# ── App installeren
msg_info "ProxDash installeren in container..."
pct exec "${CT_ID}" -- bash -c "$(curl -fsSL ${INSTALL_URL})"
msg_ok "Installatie voltooid"

# ── Klaar
echo ""
echo -e " ${GN}${BOLD}✅ ProxDash is succesvol geïnstalleerd!${CL}"
echo -e " ${BL}🌐 Open in je browser:${CL}  ${GN}${BOLD}http://${FINAL_IP}:${PORT}${CL}"
echo -e " ${YW}📦 Container ID : ${CT_ID}${CL}"
echo -e " ${YW}🖥️  Beheer via   : Proxmox GUI → CT ${CT_ID}${CL}"
echo ""
