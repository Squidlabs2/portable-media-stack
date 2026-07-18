# Traefik Notes

Use Traefik only on hosts where public/private DNS hostname routing is actually needed.

The stack supports two Traefik patterns.

## 1. Bundled Traefik

Set `INSTALL_TRAEFIK=true`.
This is the easiest path for new machines that can receive web traffic directly.

What it does:
- runs Traefik in the same Compose project
- publishes ports 80 and 443 by default
- stores ACME state in `${TRAEFIK_CONFIG_DIR}`
- enables the dashboard at `https://${TRAEFIK_DASHBOARD_HOST}`
- routes Jellyfin, Radarr, Sonarr, Prowlarr, Seerr, SABnzbd, and optional NZBDAV by hostname

## 2. External Traefik

Set `INSTALL_TRAEFIK=false`.
This assumes another Traefik instance already exists on the host and is attached to an external Docker network named by `PROXY_NETWORK`.

## Modes

- `tailnet-only`: no Traefik overlay
- `tailscale-funnel`: no Traefik required; public access comes from Tailscale Funnel instead
- `traefik-private-dns`: Traefik enabled, intended for private/split DNS names
- `traefik-public-dns`: Traefik enabled, intended for public DNS and TLS

## Operational notes

- Tailscale remains host-level; Traefik does not replace Tailnet access.
- SSH access remains host-level and unaffected.
- For public Radarr/Sonarr exposure on hosts without port forwarding, prefer `tailscale-funnel` over Traefik.
- Bundled Traefik uses Let's Encrypt HTTP challenge, so ports 80 and 443 must be reachable for public certificate issuance.
