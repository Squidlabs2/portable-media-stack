#!/usr/bin/env python3
"""Register local Radarr and Sonarr in Seerr after its first-run setup."""
import json
import os
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path


def env(name, default=""):
    return os.environ.get(name, default)


def api_key(config_dir: Path) -> str:
    root = ET.parse(config_dir / "config.xml").getroot()
    key = root.findtext("ApiKey", "").strip()
    if not key:
        raise RuntimeError(f"No ApiKey found in {config_dir / 'config.xml'}")
    return key


def api_request(base_url: str, key: str, endpoint: str, *, method="GET", payload=None):
    body = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(
        f"{base_url.rstrip('/')}/api/v3/{endpoint.lstrip('/')}",
        data=body,
        method=method,
        headers={"X-Api-Key": key, "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.load(response) if response.length != 0 else None


def api_get(base_url: str, key: str, endpoint: str):
    return api_request(base_url, key, endpoint)


def choose_profile(profiles):
    preferred = env("SEERR_QUALITY_PROFILE", "")
    if preferred:
        for profile in profiles:
            if profile.get("name") == preferred:
                return profile
        raise RuntimeError(f"Requested Seerr quality profile not found: {preferred}")
    if not profiles:
        raise RuntimeError("No Arr quality profiles are available")
    return profiles[0]


def ensure_directory(base_url: str, key: str, desired: str):
    folders = api_get(base_url, key, "rootfolder") or []
    if not any(folder.get("path") == desired for folder in folders):
        api_request(base_url, key, "rootfolder", method="POST", payload={"path": desired})
        folders = api_get(base_url, key, "rootfolder") or []
    if not any(folder.get("path") == desired for folder in folders):
        raise RuntimeError(f"Arr did not create expected root folder: {desired}")
    return desired


def service_entry(kind, base_url, key):
    profile = choose_profile(api_get(base_url, key, "qualityprofile"))
    default_directory = "/movies" if kind == "radarr" else "/tv"
    directory = ensure_directory(
        base_url,
        key,
        env(f"SEERR_{kind.upper()}_ROOT_FOLDER", default_directory),
    )
    common = {
        "name": "Movies" if kind == "radarr" else "Shows",
        "hostname": "127.0.0.1",
        "port": 7878 if kind == "radarr" else 8989,
        "useSsl": False,
        "baseUrl": "",
        "apiKey": key,
        "activeProfileId": profile["id"],
        "activeProfileName": profile["name"],
        "activeDirectory": directory,
        "tags": [],
        "is4k": False,
        "isDefault": True,
        "syncEnabled": True,
        "preventSearch": False,
        "tagRequests": False,
        "id": 0,
    }
    if kind == "radarr":
        common["minimumAvailability"] = "released"
    else:
        common.update({"animeTags": [], "enableSeasonFolders": False, "monitorNewItems": "all"})
    return common


def main():
    seerr_settings = Path(env("SEERR_CONFIG", "/config/seerr")) / "settings.json"
    if not seerr_settings.is_file():
        raise RuntimeError("Seerr settings.json is missing; finish the Seerr first-run wizard before configuring Arr services")

    radarr_dir = Path(env("RADARR_CONFIG", "/config/radarr"))
    sonarr_dir = Path(env("SONARR_CONFIG", "/config/sonarr"))
    radarr = service_entry("radarr", env("RADARR_URL", "http://127.0.0.1:7878"), api_key(radarr_dir))
    sonarr = service_entry("sonarr", env("SONARR_URL", "http://127.0.0.1:8989"), api_key(sonarr_dir))

    settings = json.loads(seerr_settings.read_text())
    settings["radarr"] = [radarr]
    settings["sonarr"] = [sonarr]
    seerr_settings.write_text(json.dumps(settings, indent=2) + "\n")
    print(f"Configured Seerr Radarr: profile={radarr['activeProfileName']!r} root={radarr['activeDirectory']!r}")
    print(f"Configured Seerr Sonarr: profile={sonarr['activeProfileName']!r} root={sonarr['activeDirectory']!r}")


if __name__ == "__main__":
    main()
