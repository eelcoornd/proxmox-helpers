#!/usr/bin/env bash
# =============================================================================
# hermes-suite.sh — Proxmox VE helper script
#
# Creates an unprivileged Debian 13 LXC on the Proxmox host, installs Docker
# and Compose, clones sunnysktsang/hermes-suite, and starts the stack.
#
# Usage on the Proxmox host (as root):
#   bash -c "$(wget -qLO - https://raw.githubusercontent.com/eelcoornd/proxmox-helpers/main/ct/hermes-suite.sh)"
#
# Non-interactive with overrides:
#   CTID=210 HOSTNAME=hermes DISK=32 CORES=4 RAM=8192 bash -c "$(wget -qLO - .../hermes-suite.sh)"
#
# Idempotent-ish: refuses to overwrite an existing CTID; re-run picks a new one.
# =============================================================================
set -euo pipefail

# ---------- config (overridable via env) ----------
CTID="${CTID:-$(pvesh get /cluster/nextid)}"
HOSTNAME="${HOSTNAME:-hermes-suite}"
DISK="${DISK:-32}"                      # GB
CORES="${CORES:-4}"
RAM="${RAM:-8192}"                      # MB
SWAP="${SWAP:-512}"                     # MB
BRIDGE="${BRIDGE:-vmbr0}"
STORAGE="${STORAGE:-local-lvm}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
OS_TEMPLATE="${OS_TEMPLATE:-debian-13-standard}"
PASSWORD="${PASSWORD:-}"                # empty = generate random
UNPRIVILEGED="${UNPRIVILEGED:-1}"
HERMES_UID="${HERMES_UID:-1000}"
HERMES_GID="${HERMES_GID:-1000}"
HERMES_SUITE_REPO="${HERMES_SUITE_REPO:-https://github.com/sunnysktsang/hermes-suite.git}"
HERMES_SUITE_REF="${HERMES_SUITE_REF:-main}"

# ---------- pretty ----------
RD=$'\033[01;31m'; GN=$'\033[1;92m'; YW=$'\033[33m'; BL=$'\033[36m'; CL=$'\033[m'
msg()  { echo -e " ${BL}•${CL} $*"; }
ok()   { echo -e " ${GN}✓${CL} $*"; }
warn() { echo -e " ${YW}!${CL} $*"; }
die()  { echo -e " ${RD}✗${CL} $*" >&2; exit 1; }

# ---------- preflight ----------
[[ $EUID -eq 0 ]] || die "Run as root on the Proxmox host."
command -v pveversion >/dev/null || die "This must run on a Proxmox VE host."
command -v pct >/dev/null       || die "pct not found."

if pct status "$CTID" &>/dev/null; then
    die "CTID $CTID already exists. Set CTID=<free-id> or delete it."
fi

# ---------- template ----------
msg "Locating LXC template matching '${OS_TEMPLATE}'"
pveam update >/dev/null || warn "pveam update failed (offline?), continuing"
TEMPLATE=$(pveam available -section system | awk -v m="$OS_TEMPLATE" '$2 ~ m {print $2}' | sort -V | tail -1)
[[ -n "${TEMPLATE:-}" ]] || die "No template matches '${OS_TEMPLATE}'."
TEMPLATE_PATH="/var/lib/vz/template/cache/${TEMPLATE}"
if [[ ! -f "$TEMPLATE_PATH" ]]; then
    msg "Downloading template ${TEMPLATE}"
    pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
fi
ok "Template ready: ${TEMPLATE}"

# ---------- password ----------
if [[ -z "$PASSWORD" ]]; then
    PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)
    GENERATED_PASSWORD=1
fi

# ---------- create container ----------
msg "Creating LXC $CTID ($HOSTNAME) — ${CORES} vCPU, ${RAM}MB RAM, ${DISK}GB disk"
FEATURES="nesting=1,keyctl=1"
pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" \
    --hostname "$HOSTNAME" \
    --cores "$CORES" \
    --memory "$RAM" \
    --swap "$SWAP" \
    --rootfs "${STORAGE}:${DISK}" \
    --net0 "name=eth0,bridge=${BRIDGE},ip=dhcp,firewall=1" \
    --features "$FEATURES" \
    --unprivileged "$UNPRIVILEGED" \
    --onboot 1 \
    --password "$PASSWORD" \
    --ostype debian >/dev/null
ok "Container created"

msg "Starting container"
pct start "$CTID"
# wait for network
for _ in {1..30}; do
    IP=$(pct exec "$CTID" -- ip -4 -o addr show eth0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 || true)
    [[ -n "${IP:-}" ]] && break
    sleep 1
done
[[ -n "${IP:-}" ]] || die "Container has no IP after 30s."
ok "Container running at ${IP}"

# ---------- provision inside ----------
msg "Provisioning inside container (Docker + hermes-suite)"
pct exec "$CTID" -- bash -euo pipefail -c "
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl git gnupg lsb-release >/dev/null

# Docker CE from official repo
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(. /etc/os-release && echo \$VERSION_CODENAME) stable\" \
    > /etc/apt/sources.list.d/docker.list
apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
systemctl enable --now docker >/dev/null

# hermes user (matches UID/GID that the container image uses)
if ! id hermes &>/dev/null; then
    groupadd -g ${HERMES_GID} hermes
    useradd -m -u ${HERMES_UID} -g ${HERMES_GID} -s /bin/bash hermes
    usermod -aG docker hermes
fi

# clone the suite
sudo -u hermes -H bash -c '
    cd ~
    if [ ! -d hermes-suite ]; then
        git clone --depth 1 --branch ${HERMES_SUITE_REF} ${HERMES_SUITE_REPO} hermes-suite
    fi
    cd hermes-suite
    # force docker path (no podman inside the LXC)
    sed -i \"s/^CONTAINER_RUNTIME=.*/CONTAINER_RUNTIME=docker/\" versions.env
    mkdir -p ~/.hermes ~/workspace
'
"
ok "Provisioned"

msg "Starting hermes-suite (first pull may take several minutes)"
pct exec "$CTID" -- sudo -u hermes -H bash -c "
    cd ~/hermes-suite
    ./up.sh
" || warn "up.sh exited non-zero — check 'pct exec $CTID -- sudo -u hermes ~/hermes-suite/logs.sh'"

# ---------- summary ----------
echo
ok "Hermes Suite deployed"
cat <<EOF

  Container:  ${CTID} (${HOSTNAME})
  Address:    ${IP}
  Root pass:  ${PASSWORD}${GENERATED_PASSWORD:+  (generated — save it now)}

  Endpoints:
    Gateway:    http://${IP}:8642
    WebUI:      http://${IP}:8787
    Dashboard:  http://${IP}:9119

  Shell:    pct enter ${CTID}
  Data:     /home/hermes/.hermes  (edit .env to add API keys, then ./up.sh)
  Update:   pct exec ${CTID} -- sudo -u hermes bash -c 'cd ~/hermes-suite && git pull && ./down.sh && ./up.sh'

EOF
