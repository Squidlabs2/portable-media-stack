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
- `scripts/preflight.sh` - validates prerequisites and prepares Traefik ACME storage
- `scripts/create-networks.sh` - creates external Docker networks when needed
- `scripts/update.sh` - pulls repo and refreshes containers

## Notes

- Real secrets and machine-specific values stay out of git.
- `.env` is created locally during install.
- `bootstrap.sh` is intentionally small; all real logic lives in versioned repo scripts.
- Tailscale stays on the host; SSH and other host access remain independent of this stack.
- For public Radarr/Sonarr exposure, use strong app credentials.
- Tailscale Funnel uses your tailnet's `*.ts.net` naming, not your own custom public CNAMEs.

## Next setup tasks after first boot

- configure SABnzbd server credentials
- connect Prowlarr to indexers
- connect Prowlarr to Radarr and Sonarr
- connect SABnzbd as the download client in Radarr and Sonarr
- add Jellyfin libraries for movies and TV
- create DNS records only if you are using a Traefik DNS mode
