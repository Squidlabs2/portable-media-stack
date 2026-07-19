# Cloudflare Tunnel Mode

Use `MODE=cloudflare-tunnel` when a portable box should use your own domain but may be on a changing IP, behind CGNAT, or on a router you do not control.

Cloudflare Tunnel works through an outbound `cloudflared` connection, so the box does not need inbound 80/443, DDNS, or router port forwarding.

## Hostname pattern

With:

```text
PUBLIC_DOMAIN=myallbox.com
DEVICE_NAME=ethan
```

configure.sh generates:

```text
RADARR_HOST=ethan-movie.myallbox.com
SONARR_HOST=ethan-tv.myallbox.com
SEERR_HOST=ethan-seerr.myallbox.com
```

For another box, change only `DEVICE_NAME`.

## Cloudflare setup

In Cloudflare Zero Trust, create one tunnel per box and save that box's tunnel token only in its local `.env`:

```text
MODE=cloudflare-tunnel
PUBLIC_DOMAIN=myallbox.com
DEVICE_NAME=ethan
CLOUDFLARE_TUNNEL_TOKEN_FILE=./secrets/cloudflare-tunnel-token
```

Paste the token into that ignored local file, or paste it into the installer prompt so preflight writes the file with `0600` permissions. The Compose service reads the token through a mounted secret file instead of placing the token directly in the container command.

Then add Public Hostname routes for that tunnel:

```text
ethan-movie.myallbox.com  -> http://radarr:7878
ethan-tv.myallbox.com     -> http://sonarr:8989
ethan-seerr.myallbox.com  -> http://seerr:5055
```

Optional/private services can be added later, but do not expose Prowlarr, SABnzbd, or NZBDAV by default.

## Compose behavior

The installer adds `compose.cloudflare-tunnel.yml`, which starts a `cloudflared` container on both the internal `media` network and outbound `egress` network. That lets Cloudflare reach internal service names like `radarr`, `sonarr`, and `seerr`, while `cloudflared` can still make outbound connections to Cloudflare.

Tailscale can still stay installed on the host for private SSH/admin access, but Cloudflare Tunnel replaces Tailscale Funnel for public custom-domain ingress.
