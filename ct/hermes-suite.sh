#!/usr/bin/env bash
# =============================================================================
# hermes-suite.sh — Proxmox VE helper script
#
# Creates a Debian 13 LXC on the Proxmox host, installs Docker + Compose,
# clones sunnysktsang/hermes-suite, and starts the stack.
#
# Run as root on the Proxmox VE host:
#   bash -c "$(wget -qLO - https://raw.githubusercontent.com/eelcoornd/proxmox-helpers/main/ct/hermes-suite.sh)"
#
# Env-var non-interactive mode: set NONINTERACTIVE=1 and any of
#   CTID CT_HOSTNAME DISK CORES RAM SWAP BRIDGE STORAGE UNPRIVILEGED PASSWORD
# =============================================================================
set -euo pipefail

APP="Hermes Suite"

# ---------- pretty ----------
RD=$'\033[01;31m'; GN=$'\033[1;92m'; YW=$'\033[33m'; BL=$'\033[36m'; CL=$'\033[m'
msg()  { echo -e " ${BL}•${CL} $*"; }
ok()   { echo -e " ${GN}✓${CL} $*"; }
warn() { echo -e " ${YW}!${CL} $*"; }
die()  { echo -e " ${RD}✗${CL} $*" >&2; exit 1; }

header() {
    clear
    cat <<'EOF'
    __  __
   / / / /__  _________ ___  ___  _____
  / /_/ / _ \/ ___/ __ `__ \/ _ \/ ___/
 / __  /  __/ /  / / / / / /  __(__  )
/_/ /_/\___/_/  /_/ /_/ /_/\___/____/    Suite
EOF
    echo -e "                              ${BL}Proxmox VE helper${CL}\n"
}

# ---------- defaults ----------
NONINTERACTIVE="${NONINTERACTIVE:-0}"
CTID_DEFAULT="$(pvesh get /cluster/nextid 2>/dev/null || echo 200)"
CTID="${CTID:-$CTID_DEFAULT}"
CT_HOSTNAME="${CT_HOSTNAME:-hermes-suite}"
DISK="${DISK:-32}"
CORES="${CORES:-4}"
RAM="${RAM:-8192}"
SWAP="${SWAP:-512}"
BRIDGE="${BRIDGE:-vmbr0}"
STORAGE="${STORAGE:-local-lvm}"
UNPRIVILEGED="${UNPRIVILEGED:-1}"
PASSWORD="${PASSWORD:-}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
OS_TEMPLATE="${OS_TEMPLATE:-debian-13-standard}"
HERMES_UID="${HERMES_UID:-1000}"
HERMES_GID="${HERMES_GID:-1000}"
HERMES_SUITE_REPO="${HERMES_SUITE_REPO:-https://github.com/sunnysktsang/hermes-suite.git}"
HERMES_SUITE_REF="${HERMES_SUITE_REF:-main}"

# ---------- preflight ----------
[[ $EUID -eq 0 ]] || die "Run as root on the Proxmox host."
command -v pveversion >/dev/null || die "This must run on a Proxmox VE host."
command -v pct >/dev/null       || die "pct not found."
command -v whiptail >/dev/null   || die "whiptail not found (apt install whiptail)."

header
msg "Proxmox: $(pveversion | head -1)"
msg "Suggested CTID: $CTID   Storage: $STORAGE   Bridge: $BRIDGE"
echo

# ---------- interactive wizard ----------
if [[ "$NONINTERACTIVE" != "1" ]]; then
    CHOICE=$(whiptail --title "$APP LXC" --menu "Settings" 12 60 3 \
        "1" "Default settings (${CORES} vCPU / ${RAM}MB / ${DISK}GB)" \
        "2" "Advanced — customise every setting" \
        "3" "Cancel" 3>&1 1>&2 2>&3) || die "Cancelled."

    case "$CHOICE" in
    1) : ;;  # keep defaults
    2)
        CTID=$(whiptail --inputbox "Container ID"  8 60 "$CTID"        --title "CTID"      3>&1 1>&2 2>&3) || die "Cancelled."
        CT_HOSTNAME=$(whiptail --inputbox "Hostname" 8 60 "$CT_HOSTNAME" --title "Hostname" 3>&1 1>&2 2>&3) || die "Cancelled."
        CORES=$(whiptail --inputbox "vCPU cores"  8 60 "$CORES" --title "CPU"    3>&1 1>&2 2>&3) || die "Cancelled."
        RAM=$(whiptail   --inputbox "RAM (MB)"    8 60 "$RAM"   --title "Memory" 3>&1 1>&2 2>&3) || die "Cancelled."
        DISK=$(whiptail  --inputbox "Disk (GB)"   8 60 "$DISK"  --title "Disk"   3>&1 1>&2 2>&3) || die "Cancelled."

        # storage picker
        mapfile -t STORAGES < <(pvesm status -content rootdir 2>/dev/null | awk 'NR>1 {print $1}')
        [[ ${#STORAGES[@]} -eq 0 ]] && die "No storage with 'rootdir' content type."
        STORAGE_ITEMS=()
        for s in "${STORAGES[@]}"; do STORAGE_ITEMS+=("$s" ""); done
        STORAGE=$(whiptail --title "Storage" --menu "Container storage" 15 60 8 \
            "${STORAGE_ITEMS[@]}" 3>&1 1>&2 2>&3) || die "Cancelled."

        BRIDGE=$(whiptail --inputbox "Network bridge" 8 60 "$BRIDGE" --title "Network" 3>&1 1>&2 2>&3) || die "Cancelled."

        if whiptail --title "Container type" --yesno "Unprivileged container? (recommended)" 8 60; then
            UNPRIVILEGED=1
        else
            UNPRIVILEGED=0
        fi

        PASSWORD=$(whiptail --passwordbox "Root password (blank = auto-generate)" 8 60 "" --title "Password" 3>&1 1>&2 2>&3) || die "Cancelled."
        ;;
    3|*) die "Cancelled." ;;
    esac

    whiptail --title "Confirm" --yesno "Create LXC $CTID ($CT_HOSTNAME)?
  vCPU:     $CORES
  RAM:      ${RAM} MB
  Disk:     ${DISK} GB on $STORAGE
  Bridge:   $BRIDGE
  Type:     $([[ $UNPRIVILEGED -eq 1 ]] && echo unprivileged || echo privileged)

Then install Docker and deploy Hermes Suite." 15 70 || die "Cancelled."
fi

# ---------- guard: CTID must be free ----------
if pct status "$CTID" &>/dev/null; then
    die "CTID $CTID already exists. Pick another."
fi

# ---------- template ----------
msg "Locating LXC template matching '${OS_TEMPLATE}'"
pveam update >/dev/null 2>&1 || warn "pveam update failed (offline?), continuing"
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
    # ponytail: openssl avoids tr/head SIGPIPE + pipefail interaction
    PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-20)
    GENERATED_PASSWORD=1
fi

# ---------- create container ----------
msg "Creating LXC $CTID ($CT_HOSTNAME) — ${CORES} vCPU, ${RAM}MB RAM, ${DISK}GB disk"
pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" \
    --hostname "$CT_HOSTNAME" \
    --cores "$CORES" \
    --memory "$RAM" \
    --swap "$SWAP" \
    --rootfs "${STORAGE}:${DISK}" \
    --net0 "name=eth0,bridge=${BRIDGE},ip=dhcp,firewall=1" \
    --features "nesting=1,keyctl=1" \
    --unprivileged "$UNPRIVILEGED" \
    --onboot 1 \
    --password "$PASSWORD" \
    --ostype debian >/dev/null
ok "Container created"

msg "Starting container"
pct start "$CTID"
IP=""
for _ in {1..30}; do
    IP=$(pct exec "$CTID" -- ip -4 -o addr show eth0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 || true)
    [[ -n "$IP" ]] && break
    sleep 1
done
[[ -n "$IP" ]] || die "Container has no IP after 30s."
ok "Container running at ${IP}"

# ---------- provision inside ----------
msg "Installing Docker + Hermes Suite inside container (this takes a while)"
pct exec "$CTID" -- bash -euo pipefail -c "
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl git gnupg lsb-release sudo >/dev/null

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(. /etc/os-release && echo \$VERSION_CODENAME) stable\" \
    > /etc/apt/sources.list.d/docker.list
apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
systemctl enable --now docker >/dev/null

if ! id hermes &>/dev/null; then
    groupadd -g ${HERMES_GID} hermes
    useradd -m -u ${HERMES_UID} -g ${HERMES_GID} -s /bin/bash hermes
    usermod -aG docker hermes
fi

sudo -u hermes -H bash -c '
    cd ~
    if [ ! -d hermes-suite ]; then
        git clone --depth 1 --branch ${HERMES_SUITE_REF} ${HERMES_SUITE_REPO} hermes-suite
    fi
    cd hermes-suite
    sed -i \"s/^CONTAINER_RUNTIME=.*/CONTAINER_RUNTIME=docker/\" versions.env
    mkdir -p ~/.hermes ~/workspace
'
"
ok "Provisioned"

msg "Starting hermes-suite (first image pull may take several minutes)"
pct exec "$CTID" -- sudo -u hermes -H bash -c "cd ~/hermes-suite && ./up.sh" \
    || warn "up.sh exited non-zero — check 'pct exec $CTID -- sudo -u hermes ~/hermes-suite/logs.sh'"

# ---------- summary ----------
echo
ok "Hermes Suite deployed"
cat <<EOF

  Container:  ${CTID} (${CT_HOSTNAME})
  Address:    ${IP}
  Root pass:  ${PASSWORD}${GENERATED_PASSWORD:+  (generated — save it now)}

  Endpoints:
    Gateway:    http://${IP}:8642
    WebUI:      http://${IP}:8787
    Dashboard:  http://${IP}:9119

  Shell:      pct enter ${CTID}
  Data dir:   /home/hermes/.hermes  (edit .env to add API keys, then ./up.sh)
  Update:     pct exec ${CTID} -- sudo -u hermes bash -c 'cd ~/hermes-suite && git pull && ./down.sh && ./up.sh'

EOF
