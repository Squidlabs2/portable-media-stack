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


def api_get(base_url: str, key: str, endpoint: str):
    request = urllib.request.Request(
        f"{base_url.rstrip('/')}/api/v3/{endpoint.lstrip('/')}",
        headers={"X-Api-Key": key},
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.load(response)


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


def choose_directory(root_folders):
    preferred = env("SEERR_ROOT_FOLDER", "")
    if preferred:
        for folder in root_folders:
            if folder.get("path") == preferred:
                return preferred
        raise RuntimeError(f"Requested Seerr root folder not found: {preferred}")
    if not root_folders:
        raise RuntimeError("No Arr root folders are available")
    return root_folders[0]["path"]


def service_entry(kind, base_url, key):
    profile = choose_profile(api_get(base_url, key, "qualityprofile"))
    directory = choose_directory(api_get(base_url, key, "rootfolder"))
    common = {
        "name": "Movies" if kind == "radarr" else "Shows",
        "hostname": "127.0.0.1",
        "port": 7878 if kind == "radarr" else 8989,
        "useSsl": False,
        "baseUrl": "",
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
