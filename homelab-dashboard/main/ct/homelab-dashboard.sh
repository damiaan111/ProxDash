#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Author: damiaan111
# License: MIT

APP="HomeLab-Dashboard"
var_tags="${var_tags:-dashboard;homelab}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info "$APP"
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/homelab-dashboard ]]; then
    msg_error "Geen installatie gevonden in /opt/homelab-dashboard"
    exit 1
  fi
  msg_info "HomeLab Dashboard herstarten..."
  systemctl restart homelab-dashboard
  msg_ok "Herstart voltooid"
  exit
}

start
build_container
description

msg_ok "Container aangemaakt (ID: ${CT_ID})"

lxc-attach -n ${CT_ID} -- bash -c "$(curl -fsSL https://raw.githubusercontent.com/damiaan111/ProxDash/main/homelab-dashboard/main/install/homelab-dashboard-install.sh)"

IP=$(lxc-info -n ${CT_ID} -iH | head -n1)
echo -e "\n${APP} is succesvol geinstalleerd!\n"
echo -e "${BL}[URL]${CL} ${GN}http://${IP}:7575${CL}\n"
