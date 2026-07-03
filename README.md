# proxmox-helpers

Personal Proxmox VE helper scripts, built on the
[community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE)
framework (`build.func` / install.func). Each app script re-uses their upstream
wizard verbatim; only the install script and defaults are ours.

Run every script **as root on the Proxmox VE host** (not inside a container).

## Scripts

### hermes-suite

Deploys [sunnysktsang/hermes-suite](https://github.com/sunnysktsang/hermes-suite)
(hermes-agent + hermes-webui + hermes-dashboard) into a new Debian 13 LXC with
Docker.

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/eelcoornd/proxmox-helpers/main/ct/hermes-suite.sh)"
```

You get the standard community-scripts wizard: **Default / Advanced /
Diagnostic** menus, storage picker, network config, verbose toggle, etc.

Defaults: 4 vCPU, 8 GB RAM, 32 GB disk, unprivileged, `nesting=1,keyctl=1`
(required for Docker inside LXC).

Ports exposed: `8642` (gateway), `8787` (webui), `9119` (dashboard). Add API
keys in `/home/hermes/.hermes/.env` after first boot, then
`cd ~/hermes-suite && ./up.sh` inside the CT.

## Framework note

`ct/*.sh` sources `build.func` from community-scripts and rewrites the install
URL to fetch `install/*-install.sh` from **this** repo. When they update the
framework, we get it. Header ASCII art still comes from their repo — apps not
in their catalog print a single "Failed to download header" warning line;
harmless.

## License

MIT

