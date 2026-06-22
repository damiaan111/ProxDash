#!/usr/bin/env bash
# ============================================================
#  ProxDash — HomeLab Dashboard LXC Installer
#  Auteur  : damiaan111
#  Licentie: MIT
#  Gebruik : bash -c "$(curl -fsSL https://raw.githubusercontent.com/damiaan111/ProxDash/main/homelab-dashboard/main/ct/homelab-dashboard.sh)"
#  Vereist : Proxmox VE 7+, root
# ============================================================

# ── Wanneer stdin geen terminal is (curl pipe) — script naar /tmp schrijven
#    en opnieuw uitvoeren met stdin van de echte terminal.
if [[ ! -t 0 ]]; then
  _TMP=$(mktemp /tmp/proxdash-XXXX.sh)
  curl -fsSL "https://raw.githubusercontent.com/damiaan111/ProxDash/main/homelab-dashboard/main/ct/homelab-dashboard.sh" \
    -o "$_TMP" 2>/dev/null
  chmod +x "$_TMP"
  bash "$_TMP" < /dev/tty
  rm -f "$_TMP"
  exit $?
fi

set -euo pipefail

# ── Kleuren
YW="\e[33m"; GN="\e[1;92m"; RD="\e[01;31m"
BL="\e[36m"; CL="\e[0m";    BO="\e[1m";  DIM="\e[2m"

msg_info()  { echo -e " ${BL}[INFO]${CL}  $*" >&2; }
msg_ok()    { echo -e " ${GN}[ OK ]${CL}  $*" >&2; }
msg_error() { echo -e " ${RD}[ERR ]${CL}  $*" >&2; exit 1; }

# ── ask "Label" "standaard"
#    Prompt + read beide via /dev/tty — geeft alleen de schone waarde via stdout
ask() {
  local label="$1" default="$2" value
  echo -en " ${YW}\u25b6${CL}  ${BO}$(printf '%-28s' "$label")${CL} ${DIM}[${default}]${CL}: " > /dev/tty
  read -r value < /dev/tty
  printf '%s' "${value:-$default}"
}

# ── confirm "Vraag" — 0 = ja, 1 = nee
confirm() {
  local label="$1" value
  echo -en " ${YW}\u25b6${CL}  ${BO}$(printf '%-28s' "$label")${CL} ${DIM}[j/N]${CL}: " > /dev/tty
  read -r value < /dev/tty
  [[ "${value,,}" =~ ^(j|ja|y|yes)$ ]]
}

clear
echo -e "
  ${BO}██████╗ ██████╗  ██████╗ ██╗  ██╗██████╗  █████╗ ███████╗██╗  ██╗${CL}
  ${BO}██╔══██╗██╔══██╗██╔═══██╗╚██╗██╔╝██╔══██╗██╔══██╗██╔════╝██║  ██║${CL}
  ${BO}██████╔╝██████╔╝██║   ██║ ╚███╔╝ ██║  ██║███████║██████╗███████║${CL}
  ${BO}██╔═══╝ ██╔══██╗██║   ██║ ██╔██╗ ██║  ██║██╔══██║╚════██║██╔══██║${CL}
  ${BO}██║     ██║  ██║╚██████╔╝██╔╝ ██╗██████╔╝██║  ██║███████║██║  ██║${CL}
  ${BO}╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝${CL}

           HomeLab Dashboard — Proxmox LXC Installer v2.1
"

# ── Vereisten
[[ "$(id -u)" != "0" ]]     && msg_error "Draai dit script als root"
command -v pct   &>/dev/null || msg_error "pct niet gevonden — is dit een Proxmox host?"
command -v pvesm &>/dev/null || msg_error "pvesm niet gevonden — is dit een Proxmox host?"
command -v curl  &>/dev/null || msg_error "curl niet gevonden"

# ── Template: zoek de nieuwste beschikbare debian-12 standaard template
pveam update >/dev/null 2>&1
OS_TEMPLATE=$(pveam available --section system 2>/dev/null \
  | awk '{print $2}' \
  | grep '^debian-12-standard_' \
  | sort -V | tail -1)
[[ -z "$OS_TEMPLATE" ]] && msg_error "Geen debian-12-standard template gevonden — controleer: pveam available --section system"

