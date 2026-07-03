# proxmox-helpers

Personal Proxmox VE helper scripts. Inspired by
[community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE)
but kept intentionally small — one self-contained script per app, no framework
indirection.

Run every script **as root on the Proxmox VE host** (not inside a container).

## Scripts

### hermes-suite

Deploys [sunnysktsang/hermes-suite](https://github.com/sunnysktsang/hermes-suite)
(hermes-agent + hermes-webui + hermes-dashboard) into a new unprivileged
Debian 13 LXC with Docker.

```sh
bash -c "$(wget -qLO - https://raw.githubusercontent.com/eelcoornd/proxmox-helpers/main/ct/hermes-suite.sh)"
```

Defaults: CTID = next free, 4 vCPU, 8 GB RAM, 32 GB disk, DHCP on `vmbr0`,
unprivileged, `nesting=1,keyctl=1` (required for Docker inside LXC).

Override any default via env vars:

```sh
CTID=210 HOSTNAME=hermes DISK=64 RAM=16384 CORES=6 BRIDGE=vmbr1 STORAGE=local-zfs \
  bash -c "$(wget -qLO - https://raw.githubusercontent.com/eelcoornd/proxmox-helpers/main/ct/hermes-suite.sh)"
```

Ports exposed by the container: `8642` (gateway), `8787` (webui), `9119`
(dashboard). Add API keys in `/home/hermes/.hermes/.env` after first boot and
run `./up.sh` from inside the CT to restart.

## License

MIT
