#!/usr/bin/env bash

# Copyright (c) 2026 eelcoornd
# Author: eelcoornd
# License: MIT | https://github.com/eelcoornd/proxmox-helpers/raw/main/LICENSE
# Source: https://github.com/sunnysktsang/hermes-suite

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Generating en_US.UTF-8 Locale"
$STD apt-get install -y locales
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
$STD locale-gen
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 >/dev/null
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
msg_ok "Generated Locale"

msg_info "Installing Dependencies"
$STD apt-get install -y \
  ca-certificates \
  curl \
  git \
  gnupg \
  lsb-release \
  sudo
msg_ok "Installed Dependencies"

msg_info "Installing Docker Engine"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
$STD apt-get update
$STD apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin
systemctl enable -q --now docker
msg_ok "Installed Docker Engine"

msg_info "Creating Hermes User"
groupadd -g 1000 hermes 2>/dev/null || true
useradd -m -u 1000 -g 1000 -s /bin/bash hermes 2>/dev/null || true
usermod -aG docker hermes
msg_ok "Created Hermes User"

msg_info "Cloning Hermes Suite"
$STD sudo -u hermes -H bash -c '
  cd ~
  git clone --depth 1 https://github.com/sunnysktsang/hermes-suite.git hermes-suite
  cd hermes-suite
  sed -i "s/^CONTAINER_RUNTIME=.*/CONTAINER_RUNTIME=docker/" versions.env
  mkdir -p ~/.hermes ~/workspace
  # ponytail: pre-seed files that ascensionoid/hermes-suite start.sh tries to
  # cp from /opt/hermes/.env.example (missing in image → crash-loop). Empty
  # target files short-circuit the cp block. Remove once upstream image ships
  # the .example files again.
  touch ~/.hermes/.env ~/.hermes/config.yaml ~/.hermes/SOUL.md
'
msg_ok "Cloned Hermes Suite"

msg_info "Starting Hermes Suite (first image pull can take several minutes)"
$STD sudo -u hermes -H bash -c 'cd ~/hermes-suite && ./up.sh'
msg_ok "Started Hermes Suite"

motd_ssh
customize
