# DNS Notes

If you enable a Traefik mode, create DNS records that point at the machine running Traefik.

Typical records:
- jellyfin.example.com
- radarr.example.com
- sonarr.example.com
- prowlarr.example.com
- sabnzbd.example.com
- nzbdav.example.com
- traefik.example.com

For private-only use, prefer split DNS or tailnet-resolved names.
If you want a family-facing request portal but cannot forward 80/443 at the router, use `tailscale-funnel` to expose Seerr only instead of public Traefik DNS.

Important:
- Tailscale Funnel does not use your own public custom DNS records by default
- Funnel publishes through the tailnet's public `*.ts.net` names
- In the recommended `tailscale-funnel` mode, the public URL is `https://<stack-device>.<tailnet>.ts.net/` for Seerr.
- Do not create public DNS/Funnel routes for Arr applications, Jellyfin, Prowlarr, or NZBDAV; the standard setup keeps them private.
