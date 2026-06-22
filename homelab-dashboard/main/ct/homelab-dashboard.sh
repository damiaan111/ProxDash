#!/usr/bin/env bash
# ============================================================
#  ProxDash — HomeLab Dashboard LXC Installer
#  Auteur  : damiaan111
#  Licentie: MIT
#  Gebruik : bash -c "$(curl -fsSL https://raw.githubusercontent.com/damiaan111/ProxDash/main/homelab-dashboard/main/ct/homelab-dashboard.sh)"
#  Vereist : Proxmox VE 7+, root
# ============================================================

# ── Wanneer stdin geen terminal is (curl pipe) — script naar /tmp schrijven en
#    opnieuw uitvoeren met stdin gekoppeld aan de echte terminal.
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

# ── Kleuren (naar stderr zodat ze nooit worden meegelezen als waarde)
YW="\033[33m"; GN="\033[1;92m"; RD="\033[01;31m"
BL="\033[36m"; CL="\033[m";     BO="\033[1m";   DIM="\033[2m"

msg_info()  { printf " ${BL}[INFO]${CL}  %s\n" "$*" >&2; }
msg_ok()    { printf " ${GN}[ OK ]${CL}  %s\n" "$*" >&2; }
msg_error() { printf " ${RD}[ERR ]${CL}  %s\n" "$*" >&2; exit 1; }

# ── ask "Label" "standaard" — schrijft prompt naar /dev/tty, leest van /dev/tty
#    geeft ALLEEN de ingevoerde waarde terug via stdout (geen kleurcodes)
ask() {
  local label="$1" default="$2" value
  printf " ${YW}\u25b6${CL}  ${BO}%-28s${CL} ${DIM}[%s]${CL}: " "$label" "$default" > /dev/tty
  read -r value < /dev/tty
  printf '%s' "${value:-$default}"
}

# ── confirm "Vraag" — returns 0 voor ja, 1 voor nee
confirm() {
  local label="$1" value
  printf " ${YW}\u25b6${CL}  ${BO}%-28s${CL} ${DIM}[j/N]${CL}: " "$label" > /dev/tty
  read -r value < /dev/tty
  [[ "${value,,}" =~ ^(j|ja|y|yes)$ ]]
}

clear >&2
printf >&2 "
  ${BO}██████╗ ██████╗  ██████╗ ██╗  ██╗██████╗  █████╗ ███████╗██╗  ██╗${CL}
  ${BO}██╔══██╗██╔══██╗██╔═══██╗╚██╗██╔╝██╔══██╗██╔══██╗██╔════╝██║  ██║${CL}
  ${BO}██████╔╝██████╔╝██║   ██║ ╚███╔╝ ██║  ██║███████║██████╗███████║${CL}
  ${BO}██╔═══╝ ██╔══██╗██║   ██║ ██╔██╗ ██║  ██║██╔══██║╚════██║██╔══██║${CL}
  ${BO}██║     ██║  ██║╚██████╔╝██╔╝ ██╗██████╔╝██║  ██║███████║██║  ██║${CL}
  ${BO}╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝${CL}

           HomeLab Dashboard — Proxmox LXC Installer v2.1

"

# ── Vereisten controleren
[[ "$(id -u)" != "0" ]]     && msg_error "Draai dit script als root"
command -v pct   &>/dev/null || msg_error "pct niet gevonden — is dit een Proxmox host?"
command -v pvesm &>/dev/null || msg_error "pvesm niet gevonden — is dit een Proxmox host?"
command -v curl  &>/dev/null || msg_error "curl niet gevonden"

