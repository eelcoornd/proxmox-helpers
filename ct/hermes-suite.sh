#!/usr/bin/env bash
# Rewrite the install-script URL to point at this repo instead of community-scripts.
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func \
  | sed 's|community-scripts/ProxmoxVE/main/install/|eelcoornd/proxmox-helpers/main/install/|g')
# Copyright (c) 2026 eelcoornd
# Author: eelcoornd
# License: MIT | https://github.com/eelcoornd/proxmox-helpers/raw/main/LICENSE
# Source: https://github.com/sunnysktsang/hermes-suite

APP="Hermes Suite"
var_tags="${var_tags:-ai;automation;docker;agent}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-32}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors
# The build.func default is "${APP,,-spaces}-install" = "hermessuite-install".
# We keep the hyphen in the install script filename for readability.
# shellcheck disable=SC2034
var_install="hermes-suite-install"

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /home/hermes/hermes-suite ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating Hermes Suite"
  cd /home/hermes/hermes-suite || exit
  $STD sudo -u hermes git pull
  $STD sudo -u hermes ./down.sh || true
  $STD sudo -u hermes ./up.sh
  msg_ok "Updated Hermes Suite"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URLs:${CL}"
echo -e "${TAB}${BGN}Gateway:    http://${IP}:8642${CL}"
echo -e "${TAB}${BGN}WebUI:      http://${IP}:8787${CL}"
echo -e "${TAB}${BGN}Dashboard:  http://${IP}:9119${CL}"
echo -e "${INFO}${YW} Add API keys in:${CL}"
echo -e "${TAB}${BGN}/home/hermes/.hermes/.env${CL}"
