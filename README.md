# Portable Media Stack

Portable Docker Compose stack for Jellyfin, Radarr, Sonarr, Prowlarr, Seerr, NZBDAV, and optional legacy SABnzbd.

Goals:
- easy to deploy on multiple machines
- GitHub as the source of truth
- one-line bootstrap support
- machine-specific config kept local in `.env`
- Cloudflare Tunnel public ingress with required Tailscale remote administration
- optional bundled Traefik for self-contained installs on hosts that can receive 80/443

## Quick start

Existing Debian host with Docker and Tailscale already configured:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Squidlabs2/portable-media-stack/main/scripts/bootstrap.sh)
```

Fresh Debian host — recommended safe first step:

```bash
sudo apt-get update && sudo apt-get install -y curl && \
  bash <(curl -fsSL https://raw.githubusercontent.com/Squidlabs2/portable-media-stack/main/scripts/bootstrap.sh) \
    --prepare-host-only --skip-upgrade
```

The initial `curl` install is the only bootstrap prerequisite on a minimal Debian image. This conservative first step prepares the host, skips a full OS upgrade, and deliberately stops before stack deployment.

That guided path will:
- run `apt-get update`
- run `apt-get upgrade -y` by default
- install `curl`, `git`, `bash`, `python3`, and apt/GPG prerequisites
- install Docker Engine and the Docker Compose plugin
- install Tailscale and start `tailscaled`
- add the current non-root user to the `docker` group
- require enrollment into your Tailscale tailnet, using an auth key or browser login
- stop and print the command needed to begin the normal stack installer

Open a new SSH session so Docker group membership is refreshed. After confirming the host is responsive and Docker/Tailscale are healthy, continue with:

```bash
cd ~/portable-media-stack
docker info
tailscale status
./scripts/install.sh
```

Useful host-prep variants:

```bash
# prepare the host and immediately launch the installer, but skip a full apt upgrade
bash <(curl -fsSL https://raw.githubusercontent.com/Squidlabs2/portable-media-stack/main/scripts/bootstrap.sh) --prepare-host --skip-upgrade

# prepare only (default behavior of the recommended fresh-host command)
bash <(curl -fsSL https://raw.githubusercontent.com/Squidlabs2/portable-media-stack/main/scripts/bootstrap.sh) --prepare-host-only --skip-upgrade

# preview host prep commands without changing the machine
bash <(curl -fsSL https://raw.githubusercontent.com/Squidlabs2/portable-media-stack/main/scripts/bootstrap.sh) --prepare-host --dry-run
```

By default this installs the repo under `${HOME}/portable-media-stack`, so it automatically uses the current user on the machine rather than a hardcoded home path.

If you want it under a `containers` workspace, use:

```bash
INSTALL_DIR="${HOME}/containers/portable-media-stack" bash <(curl -fsSL https://raw.githubusercontent.com/Squidlabs2/portable-media-stack/main/scripts/bootstrap.sh)
```

Safer/manual install:

```bash
git clone git@github.com:Squidlabs2/portable-media-stack.git
cd portable-media-stack
./scripts/install.sh
```

On a brand-new install, the setup wizard starts with four simple choices:

1. Private Tailscale/LAN media box.
2. Family request box using a public Seerr-only Tailscale Funnel (the recommended default).
3. Portable custom-domain box using Cloudflare Tunnel.
4. Full custom setup for every deployment and service option.

The first three presets use NZBDAV and Seerr by default, keep legacy SABnzbd off, and leave bootstrap-data auto-apply off. Every preset keeps the host enrolled in Tailscale for SSH and private administration. The default public ingress exposes only Seerr through a root-level Tailscale Funnel URL; Radarr, Sonarr, Jellyfin, NZBDAV, and administration stay private. Run `./squid-media configure` later when you want to adjust every option.

Manual two-step fresh Debian flow:

```bash
./scripts/prepare-host-debian.sh
./scripts/install.sh
```

Yes: the installer asks configuration questions during setup and writes the answers to the local `.env` file.

## Deployment modes

- `tailnet-only`: publish app ports on the host and access them only over Tailscale.
- `tailscale-funnel`: keep the machine on Tailscale but expose selected apps publicly through Tailscale Funnel without router port forwarding.
- `cloudflare-tunnel`: use your own Cloudflare domain names without static IPs, DDNS, inbound ports, or router port forwarding.
- `traefik-private-dns`: add Traefik labels and hostnames for friendly private DNS names.
- `traefik-public-dns`: same as above, but intended for public DNS and TLS on hosts that can actually receive 80/443. The installer can generate per-device hostnames like `ethan-tv.myallbox.com`, `ethan-movie.myallbox.com`, and `ethan-seerr.myallbox.com`.

## Cloudflare Tunnel mode

Use `cloudflare-tunnel` when the boxes should use your domain but may live on random networks, changing public IPs, CGNAT, or routers you do not control.

For a device named `ethan` and `PUBLIC_DOMAIN=myallbox.com`, the generated public hostnames are:
- Radarr: `https://ethan-movie.myallbox.com`
- Sonarr: `https://ethan-tv.myallbox.com`
- Seerr: `https://ethan-seerr.myallbox.com`

Recommended `.env` values:
- `MODE=cloudflare-tunnel`
- `PUBLIC_DOMAIN=myallbox.com`
- `DEVICE_NAME=ethan`
- `CLOUDFLARE_TUNNEL_TOKEN_FILE=./secrets/cloudflare-tunnel-token`

Paste the Cloudflare Tunnel token into the local token file on the target box, or paste it into the installer when prompted so preflight can write that ignored local file for you and clear the raw value from `.env`. Do not commit or paste the token in chat.

Create one Cloudflare Tunnel per box in Cloudflare Zero Trust, then add Public Hostname routes for that tunnel:
- `ethan-movie.myallbox.com` -> `http://radarr:7878`
- `ethan-tv.myallbox.com` -> `http://sonarr:8989`
- `ethan-seerr.myallbox.com` -> `http://seerr:5055`

The stack starts `cloudflared` as a Compose service. It connects outbound to Cloudflare, so no public IP, DDNS, router port forwarding, or inbound 80/443 is required. Tailscale remains required on every host for private SSH and administration; it is not used for the public Cloudflare routes.

## Cloudflare domain mode

Use `traefik-public-dns` only when the host can receive inbound public traffic directly. For uncontrolled/changing networks, prefer `cloudflare-tunnel` instead.

For a device named `ethan` and `PUBLIC_DOMAIN=myallbox.com`, the generated public hostnames are:
- Radarr: `https://ethan-movie.myallbox.com`
- Sonarr: `https://ethan-tv.myallbox.com`
- Seerr: `https://ethan-seerr.myallbox.com`

For the next box, set only `DEVICE_NAME`, for example `DEVICE_NAME=bedroom`, and the same pattern becomes `bedroom-tv.myallbox.com`, `bedroom-movie.myallbox.com`, and `bedroom-seerr.myallbox.com`.

Recommended `.env` values:
- `MODE=traefik-public-dns`
- `PUBLIC_DOMAIN=myallbox.com`
- `DEVICE_NAME=ethan`
- `TRAEFIK_ACME_CHALLENGE=cloudflare-dns`
- `CLOUDFLARE_DNS_API_TOKEN=<local Cloudflare token, do not commit>`
- `TRAEFIK_EXPOSE_ADMIN_APPS=false`

The Cloudflare token needs permission to edit DNS for the zone so Traefik can complete Let's Encrypt DNS-01 validation. With DNS-01, Traefik can get certificates without relying on Tailscale DNS names.

DNS note: a Cloudflare wildcard record such as `*.myallbox.com` can cover the names, but DNS wildcards route every matching name to the same target. If later boxes live behind different public IPs/tunnels, create explicit records for each hostname or use a device-scoped naming shape such as `tv.ethan.myallbox.com` with `*.ethan.myallbox.com` per box. This repo still supports the requested `ethan-tv.myallbox.com` style hostnames.

## Tailscale Funnel mode

`tailscale-funnel` is the default public option for a family request box when:
- the machine stays on your tailnet
- you still want SSH and private admin access over Tailscale
- the router cannot forward 80/443
- you want to expose only Seerr publicly while keeping every media-management and administration service private

Recommended default values:
- `AUTO_CONFIGURE_FUNNEL=true`
- `FUNNEL_USE_PATHS=false`
- `FUNNEL_RADARR=false`
- `FUNNEL_SONARR=false`
- `FUNNEL_JELLYFIN=false`
- `FUNNEL_SEERR=true`
- `FUNNEL_SEERR_PUBLIC_PORT=443`
- `FUNNEL_SEERR_PATH=/`
- `INSTALL_TRAEFIK=false`

The repo includes `scripts/ingress/configure-funnel.sh`, which can apply the Funnel config later.
When Funnel auto-config is enabled, the installer now prints the expected public mapping and the Funnel helper/status output prints likely public URLs based on the machine's tailnet DNS name.

The default public URL is:

- `https://<device>.<tailnet>.ts.net/` -> Seerr on internal port `5055`

Seerr must be served at `/`; do not proxy it under `/seerr`, because its frontend does not reliably support a URL base. The installer can still be reconfigured for an intentional custom/path-based Funnel layout, but that is not the default and should not expose Arr, Jellyfin, NZBDAV, or administration services casually.

## Traefik options

- `INSTALL_TRAEFIK=true`: run a bundled Traefik container in this stack.
- `INSTALL_TRAEFIK=false`: reuse an existing Traefik instance and external Docker `proxy` network.

Bundled Traefik is the default for Traefik modes because it makes fresh-machine installs easier.

## Squid Media management CLI

After the first install, use the repository-local CLI instead of remembering the resolved Compose overlays and profiles:

```bash
./squid-media status
./squid-media start
./squid-media stop sonarr
./squid-media logs --follow seerr
./squid-media funnel-status
./squid-media update
```

`./squid-media configure` updates the local `.env`, and `./squid-media bootstrap-apply --input <file>` delegates to the existing bootstrap-data importer. The CLI deliberately has no destructive `destroy` or `reset` command; use the documented clean-reset workflow when you explicitly want to remove a deployment.

## Files

- `compose.yml` - base app stack
- `compose.traefik.yml` - Traefik labels shared by both Traefik setups
- `compose.traefik-bundled.yml` - bundled Traefik service
- `compose.jellyfin-intel-gpu.yml` - optional `/dev/dri` pass-through for Jellyfin Intel iGPU transcoding
- `compose.cloudflare-dns.yml` - Cloudflare DNS-01 ACME override for public-domain installs
- `compose.cloudflare-tunnel.yml` - Cloudflare Tunnel service for custom-domain ingress without inbound ports
- `compose.traefik-external.yml` - external proxy network for an existing Traefik host
- `compose.funnel-traefik.yml` - Traefik path-routing labels for Funnel mode
- `compose.funnel-traefik-bundled.yml` - bundled Traefik service bound to a local high port for Funnel mode
- `.env.example` - template for local `.env`
- `docs/nzbdav.md` - NZBDAV-specific setup, privacy, and path notes
- `docs/cloudflare-tunnel.md` - custom-domain Cloudflare Tunnel setup for portable boxes on uncontrolled networks
- `scripts/README.md` - script map and stable entrypoints
- `scripts/bootstrap.sh` - one-liner entrypoint
- `scripts/prepare-host-debian.sh` - optional Debian host prep wrapper for Docker, Compose, and Tailscale
- `scripts/install.sh`, `scripts/update.sh`, `scripts/configure.sh` - stable install/update/configure entrypoints
- `scripts/installer/` - setup wizard, preflight, network setup, Compose resolution, and install/update implementations
- `scripts/ingress/` - Funnel, Traefik, Seerr proxy, and Arr URL-base helpers
- `scripts/services/` - SABnzbd and NZBDAV path helpers
- `scripts/bootstrap-data/` - export, fetch, and apply tooling plus the Python implementation
- `scripts/host/` - host-specific preparation implementations
- `squid-media` - safe repository-local management CLI

## Notes

- Real secrets and machine-specific values stay out of git.
- `.env` is created locally during install.
- `bootstrap-data/local/bootstrap-data.json` is local-only and ignored by git because it can contain API keys and indexer credentials.
- `./scripts/bootstrap-data/export-bootstrap-data.sh` also refreshes a reusable bootstrap library under `${HOME}/.local/share/portable-media-stack/bootstrap-data/`, including `latest-bootstrap-data.json` plus timestamped history copies for future machines.
- `bootstrap.sh` is intentionally small; all real logic lives in versioned repo scripts.
- `scripts/prepare-host-debian.sh` is Debian-only and optional; use it on fresh machines that still need Docker/Tailscale installed.
- Tailscale stays on the host; SSH and other host access remain independent of this stack.
- For public Radarr/Sonarr exposure, use strong app credentials.
- Tailscale Funnel uses your tailnet's `*.ts.net` naming, not your own custom public CNAMEs. Use `cloudflare-tunnel` for custom Cloudflare names like `ethan-tv.myallbox.com` when you do not control public IPs/routers.
- With NZBDAV enabled, Sonarr and Radarr still use a SAB-compatible download-client integration, but the client host should be `nzbdav` on port `3000`.
- Seerr is enabled by `ENABLE_SEERR=true`, stores config in `${SEERR_CONFIG}`, listens locally on `${SEERR_PORT:-5055}`, and is the recommended family-facing request UI.
- Jellyfin Intel iGPU pass-through is opt-in with `ENABLE_JELLYFIN_INTEL_GPU=true`; leave it off on hosts without `/dev/dri`.
- Sonarr's library root folder inside the container is `/tv`; Radarr's library root folder is `/movies`.
- NZBDAV completed downloads live under `/downloads/nzbdav-completed/<category>` inside the containers, backed by `${DOWNLOADS_PATH}/nzbdav-completed/<category>` on the host.

## Fresh Debian checklist

1. Run the bootstrap with host prep if the machine does not already have Docker and Tailscale:

   ```bash
   INSTALL_DIR="${HOME}/containers/portable-media-stack" bash <(curl -fsSL https://raw.githubusercontent.com/Squidlabs2/portable-media-stack/main/scripts/bootstrap.sh) --prepare-host
   ```

2. Log out and back in after host prep if you want to use Docker without `sudo`.
3. During host prep, you can paste a Tailscale auth key when prompted to join automatically, or press Enter to skip and run `sudo tailscale up` manually afterward.
4. During installer prompts, the default persistent paths now stay under the current user's home directory, for example:
   - `CONFIG_ROOT=$HOME/portable-media-stack/config`
   - `DOWNLOADS_PATH=$HOME/downloads`
   - `MOVIES_PATH=$HOME/media/movies`
   - `TV_PATH=$HOME/media/tv`
5. If you exported bootstrap data from another machine, you can either fetch it with `./scripts/bootstrap-data/fetch-bootstrap-data.sh user@source-host` or restore the latest saved copy under `${HOME}/.local/share/portable-media-stack/bootstrap-data/`, then enable:
   - `AUTO_APPLY_BOOTSTRAP_DATA=true`
   - `BOOTSTRAP_DATA_FILE=${HOME}/.local/share/portable-media-stack/bootstrap-data/latest-bootstrap-data.json`

## Automating fresh Arr setup from your current stack

If you want a clean new install but want it to reuse your current Prowlarr indexers and SAB-compatible downloader wiring:

1. On the current working machine, run:

```bash
./scripts/bootstrap-data/export-bootstrap-data.sh
```

2. The export refreshes both:

```text
bootstrap-data/local/bootstrap-data.json
~/.local/share/portable-media-stack/bootstrap-data/latest-bootstrap-data.json
```

and also writes a timestamped archive copy under:

```text
~/.local/share/portable-media-stack/bootstrap-data/history/
```

3. On the new machine, the easiest transfer path is:

```bash
./scripts/bootstrap-data/fetch-bootstrap-data.sh user@source-host
```

That copies the saved `latest-bootstrap-data.json` from the source host into `./bootstrap-data/local/bootstrap-data.json` on the new machine.

4. In `.env`, enable:

```text
AUTO_APPLY_BOOTSTRAP_DATA=true
BOOTSTRAP_DATA_FILE=${HOME}/.local/share/portable-media-stack/bootstrap-data/latest-bootstrap-data.json
```

If that file is missing, `install.sh` also falls back automatically to:
- `${BOOTSTRAP_LIBRARY_DIR}/latest-bootstrap-data.json`
- `./bootstrap-data/local/bootstrap-data.json`

5. Run the install normally. After the fresh containers start, the stack will automatically:
- import Prowlarr indexers
- create a Sonarr app connection in Prowlarr
- create a Radarr app connection in Prowlarr
- create the configured SAB-compatible download client in Sonarr
- create the configured SAB-compatible download client in Radarr

If an exported indexer has bad or missing credentials, bootstrap apply will warn and skip that indexer instead of aborting the whole install. That lets the fresh stack still finish wiring Sonarr, Radarr, Prowlarr app sync, and the configured SAB-compatible downloader.

This is designed for a fresh single-Radarr install, not for copying old full app configs.

## Next setup tasks after first boot

- add Jellyfin libraries for movies and TV
- create DNS records only if you are using a Traefik DNS mode