# ── Storage detecteren (alle actieve pools)
mapfile -t STORAGE_LIST < <(pvesm status 2>/dev/null | awk 'NR>1 && $3=="active" {print $1}')
[[ ${#STORAGE_LIST[@]} -eq 0 ]] && msg_error "Geen actieve storage gevonden — controleer: pvesm status"

# Slim standaard kiezen: voorkeur local-lvm, anders eerste actieve
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
printf >&2 " ${BO}Configureer je container${CL} — druk Enter voor de standaardwaarde\n"
printf >&2 " ${DIM}%s${CL}\n\n" "$(printf '%0.s─' {1..52})"

CT_ID=$(ask   "Container ID"         "$DEF_CTID")
HOSTNAME=$(ask "Hostname"             "proxdash")

printf >&2 "         ${DIM}Beschikbare pools: %s${CL}\n" "${STORAGE_LIST[*]}"
STORAGE=$(ask "Storage pool"          "$DEF_STORAGE")

# Valideer storage
for _s in "${STORAGE_LIST[@]}"; do [[ "$_s" == "$STORAGE" ]] && _VALID=1 && break; done
[[ -z "${_VALID:-}" ]] && msg_error "'${STORAGE}' is geen actieve storage pool. Kies uit: ${STORAGE_LIST[*]}"

DISK=$(ask     "Disk (GB)"            "4")
MEMORY=$(ask   "RAM (MB)"             "512")
SWAP=$(ask     "Swap (MB)"            "512")
CORES=$(ask    "CPU cores"            "1")

printf >&2 "         ${DIM}Gevonden bridges : %s${CL}\n" "${BRIDGE_LIST[*]}"
BRIDGE=$(ask  "Netwerk bridge"         "$DEF_BRIDGE")

printf >&2 "\n"
if confirm "Statisch IP instellen? (anders DHCP)"; then
  IP_CIDR=$(ask  "IP + subnet (bijv. 192.168.1.50/24)" "")
  GATEWAY=$(ask  "Gateway (bijv. 192.168.1.1)"         "")
  [[ -z "$IP_CIDR" || -z "$GATEWAY" ]] && msg_error "IP en gateway zijn verplicht bij statisch IP"
  NET_CFG="name=eth0,bridge=${BRIDGE},ip=${IP_CIDR},gw=${GATEWAY}"
  STATIC_IP="${IP_CIDR%%/*}"
else
  NET_CFG="name=eth0,bridge=${BRIDGE},ip=dhcp"
  STATIC_IP=""
fi

# ── Overzicht
printf >&2 "\n ${BO}Overzicht${CL}\n ${DIM}%s${CL}\n" "$(printf '%0.s─' {1..52})"
msg_info "Container ID : ${BO}${CT_ID}${CL}"
msg_info "Hostname     : ${BO}${HOSTNAME}${CL}"
msg_info "OS           : ${BO}Debian 12${CL}"
msg_info "Storage      : ${BO}${STORAGE}${CL}"
msg_info "Disk         : ${BO}${DISK} GB${CL}"
msg_info "RAM / Swap   : ${BO}${MEMORY} MB / ${SWAP} MB${CL}"
msg_info "CPU cores    : ${BO}${CORES}${CL}"
msg_info "Bridge       : ${BO}${BRIDGE}${CL}"
msg_info "IP           : ${BO}${STATIC_IP:-DHCP}${CL}"
printf >&2 "\n"

confirm "Doorgaan met installatie?" || { printf >&2 "\n Geannuleerd.\n"; exit 0; }
printf >&2 "\n"

# ── Constanten
OS_TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
INSTALL_URL="https://raw.githubusercontent.com/damiaan111/ProxDash/main/homelab-dashboard/main/install/homelab-dashboard-install.sh"
PORT=7575

# ── Template downloaden indien nodig
TEMPLATE_PATH="/var/lib/vz/template/cache/${OS_TEMPLATE}"
if [[ ! -f "$TEMPLATE_PATH" ]]; then
  msg_info "Debian 12 template downloaden..."
  pveam update >/dev/null 2>&1
  pveam download local "$OS_TEMPLATE" >/dev/null 2>&1 \
    || msg_error "Template download mislukt — controleer: pveam available --section system"
  msg_ok "Template gedownload"
else
  msg_ok "Template al aanwezig"
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

# ── Wachten op IP-adres
msg_info "Wachten op netwerk..."
FINAL_IP=""
for _i in {1..25}; do
  FINAL_IP=$(pct exec "${CT_ID}" -- hostname -I 2>/dev/null | awk '{print $1}' || true)
  [[ -n "$FINAL_IP" ]] && break
  sleep 2
done
[[ -z "$FINAL_IP" && -n "$STATIC_IP" ]] && FINAL_IP="$STATIC_IP"
[[ -z "$FINAL_IP" ]] && msg_error "Container kreeg geen IP ��� controleer bridge ${BRIDGE} en DHCP"
msg_ok "IP-adres: ${BO}${FINAL_IP}${CL}"

# ── ProxDash installeren
msg_info "ProxDash installeren in container..."
pct exec "${CT_ID}" -- bash -c "$(curl -fsSL ${INSTALL_URL})"
msg_ok "Installatie voltooid"

# ── Klaar
printf >&2 "\n ${GN}${BO}✅ ProxDash is succesvol geïnstalleerd!${CL}\n"
printf >&2 " ${BL}🌐 Open in je browser :${CL}  ${GN}${BO}http://%s:%s${CL}\n" "$FINAL_IP" "$PORT"
printf >&2 " ${YW}📦 Container ID       : %s${CL}\n" "$CT_ID"
printf >&2 " ${YW}🖥️  Beheer via         : Proxmox GUI → CT %s${CL}\n\n" "$CT_ID"
