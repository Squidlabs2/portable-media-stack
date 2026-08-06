#!/usr/bin/env python3
"""Apply the portable stack's default Radarr quality policy after first start."""
import http.client
import os
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path


def blocked(name):
    name = name.lower()
    return "2160" in name or "4k" in name or "remux" in name


def apply_high_quality_1080p_policy(definitions, profiles, max_mb_per_minute):
    changed_definitions = []
    for definition in definitions:
        item = dict(definition)
        name = item.get("quality", {}).get("name", "")
        item["maxSize"] = 0 if blocked(name) else max_mb_per_minute
        changed_definitions.append(item)
    changed_profiles = []
    for profile in profiles:
        item = dict(profile)
        item["items"] = [dict(q, allowed=False if blocked(q.get("quality", {}).get("name", "")) else q.get("allowed", True)) for q in profile.get("items", [])]
        changed_profiles.append(item)
    return changed_definitions, changed_profiles


def request_json(url, key, method="GET", payload=None):
    data = None if payload is None else __import__("json").dumps(payload).encode()
    request = urllib.request.Request(url, data=data, method=method, headers={"X-Api-Key": key, "Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return __import__("json").loads(response.read() or b"null")


def main():
    if os.environ.get("RADARR_QUALITY_POLICY", "high-quality-1080p") != "high-quality-1080p":
        return
    config = Path(os.environ.get("RADARR_CONFIG", "./config/radarr")) / "config.xml"
    for _ in range(60):
        if config.exists():
            break
        time.sleep(2)
    else:
        raise RuntimeError(f"Timed out waiting for {config}")
    key = ET.parse(config).getroot().findtext("ApiKey")
    url = f"http://127.0.0.1:{os.environ.get('RADARR_PORT', '7878')}/api/v3"
    for attempt in range(30):
        try:
            definitions = request_json(f"{url}/qualitydefinition", key)
            profiles = request_json(f"{url}/qualityprofile", key)
            break
        except (OSError, urllib.error.URLError, http.client.HTTPException) as error:
            if attempt == 29:
                raise RuntimeError("Radarr did not become ready within 60 seconds") from error
            time.sleep(2)
    definitions, profiles = apply_high_quality_1080p_policy(definitions, profiles, int(os.environ.get("RADARR_MAX_MB_PER_MINUTE", "100")))
    for item in definitions:
        request_json(f"{url}/qualitydefinition/{item['id']}", key, "PUT", item)
    for item in profiles:
        request_json(f"{url}/qualityprofile/{item['id']}", key, "PUT", item)
    print("Applied Radarr high-quality 1080p policy")

if __name__ == "__main__":
    main()
