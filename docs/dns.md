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
If you want public Radarr/Sonarr access but cannot forward 80/443 at the router, use `tailscale-funnel` instead of public Traefik DNS.

Important:
- Tailscale Funnel does not use your own public custom DNS records by default
- Funnel publishes through the tailnet's public `*.ts.net` names
- In `tailscale-funnel` mode, the useful URLs are path-based Funnel URLs such as `https://<device>.<tailnet>.ts.net/radarr` and `https://<device>.<tailnet>.ts.net/sonarr`.
- Do not create or expose an NZBDAV public DNS/Funnel route unless you explicitly want its UI/API public. The verified NZBDAV setup keeps it private.
