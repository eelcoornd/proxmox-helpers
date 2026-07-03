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

# ------------------------------------------------------------------------------
# Optional: configure a local vLLM (or any OpenAI-compatible) endpoint.
# Writes ~/.hermes/.env + ~/.hermes/config.yaml and restarts the container.
# Skip to configure manually later at /home/hermes/.hermes/{env,config.yaml}.
# ------------------------------------------------------------------------------
if whiptail --title "Local LLM endpoint" --yesno \
    "Configure a local vLLM / OpenAI-compatible endpoint now?\n\nSkip to edit /home/hermes/.hermes/{.env,config.yaml} by hand later." \
    10 70; then
  LLM_URL=$(whiptail --title "Local LLM endpoint" --inputbox \
    "Base URL (must include /v1):" 8 70 "http://192.168.100.1:8000/v1" 3>&1 1>&2 2>&3) || LLM_URL=""
  LLM_MODEL=$(whiptail --title "Local LLM endpoint" --inputbox \
    "Model name (as served by your endpoint):" 8 70 "qwen" 3>&1 1>&2 2>&3) || LLM_MODEL=""
  LLM_KEY=$(whiptail --title "Local LLM endpoint" --inputbox \
    "API key (most local servers accept any string):" 8 70 "sk-local" 3>&1 1>&2 2>&3) || LLM_KEY="sk-local"

  if [[ -n "$LLM_URL" && -n "$LLM_MODEL" ]]; then
    pct exec "$CTID" -- bash -c "cat > /home/hermes/.hermes/.env" <<EOF
# Written by proxmox-helpers/ct/hermes-suite.sh
# See https://github.com/NousResearch/hermes-agent/blob/main/.env.example for more.
OPENAI_API_KEY=${LLM_KEY}
OPENAI_BASE_URL=${LLM_URL}
EOF
    pct exec "$CTID" -- bash -c "cat > /home/hermes/.hermes/config.yaml" <<EOF
# Written by proxmox-helpers/ct/hermes-suite.sh
model:
  provider: "custom"       # aliases: vllm, ollama, llamacpp
  base_url: "${LLM_URL}"
  default: "${LLM_MODEL}"
EOF
    # In-container hermes runs as uid 10000; the host's uid 1000 can't write here.
    pct exec "$CTID" -- chown 10000:10000 \
      /home/hermes/.hermes/.env /home/hermes/.hermes/config.yaml
    pct exec "$CTID" -- docker restart hermes-suite >/dev/null 2>&1 \
      && echo -e "${INFO}${GN} Configured local LLM (${LLM_MODEL} @ ${LLM_URL}) and restarted container${CL}"
  fi
fi

# ------------------------------------------------------------------------------
# Optional: set a root password so console/SSH login works.
# Default access is via `pct enter $CTID` (no password needed) from the host.
# ------------------------------------------------------------------------------
if whiptail --title "Root password" --yesno \
    "Set a root password on CT ${CTID}?\n\nWithout one, log in only via 'pct enter ${CTID}' from the Proxmox host." \
    10 70; then
  ROOT_PW=""
  while [[ -z "$ROOT_PW" ]]; do
    ROOT_PW=$(whiptail --title "Root password" --passwordbox \
      "Enter root password for CT ${CTID} (min 5 chars):" 8 70 3>&1 1>&2 2>&3) \
      || { ROOT_PW=""; break; }
    if [[ ${#ROOT_PW} -lt 5 ]]; then
      whiptail --title "Root password" --msgbox "Password too short (need 5+ chars)." 8 50
      ROOT_PW=""
    fi
  done
  if [[ -n "$ROOT_PW" ]]; then
    pct exec "$CTID" -- bash -c "echo 'root:${ROOT_PW}' | chpasswd" \
      && echo -e "${INFO}${GN} Root password set on CT ${CTID}${CL}"
  fi
fi

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URLs:${CL}"
echo -e "${TAB}${BGN}Gateway:    http://${IP}:8642${CL}"
echo -e "${TAB}${BGN}WebUI:      http://${IP}:8787${CL}"
echo -e "${TAB}${BGN}Dashboard:  http://${IP}:9119${CL}"
echo -e "${INFO}${YW} Add API keys in:${CL}"
echo -e "${TAB}${BGN}/home/hermes/.hermes/.env${CL}"
