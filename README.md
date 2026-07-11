# Portable Media Stack

Portable Docker Compose stack for Jellyfin, Radarr, Sonarr, Prowlarr, SABnzbd, and optional NZBDAV.

Goals:
- easy to deploy on multiple machines
- GitHub as the source of truth
- one-line bootstrap support
- machine-specific config kept local in `.env`
- Tailscale-first networking with optional public exposure modes
- optional bundled Traefik for self-contained installs on hosts that can receive 80/443

## Quick start

Recommended install:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Squidlabs2/portable-media-stack/main/scripts/bootstrap.sh)
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

Yes: the installer asks configuration questions during setup and writes the answers to the local `.env` file.

## Deployment modes

- `tailnet-only`: publish app ports on the host and access them only over Tailscale.
- `tailscale-funnel`: keep the machine on Tailscale but expose selected apps publicly through Tailscale Funnel without router port forwarding.
- `traefik-private-dns`: add Traefik labels and hostnames for friendly private DNS names.
- `traefik-public-dns`: same as above, but intended for public DNS and TLS on hosts that can actually receive 80/443.

## Tailscale Funnel mode

`tailscale-funnel` is the right fit when:
- the machine stays on your tailnet
- you still want SSH and private admin access over Tailscale
- the router cannot forward 80/443
- you want public access to Radarr or Sonarr anyway

Installer prompts cover:
- whether to auto-configure Funnel during install
- whether to expose Radarr
- whether to expose Sonarr
- whether to expose Jellyfin
- which public Funnel ports to use (443, 8443, 10000)

Recommended defaults for your use case:
- `AUTO_CONFIGURE_FUNNEL=true`
- `FUNNEL_RADARR=true`
- `FUNNEL_SONARR=true`
- `FUNNEL_JELLYFIN=false`
- `FUNNEL_RADARR_PUBLIC_PORT=443`
- `FUNNEL_SONARR_PUBLIC_PORT=8443`
- `FUNNEL_JELLYFIN_PUBLIC_PORT=10000`
- `INSTALL_TRAEFIK=false`

The repo includes `scripts/configure-funnel.sh`, which can apply the Funnel config later.
When Funnel auto-config is enabled, the installer now prints the expected public mapping and the Funnel helper/status output prints likely public URLs based on the machine's tailnet DNS name.

## Traefik options

- `INSTALL_TRAEFIK=true`: run a bundled Traefik container in this stack.
- `INSTALL_TRAEFIK=false`: reuse an existing Traefik instance and external Docker `proxy` network.

Bundled Traefik is the default for Traefik modes because it makes fresh-machine installs easier.

## Files

- `compose.yml` - base app stack
- `compose.traefik.yml` - Traefik labels shared by both Traefik setups
- `compose.traefik-bundled.yml` - bundled Traefik service
- `compose.traefik-external.yml` - external proxy network for an existing Traefik host
- `.env.example` - template for local `.env`
- `scripts/bootstrap.sh` - one-liner entrypoint
- `scripts/install.sh` - orchestrates setup
- `scripts/configure.sh` - generates `.env`
- `scripts/configure-funnel.sh` - applies Tailscale Funnel config from `.env`
- `scripts/export-bootstrap-data.sh` - exports reusable indexer/downloader seed data from a live stack
- `scripts/apply-bootstrap-data.sh` - applies reusable indexer/downloader seed data to a fresh install
- `scripts/preflight.sh` - validates prerequisites and prepares Traefik ACME storage
- `scripts/create-networks.sh` - creates external Docker networks when needed
- `scripts/update.sh` - pulls repo and refreshes containers

## Notes

- Real secrets and machine-specific values stay out of git.
- `.env` is created locally during install.
- `bootstrap-data/local/bootstrap-data.json` is local-only and ignored by git because it can contain API keys and indexer credentials.
- `bootstrap.sh` is intentionally small; all real logic lives in versioned repo scripts.
- Tailscale stays on the host; SSH and other host access remain independent of this stack.
- For public Radarr/Sonarr exposure, use strong app credentials.
- Tailscale Funnel uses your tailnet's `*.ts.net` naming, not your own custom public CNAMEs.

## Automating fresh Arr setup from your current stack

If you want a clean new install but want it to reuse your current Prowlarr indexers and SABnzbd wiring:

1. On the current working machine, run:

```bash
./scripts/export-bootstrap-data.sh
```

2. Keep the generated local-only file at:

```text
bootstrap-data/local/bootstrap-data.json
```

3. On the new machine, set these in `.env`:

```text
AUTO_APPLY_BOOTSTRAP_DATA=true
BOOTSTRAP_DATA_FILE=./bootstrap-data/local/bootstrap-data.json
```

4. Run the install normally. After the fresh containers start, the stack will automatically:
- import Prowlarr indexers
- create a Sonarr app connection in Prowlarr
- create a Radarr app connection in Prowlarr
- create the SABnzbd download client in Sonarr
- create the SABnzbd download client in Radarr

If an exported indexer has bad or missing credentials, bootstrap apply will warn and skip that indexer instead of aborting the whole install. That lets the fresh stack still finish wiring Sonarr, Radarr, Prowlarr app sync, and SABnzbd.

This is designed for a fresh single-Radarr install, not for copying old full app configs.

## Next setup tasks after first boot

- add Jellyfin libraries for movies and TV
- create DNS records only if you are using a Traefik DNS mode
