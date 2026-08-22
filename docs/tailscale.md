# Tailscale Notes

This stack always requires host Tailscale for SSH and host administration. In the recommended `tailscale-funnel` mode, it also runs a separate Tailscale container for the media stack.

The dedicated container has its own persisted identity and shares its network namespace with the media services. This keeps application ports off the host while preserving host-level SSH administration.

Supported access patterns:
- `tailnet-only`: apps are reachable only from devices on your tailnet
- `tailscale-funnel`: private services use the dedicated stack identity; Funnel publishes only Seerr at the root URL without router port forwarding

Notes for Funnel mode:
- the host stays on Tailscale for SSH/admin
- the stack has a separate Tailscale identity and persisted state
- public URLs use your tailnet's `*.ts.net` naming
- supported public Funnel ports are 443, 8443, and 10000
- the default installer preset configures Funnel only for Seerr at HTTPS 443 and `/`
- Radarr, Sonarr, Jellyfin, Prowlarr, NZBDAV, Docker, and administration remain private

Verified public URL shape:

```text
https://<stack-device>.<tailnet>.ts.net/
```

Seerr must use `/`, not `/seerr`, because its Next.js assets and redirects are not reliable behind a subpath proxy.

If Funnel status shows multiple hostnames, test the specific hostname printed as the "Available on the internet" URL after rerunning `./scripts/ingress/configure-funnel.sh`. Old names can remain visible in status but fail externally.
