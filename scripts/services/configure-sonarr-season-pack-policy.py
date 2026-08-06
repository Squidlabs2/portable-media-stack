#!/usr/bin/env python3
"""Block full-season releases in Sonarr profiles."""
import json, os, time, urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

NAME = "Squid Block Season Packs"
REGEX = r"(?i)(?:\bS\d{1,2}\b(?!\s*E)|\bseason\s*\d{1,2}\b|\bcomplete\s+season\b)"

def request(url, key, method="GET", payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, headers={"X-Api-Key": key, "Content-Type": "application/json"}, method=method)
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response) if response.length != 0 else {}

def main():
    config = Path(os.environ.get("SONARR_CONFIG", "./config/sonarr")) / "config.xml"
    for _ in range(30):
        if config.exists(): break
        time.sleep(2)
    root = ET.parse(config).getroot(); key = root.findtext("ApiKey"); base = (root.findtext("UrlBase") or "").rstrip("/")
    url = f"http://127.0.0.1:{os.environ.get('SONARR_PORT', '8989')}{base}/api/v3"
    formats = request(url + "/customformat", key)
    fmt = next((x for x in formats if x.get("name") == NAME), None)
    if not fmt:
        fmt = request(url + "/customformat", key, "POST", {"name": NAME, "includeCustomFormatWhenRenaming": False, "specifications": [{"name": "Release Title", "implementation": "ReleaseTitleSpecification", "negate": False, "required": False, "fields": [{"name": "value", "value": REGEX}]}]})
    for profile in request(url + "/qualityprofile", key):
        items = [x for x in profile.get("formatItems", []) if x.get("format") != fmt["id"]]
        items.append({"format": fmt["id"], "name": NAME, "score": -10000})
        profile["formatItems"] = items
        profile["minFormatScore"] = max(profile.get("minFormatScore", 0), 0)
        request(url + f"/qualityprofile/{profile['id']}/", key, "PUT", profile)
    print("Applied Sonarr individual-episode policy")

if __name__ == "__main__": main()
