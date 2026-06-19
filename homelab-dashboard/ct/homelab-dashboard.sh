#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Homelab User
# License: MIT
# Source: Local

APP="HomeLab-Dashboard"
var_tags="dashboard;homelab"
var_cpu="1"
var_ram="256"
var_disk="2"
var_os="debian"
var_version="12"
var_unprivileged="1"

header_info() {
  clear
  cat << "EOF"
    __  __                   __          __       ____            __    __
   / / / /___  ____ ___  ___/ /   ____ _/ /_     / __ \____ ____/ /_  / /_  ____  ____ __________/ /
  / /_/ / __ \/ __ `__ \/ _ / /   / __ `/ __ \  / / / / __ `/ __  __ \/ __ \/ __ \/ __ `/ ___/ __  /
 / __  / /_/ / / / / / /  __/ /___/ /_/ / /_/ / / /_/ / /_/ (__  ) / / / /_/ / /_/ / /_/ / /  / /_/ /
/_/ /_/\____/_/ /_/ /_/\___/_____/\__,_/_.___/ /_____/\__,_/____/_/ /_/_.___/\____/\__,_/_/   \__,_/
                                                                            HomeLab Dashboard v1.0
EOF
}

header_info
echo -e "Laden..."
start_script

color
catch_errors

function default_settings() {
  CT_TYPE="1"
  DISK_SIZE="$var_disk"
  CORE_COUNT="$var_cpu"
  RAM_SIZE="$var_ram"
  OS_TYPE="$var_os"
  OS_VERSION="$var_version"
  TAGS="$var_tags"
  VERB="no"
  echo_default
}

function update_script() {
  header_info
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

# Installeer in de container
lxc-attach -n ${CT_ID} -- bash -c "$(curl -fsSL https://raw.githubusercontent.com/JOUW_GITHUB_USERNAME/homelab-dashboard/main/install/homelab-dashboard-install.sh)"

IP=$(lxc-info -n ${CT_ID} -iH | head -n1)
echo -e "\n${APP} is succesvol geinstalleerd!\n"
echo -e "${BL}[URL]${CL} ${GN}http://${IP}:7575${CL}\n"
