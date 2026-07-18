# Setup Notes

1. Install Docker Engine and Docker Compose plugin.
2. Install Tailscale on the host.
3. Join the machine to your tailnet.
4. Run `scripts/install.sh` or `scripts/bootstrap.sh`.
5. Configure app credentials inside the web UIs after first boot.

Recommended defaults:
- keep Radarr, Sonarr, and Prowlarr tailnet-only unless you need friendly DNS names
- use Traefik only when you want hostname-based routing
- keep downloads and media paths stable across machines when possible
- for NZBDAV setups, use `ENABLE_NZBDAV=true` and `ENABLE_SABNZBD=false`
- use `ENABLE_SEERR=true` for the family-facing request portal
- Sonarr's root folder inside the container is `/tv`; Radarr's is `/movies`
- NZBDAV completed downloads should be under `/downloads/nzbdav-completed/<category>` and are prepared by `scripts/configure-nzbdav-paths.sh`
