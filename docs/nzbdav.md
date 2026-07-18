# NZBDAV Notes

NZBDAV is the preferred downloader-style component for this stack. It speaks a SAB-compatible API, so Radarr and Sonarr may still show the download-client implementation/name as `SABnzbd`. That is expected: the endpoint should point at NZBDAV, not the real SABnzbd container.

## Recommended target settings

For an NZBDAV-based install:

```text
ENABLE_NZBDAV=true
ENABLE_SABNZBD=false
TARGET_INTERNAL_NZBDAV_HOST=nzbdav
TARGET_INTERNAL_NZBDAV_PORT=3000
TARGET_NZBDAV_COMPLETED_DOWNLOADS_DIR=/downloads/nzbdav-completed
NZBDAV_COMPLETED_CATEGORIES=movies,tv,audio,software
```

NZBDAV should stay private unless explicitly exposed. In the tested Funnel setup, only Radarr and Sonarr are exposed through public paths; NZBDAV is not routed through Funnel/Traefik.

## Volumes and paths

All download-related containers mount the same host downloads directory at `/downloads`:

- Radarr: `/downloads`
- Sonarr: `/downloads`
- NZBDAV: `/downloads`

NZBDAV completed paths are category subdirectories under `/downloads/nzbdav-completed`, for example:

```text
/downloads/nzbdav-completed/movies
/downloads/nzbdav-completed/tv
```

The host-side path is `${DOWNLOADS_PATH}/nzbdav-completed/<category>`.

`scripts/configure-nzbdav-paths.sh` creates these category directories during install/update when `ENABLE_NZBDAV=true`. It refuses completed-download paths outside `/downloads`, because Radarr/Sonarr/NZBDAV must all see the same mounted path.

## Sonarr and Radarr library root folders

Inside the containers, use these root folders:

```text
Sonarr TV root folder: /tv
Radarr movies root folder: /movies
```

Downloads are separate and should remain under `/downloads`.

## Verification checklist

After install/update, verify:

```bash
# NZBDAV container is running
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep nzbdav

# Completed paths exist inside the app containers
docker exec portable-media-stack_sonarr test -d /downloads/nzbdav-completed/tv
docker exec portable-media-stack_radarr test -d /downloads/nzbdav-completed/movies

# Arr health should not contain Docker remote-path warnings for nzbdav-completed
```

If Arr still shows the path warning after the directories exist and are writable, restart the affected Arr container once so it refreshes its cached health check.
