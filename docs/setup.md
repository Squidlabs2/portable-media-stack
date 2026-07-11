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
