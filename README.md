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

Fresh Debian host prep + install:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Squidlabs2/portable-media-stack/main/scripts/bootstrap.sh) --prepare-host
```

That Debian host prep path will:
- run `apt-get update`
- run `apt-get upgrade -y` by default
- install `curl`, `git`, `bash`, `python3`, and apt/GPG prerequisites
- install Docker Engine and the Docker Compose plugin
- install Tailscale and start `tailscaled`
- add the current non-root user to the `docker` group
- then continue into the normal stack installer

Useful host-prep variants:

```bash
# prepare host but skip full apt upgrade
bash <(curl -fsSL https://raw.githubusercontent.com/Squidlabs2/portable-media-stack/main/scripts/bootstrap.sh) --prepare-host --skip-upgrade

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

Manual two-step fresh Debian flow:

```bash
./scripts/prepare-host-debian.sh
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
- whether to use one hostname with path-based URLs
- whether to expose Radarr
- whether to expose Sonarr
- whether to expose Jellyfin
- which public Funnel paths to use for Radarr/Sonarr when path-based mode is enabled
- which public Funnel ports to use when path-based mode is disabled

Recommended defaults for your use case:
- `AUTO_CONFIGURE_FUNNEL=true`
- `FUNNEL_USE_PATHS=true`
- `FUNNEL_RADARR=true`
- `FUNNEL_SONARR=true`
- `FUNNEL_JELLYFIN=false`
- `FUNNEL_RADARR_PUBLIC_PORT=443`
- `FUNNEL_SONARR_PUBLIC_PORT=443`
- `FUNNEL_JELLYFIN_PUBLIC_PORT=10000`
- `FUNNEL_RADARR_PATH=/radarr`
- `FUNNEL_SONARR_PATH=/sonarr`
- `INSTALL_TRAEFIK=true`
- `TRAEFIK_FUNNEL_PORT=8088`

The repo includes `scripts/configure-funnel.sh`, which can apply the Funnel config later.
When Funnel auto-config is enabled, the installer now prints the expected public mapping and the Funnel helper/status output prints likely public URLs based on the machine's tailnet DNS name.

Path-based Funnel URLs look like:
- `https://<device>.<tailnet>.ts.net/radarr`
- `https://<device>.<tailnet>.ts.net/sonarr`

The installer also updates Radarr and Sonarr `UrlBase` automatically when path-based Funnel mode is enabled.
For Arr apps, the recommended path-based Funnel architecture is bundled Traefik listening on a local high port behind Funnel; Funnel points `/radarr` and `/sonarr` at Traefik, and Traefik strips the prefix before proxying upstream.
In Funnel mode, the bundled Traefik front door now uses a generated file-provider config rather than Traefik's Docker provider.

## Traefik options

- `INSTALL_TRAEFIK=true`: run a bundled Traefik container in this stack.
- `INSTALL_TRAEFIK=false`: reuse an existing Traefik instance and external Docker `proxy` network.

Bundled Traefik is the default for Traefik modes because it makes fresh-machine installs easier.

## Files

- `compose.yml` - base app stack
- `compose.traefik.yml` - Traefik labels shared by both Traefik setups
- `compose.traefik-bundled.yml` - bundled Traefik service
- `compose.traefik-external.yml` - external proxy network for an existing Traefik host
- `compose.funnel-traefik.yml` - Traefik path-routing labels for Funnel mode
- `compose.funnel-traefik-bundled.yml` - bundled Traefik service bound to a local high port for Funnel mode
- `.env.example` - template for local `.env`
- `scripts/bootstrap.sh` - one-liner entrypoint
- `scripts/prepare-host-debian.sh` - optional Debian host prep for Docker, Compose, and Tailscale
- `scripts/install.sh` - orchestrates setup
- `scripts/configure.sh` - generates `.env`
- `scripts/configure-arr-url-bases.sh` - sets Radarr/Sonarr UrlBase for path-based Funnel URLs
- `scripts/configure-funnel.sh` - applies Tailscale Funnel config from `.env`
- `scripts/write-funnel-traefik-config.sh` - generates the bundled Traefik dynamic config used behind Funnel path routes
- `scripts/export-bootstrap-data.sh` - exports reusable indexer/downloader seed data from a live stack
- `scripts/fetch-bootstrap-data.sh` - pulls the latest saved bootstrap artifact from another machine over SSH
- `scripts/apply-bootstrap-data.sh` - applies reusable indexer/downloader seed data to a fresh install
- `scripts/configure-sab-paths.sh` - normalizes SABnzbd download directories to the mounted `/downloads` path and restarts SAB if a legacy default is detected
- `scripts/preflight.sh` - validates prerequisites and prepares Traefik ACME storage
- `scripts/create-networks.sh` - creates external Docker networks when needed
- `scripts/update.sh` - pulls repo and refreshes containers

## Notes

- Real secrets and machine-specific values stay out of git.
- `.env` is created locally during install.
- `bootstrap-data/local/bootstrap-data.json` is local-only and ignored by git because it can contain API keys and indexer credentials.
- `./scripts/export-bootstrap-data.sh` also refreshes a reusable bootstrap library under `${HOME}/.local/share/portable-media-stack/bootstrap-data/`, including `latest-bootstrap-data.json` plus timestamped history copies for future machines.
- `bootstrap.sh` is intentionally small; all real logic lives in versioned repo scripts.
- `scripts/prepare-host-debian.sh` is Debian-only and optional; use it on fresh machines that still need Docker/Tailscale installed.
- Tailscale stays on the host; SSH and other host access remain independent of this stack.
- For public Radarr/Sonarr exposure, use strong app credentials.
- Tailscale Funnel uses your tailnet's `*.ts.net` naming, not your own custom public CNAMEs.

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
5. If you exported bootstrap data from another machine, you can either fetch it with `./scripts/fetch-bootstrap-data.sh user@source-host` or restore the latest saved copy under `${HOME}/.local/share/portable-media-stack/bootstrap-data/`, then enable:
   - `AUTO_APPLY_BOOTSTRAP_DATA=true`
   - `BOOTSTRAP_DATA_FILE=${HOME}/.local/share/portable-media-stack/bootstrap-data/latest-bootstrap-data.json`

## Automating fresh Arr setup from your current stack

If you want a clean new install but want it to reuse your current Prowlarr indexers and SABnzbd wiring:

1. On the current working machine, run:

```bash
./scripts/export-bootstrap-data.sh
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
./scripts/fetch-bootstrap-data.sh user@source-host
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
- create the SABnzbd download client in Sonarr
- create the SABnzbd download client in Radarr

If an exported indexer has bad or missing credentials, bootstrap apply will warn and skip that indexer instead of aborting the whole install. That lets the fresh stack still finish wiring Sonarr, Radarr, Prowlarr app sync, and SABnzbd.

This is designed for a fresh single-Radarr install, not for copying old full app configs.

## Next setup tasks after first boot

- add Jellyfin libraries for movies and TV
- create DNS records only if you are using a Traefik DNS mode
