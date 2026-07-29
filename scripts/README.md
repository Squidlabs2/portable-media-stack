# Script map

Top-level scripts are stable entrypoints. On a fresh Debian machine, begin with `bootstrap.sh --prepare-host`; normal operations start after setup with `../squid-media`.

- `bootstrap.sh` — clone/update the repository, optionally prepare a fresh Debian host, then start installation.
- `install.sh` — first install or re-run the stack installer.
- `update.sh` — pull and refresh the running stack.
- `configure.sh` — edit the machine-local `.env` through the setup wizard.
- `prepare-host-debian.sh` — fresh-Debian Docker/Tailscale preparation, including required tailnet enrollment.

Implementation scripts are grouped by responsibility:

- `installer/` — configuration, preflight checks, Compose argument resolution, install/update orchestration.
- `ingress/` — Tailscale Funnel, generated Traefik routes, and Arr URL-base helpers.
- `services/` — downloader path preparation for SABnzbd and NZBDAV.
- `bootstrap-data/` — reusable Prowlarr/Arr/downloader export, fetch, and apply tooling.
- `host/` — host-specific preparation implementation.

For routine administration, use `../squid-media` from the repository root rather than calling implementation scripts directly.