# ── Storage detecteren
mapfile -t STORAGE_LIST < <(pvesm status 2>/dev/null | awk 'NR>1 && $3=="active" {print $1}')
[[ ${#STORAGE_LIST[@]} -eq 0 ]] && msg_error "Geen actieve storage gevonden — controleer: pvesm status"

DEF_STORAGE="${STORAGE_LIST[0]}"
for _s in "${STORAGE_LIST[@]}"; do
  [[ "$_s" == "local-lvm" ]] && DEF_STORAGE="local-lvm" && break
done

# ── Bridge detecteren
mapfile -t BRIDGE_LIST < <(ip -o link show type bridge 2>/dev/null | awk -F': ' '{print $2}' | tr -d ' ')
[[ ${#BRIDGE_LIST[@]} -eq 0 ]] && BRIDGE_LIST=("vmbr0")
DEF_BRIDGE="${BRIDGE_LIST[0]}"

# ── Volgende vrije CT ID
DEF_CTID=$(pvesh get /cluster/nextid 2>/dev/null || echo "200")

# ── Wizard
echo -e " ${BO}Configureer je container${CL} — druk Enter voor de standaardwaarde"
echo -e " ${DIM}$(printf '%0.s─' {1..52})${CL}\n"

CT_ID=$(ask    "Container ID"         "$DEF_CTID")
HOSTNAME=$(ask "Hostname"             "proxdash")

echo -e "         ${DIM}Beschikbare pools: ${STORAGE_LIST[*]}${CL}" >&2
STORAGE=$(ask  "Storage pool"         "$DEF_STORAGE")

# Valideer storage
_VALID=""
for _s in "${STORAGE_LIST[@]}"; do [[ "$_s" == "$STORAGE" ]] && _VALID=1 && break; done
[[ -z "$_VALID" ]] && msg_error "'${STORAGE}' is geen actieve storage pool. Kies uit: ${STORAGE_LIST[*]}"

DISK=$(ask     "Disk (GB)"            "4")
MEMORY=$(ask   "RAM (MB)"             "512")
SWAP=$(ask     "Swap (MB)"            "512")
CORES=$(ask    "CPU cores"            "1")

echo -e "         ${DIM}Gevonden bridges : ${BRIDGE_LIST[*]}${CL}" >&2
BRIDGE=$(ask   "Netwerk bridge"       "$DEF_BRIDGE")

echo "" >&2
if confirm "Statisch IP instellen? (anders DHCP)"; then
  IP_CIDR=$(ask "IP + subnet (bijv. 192.168.1.50/24)" "")
  GATEWAY=$(ask "Gateway (bijv. 192.168.1.1)"         "")
  [[ -z "$IP_CIDR" || -z "$GATEWAY" ]] && msg_error "IP en gateway zijn verplicht bij statisch IP"
  NET_CFG="name=eth0,bridge=${BRIDGE},ip=${IP_CIDR},gw=${GATEWAY}"
  STATIC_IP="${IP_CIDR%%/*}"
else
  NET_CFG="name=eth0,bridge=${BRIDGE},ip=dhcp"
  STATIC_IP=""
fi

# ── Overzicht
echo -e "\n ${BO}Overzicht${CL}\n ${DIM}$(printf '%0.s─' {1..52})${CL}"
msg_info "Container ID : ${BO}${CT_ID}${CL}"
msg_info "Hostname     : ${BO}${HOSTNAME}${CL}"
msg_info "OS           : ${BO}Debian 12 (${OS_TEMPLATE})${CL}"
msg_info "Storage      : ${BO}${STORAGE}${CL}"
msg_info "Disk         : ${BO}${DISK} GB${CL}"
msg_info "RAM / Swap   : ${BO}${MEMORY} MB / ${SWAP} MB${CL}"
msg_info "CPU cores    : ${BO}${CORES}${CL}"
msg_info "Bridge       : ${BO}${BRIDGE}${CL}"
msg_info "IP           : ${BO}${STATIC_IP:-DHCP}${CL}"
echo ""

confirm "Doorgaan met installatie?" || { echo -e "\n Geannuleerd."; exit 0; }
echo ""

# ── Overige constanten
INSTALL_URL="https://raw.githubusercontent.com/damiaan111/ProxDash/main/homelab-dashboard/main/install/homelab-dashboard-install.sh"
PORT=7575

# ── Template downloaden indien nodig
TEMPLATE_PATH="/var/lib/vz/template/cache/${OS_TEMPLATE}"
if [[ ! -f "$TEMPLATE_PATH" ]]; then
  msg_info "Debian 12 template downloaden (${OS_TEMPLATE})..."
  pveam download local "$OS_TEMPLATE" >/dev/null 2>&1 \
    || msg_error "Template download mislukt — controleer: pveam available --section system"
  msg_ok "Template gedownload"
else
  msg_ok "Template al aanwezig: ${OS_TEMPLATE}"
fi

# ── Container aanmaken
msg_info "LXC container aanmaken (ID ${CT_ID})..."
pct create "${CT_ID}" "local:vztmpl/${OS_TEMPLATE}" \
  --hostname    "${HOSTNAME}" \
  --memory      "${MEMORY}" \
  --swap        "${SWAP}" \
  --rootfs      "${STORAGE}:${DISK}" \
  --cores       "${CORES}" \
  --net0        "${NET_CFG}" \
  --unprivileged 1 \
  --features    "nesting=1" \
  --start       1 \
  --onboot      1 \
  >/dev/null 2>&1
msg_ok "Container ${CT_ID} aangemaakt en gestart"

# ── Wachten op IP
msg_info "Wachten op netwerk..."
FINAL_IP=""
for _i in {1..25}; do
  FINAL_IP=$(pct exec "${CT_ID}" -- hostname -I 2>/dev/null | awk '{print $1}' || true)
  [[ -n "$FINAL_IP" ]] && break
  sleep 2
done
[[ -z "$FINAL_IP" && -n "$STATIC_IP" ]] && FINAL_IP="$STATIC_IP"
[[ -z "$FINAL_IP" ]] && msg_error "Container kreeg geen IP — controleer bridge ${BRIDGE} en DHCP"
msg_ok "IP-adres: ${BO}${FINAL_IP}${CL}"

# ── ProxDash installeren
msg_info "ProxDash installeren in container..."
pct exec "${CT_ID}" -- bash -c "$(curl -fsSL ${INSTALL_URL})"
msg_ok "Installatie voltooid"

# ── Klaar
echo -e "\n ${GN}${BO}✅ ProxDash is succesvol geïnstalleerd!${CL}"
echo -e " ${BL}🌐 Open in je browser :${CL}  ${GN}${BO}http://${FINAL_IP}:${PORT}${CL}"
echo -e " ${YW}📦 Container ID       : ${CT_ID}${CL}"
echo -e " ${YW}🖥️  Beheer via         : Proxmox GUI → CT ${CT_ID}${CL}\n"
