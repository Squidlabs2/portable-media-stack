# Tailscale Notes

This stack assumes Tailscale runs on the host, not inside Docker.

Why:
- simpler operational model
- easier host access to published app ports
- avoids mixing overlay routing into the application stack

Supported access patterns:
- `tailnet-only`: apps are reachable only from devices on your tailnet
- `tailscale-funnel`: selected apps are still hosted on the tailnet machine but are published publicly through Tailscale Funnel without router port forwarding

Notes for Funnel mode:
- the host still stays on Tailscale
- SSH remains host-level and unchanged
- public URLs use your tailnet's `*.ts.net` naming
- supported public Funnel ports are 443, 8443, and 10000
- the installer can ask whether to auto-configure Funnel for Radarr, Sonarr, and Jellyfin
- for path-based Radarr/Sonarr, keep bundled Traefik on the local high port and point Funnel paths at Traefik, not directly at the Arr containers
- expose only the services you intend to publish; the verified NZBDAV setup keeps NZBDAV private and publishes only `/radarr` and `/sonarr`

Verified public URL shape:

```text
https://<device>.<tailnet>.ts.net/radarr
https://<device>.<tailnet>.ts.net/sonarr
```

The current test machine's working Funnel hostname was:

```text
https://ethan.wolverine-crocodile.ts.net/radarr
https://ethan.wolverine-crocodile.ts.net/sonarr
```

If Funnel status shows multiple hostnames, test the specific hostname printed as the "Available on the internet" URL after rerunning `./scripts/configure-funnel.sh`. Old names can remain visible in status but fail externally.
