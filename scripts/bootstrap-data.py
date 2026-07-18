#!/usr/bin/env python3
import argparse
import configparser
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
DEFAULT_BOOTSTRAP_LIBRARY_DIR = Path.home() / ".local/share/portable-media-stack/bootstrap-data"

PROWLARR_ALLOWED_KEYS = {
    "appProfileId",
    "configContract",
    "enable",
    "fields",
    "implementation",
    "implementationName",
    "name",
    "priority",
    "protocol",
    "redirect",
    "tags",
}

APP_ALLOWED_KEYS = {
    "configContract",
    "enable",
    "fields",
    "implementation",
    "implementationName",
    "name",
    "syncLevel",
    "tags",
}

DOWNLOAD_CLIENT_ALLOWED_KEYS = {
    "configContract",
    "enable",
    "fields",
    "implementation",
    "implementationName",
    "name",
    "priority",
    "protocol",
    "removeCompletedDownloads",
    "removeFailedDownloads",
    "tags",
}


def env(name: str, default: str) -> str:
    return os.environ.get(name, default)


def read_api_key(config_path: str) -> str:
    root = ET.parse(config_path).getroot()
    key = root.findtext("ApiKey")
    if not key:
        raise RuntimeError(f"Missing ApiKey in {config_path}")
    return key


def read_url_base(config_path: str) -> str:
    root = ET.parse(config_path).getroot()
    value = (root.findtext("UrlBase") or "").strip()
    if not value:
        return ""
    if not value.startswith("/"):
        value = f"/{value}"
    return value.rstrip("/")


def read_ini_value(config_path: str, key_name: str) -> str:
    for line in Path(config_path).read_text().splitlines():
        if line.startswith(f"{key_name} ="):
            return line.split("=", 1)[1].strip().strip('"')
    raise RuntimeError(f"Missing {key_name} in {config_path}")


def read_sab_ini(config_path: str) -> configparser.ConfigParser:
    def lower_optionstr(optionstr: str) -> str:
        return optionstr.lower()

    parser = configparser.ConfigParser(interpolation=None)
    parser.optionxform = lower_optionstr
    parser.read_string("[root]\n" + Path(config_path).read_text())
    return parser


def export_usenet_providers_from_sab(config_path: str):
    parser = read_sab_ini(config_path)
    providers = []
    for section in parser.sections():
        if not (section.startswith("[") and section.endswith("]")):
            continue
        server = parser[section]
        if server.get("host") and server.get("enable", "1") != "0":
            providers.append(
                {
                    "Type": 1,
                    "Host": server.get("host", ""),
                    "Port": int(server.get("port", "563") or 563),
                    "UseSsl": server.get("ssl", "1") == "1",
                    "User": server.get("username", ""),
                    "Pass": server.get("password", ""),
                    "MaxConnections": int(server.get("connections", "20") or 20),
                }
            )
    if not providers:
        raise RuntimeError(f"No enabled SABnzbd servers found in {config_path}")
    return providers


def http_json(url: str, api_key: str, method: str = "GET", payload=None):
    body = None
    headers = {"X-Api-Key": api_key}
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=30) as response:
        raw = response.read()
        if not raw:
            return None
        return json.loads(raw)


def http_error_details(exc: urllib.error.HTTPError) -> str:
    try:
        body = exc.read().decode("utf-8", "ignore").strip()
    except Exception:
        body = ""
    return body or str(exc.reason)


def sanitize_fields(fields):
    sanitized = []
    for field in fields:
        sanitized.append(
            {
                key: field.get(key)
                for key in (
                    "advanced",
                    "helpText",
                    "isFloat",
                    "label",
                    "name",
                    "order",
                    "placeholder",
                    "privacy",
                    "type",
                    "value",
                )
                if key in field
            }
        )
    return sanitized


def sanitize_item(item, allowed_keys):
    sanitized = {key: item.get(key) for key in allowed_keys if key in item}
    if "fields" in sanitized:
        sanitized["fields"] = sanitize_fields(sanitized["fields"])
    return sanitized


def pick_first(items, *, implementation_name):
    matches = [item for item in items if item.get("implementationName") == implementation_name]
    if not matches:
        raise RuntimeError(f"No item found for implementationName={implementation_name}")
    enabled = [item for item in matches if item.get("enable")]
    return enabled[0] if enabled else matches[0]


def set_field_value(fields, field_name, value):
    for field in fields:
        if field.get("name") == field_name:
            field["value"] = value
            return
    raise RuntimeError(f"Field {field_name} not found")


def get_field_value(fields, field_name, default=None):
    for field in fields:
        if field.get("name") == field_name:
            return field.get("value", default)
    return default


def read_prowlarr_indexer_settings(db_path: Path):
    conn = sqlite3.connect(db_path)
    try:
        cur = conn.cursor()
        cur.execute("select Id, Name, Settings from Indexers")
        by_id = {}
        by_name = {}
        for idx, name, settings_json in cur.fetchall():
            settings = json.loads(settings_json or "{}")
            by_id[idx] = settings
            by_name[name] = settings
        return by_id, by_name
    finally:
        conn.close()


def enrich_indexer_fields_from_db(indexers, db_path: Path):
    by_id, by_name = read_prowlarr_indexer_settings(db_path)
    for indexer in indexers:
        settings = by_id.get(indexer.get("id")) or by_name.get(indexer.get("name")) or {}
        for field in indexer.get("fields", []):
            field_name = field.get("name")
            if field_name in settings and settings[field_name] not in (None, ""):
                field["value"] = settings[field_name]
    return indexers


def bootstrap_library_paths():
    library_dir_raw = env("BOOTSTRAP_LIBRARY_DIR", str(DEFAULT_BOOTSTRAP_LIBRARY_DIR)).strip()
    if not library_dir_raw:
        return None, None, None
    library_dir = Path(os.path.expanduser(library_dir_raw))
    latest_path = library_dir / "latest-bootstrap-data.json"
    archive_path = library_dir / "history" / f"bootstrap-data-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}.json"
    return library_dir, latest_path, archive_path


def write_bootstrap_library_copies(output_path: Path):
    library_dir, latest_path, archive_path = bootstrap_library_paths()
    if library_dir is None or latest_path is None or archive_path is None:
        return
    latest_path.parent.mkdir(parents=True, exist_ok=True)
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(output_path, latest_path)
    shutil.copy2(output_path, archive_path)
    print(f"Updated bootstrap library latest copy: {latest_path}")
    print(f"Archived bootstrap library copy: {archive_path}")


def export_data(output_path: Path):
    prowlarr_url = env("SOURCE_PROWLARR_URL", "http://127.0.0.1:9696")
    sonarr_url = env("SOURCE_SONARR_URL", "http://127.0.0.1:8989")
    radarr_url = env("SOURCE_RADARR_URL", "http://127.0.0.1:7979")

    prowlarr_key = read_api_key(env("SOURCE_PROWLARR_CONFIG_XML", "/media/dockerfiles/prowlarr/config.xml"))
    sonarr_key = read_api_key(env("SOURCE_SONARR_CONFIG_XML", "/media/dockerfiles/sonarr/config.xml"))
    radarr_key = read_api_key(env("SOURCE_RADARR_CONFIG_XML", "/media/dockerfiles/radarr/config.xml"))
    prowlarr_db = Path(env("SOURCE_PROWLARR_DB", str(Path(env("SOURCE_PROWLARR_CONFIG_XML", "/media/dockerfiles/prowlarr/config.xml")).with_name("prowlarr.db"))))
    source_sabnzbd_ini = env("SOURCE_SABNZBD_INI", "/media/dockerfiles/sabnzbd/sabnzbd.ini")

    prowlarr_indexers = http_json(f"{prowlarr_url}/api/v1/indexer", prowlarr_key) or []
    prowlarr_indexers = enrich_indexer_fields_from_db(prowlarr_indexers, prowlarr_db)
    prowlarr_apps = http_json(f"{prowlarr_url}/api/v1/applications", prowlarr_key) or []
    sonarr_clients = http_json(f"{sonarr_url}/api/v3/downloadclient", sonarr_key) or []
    radarr_clients = http_json(f"{radarr_url}/api/v3/downloadclient", radarr_key) or []

    sonarr_app_template = sanitize_item(pick_first(prowlarr_apps, implementation_name="Sonarr"), APP_ALLOWED_KEYS)
    radarr_app_template = sanitize_item(pick_first(prowlarr_apps, implementation_name="Radarr"), APP_ALLOWED_KEYS)
    sonarr_sab = sanitize_item(pick_first(sonarr_clients, implementation_name="SABnzbd"), DOWNLOAD_CLIENT_ALLOWED_KEYS)
    radarr_sab = sanitize_item(pick_first(radarr_clients, implementation_name="SABnzbd"), DOWNLOAD_CLIENT_ALLOWED_KEYS)
    usenet_providers = export_usenet_providers_from_sab(source_sabnzbd_ini)

    payload = {
        "version": 1,
        "exportedAt": datetime.now(timezone.utc).isoformat(),
        "source": {
            "prowlarrUrl": prowlarr_url,
            "sonarrUrl": sonarr_url,
            "radarrUrl": radarr_url,
            "indexerCount": len(prowlarr_indexers),
        },
        "prowlarr": {
            "indexers": [sanitize_item(item, PROWLARR_ALLOWED_KEYS) for item in prowlarr_indexers],
            "applicationTemplates": {
                "sonarr": sonarr_app_template,
                "radarr": radarr_app_template,
            },
        },
        "sonarr": {
            "downloadClient": sonarr_sab,
        },
        "radarr": {
            "downloadClient": radarr_sab,
        },
        "downloader": {
            "type": "sab-compatible",
            "usenetProviders": usenet_providers,
        },
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2) + "\n")
    print(f"Exported bootstrap data to {output_path}")
    write_bootstrap_library_copies(output_path)
    print(f"- Prowlarr indexers: {len(payload['prowlarr']['indexers'])}")
    print("- Prowlarr application templates: sonarr, radarr")
    print("- Download client templates: sonarr SABnzbd, radarr SABnzbd")


def wait_for_api(url: str, api_key: str, label: str, timeout_seconds: int):
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        try:
            http_json(url, api_key)
            print(f"Ready: {label}")
            return
        except Exception:
            time.sleep(2)
    raise RuntimeError(f"Timed out waiting for {label} at {url}")


def wait_for_sab_api(base_url: str, api_key: str, timeout_seconds: int):
    deadline = time.time() + timeout_seconds
    url = f"{base_url}/api?mode=version&output=json&apikey={api_key}"
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=30) as response:
                if response.status == 200:
                    print("Ready: SABnzbd")
                    return
        except Exception:
            time.sleep(2)
    raise RuntimeError(f"Timed out waiting for SABnzbd at {base_url}")


def wait_for_config(config_path: Path, timeout_seconds: int):
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        if config_path.exists() and config_path.stat().st_size > 0:
            return
        time.sleep(2)
    raise RuntimeError(f"Timed out waiting for config file {config_path}")


def ensure_sab_categories(config_path: Path, categories) -> bool:
    text = config_path.read_text()
    lines = text.splitlines()
    existing = set()
    has_categories_section = False
    for line in lines:
        stripped = line.strip()
        if stripped == "[categories]":
            has_categories_section = True
        if stripped.startswith("[[") and stripped.endswith("]]"
        ):
            existing.add(stripped[2:-2])

    missing = [category for category in categories if category and category not in existing and category != "*"]
    if not missing:
        return False

    order = len(existing)
    blocks = []
    for category in missing:
        blocks.append(
            "\n".join(
                [
                    f"[[{category}]]",
                    f"name = {category}",
                    f"order = {order}",
                    'pp = ""',
                    'script = Default',
                    'dir = ""',
                    'newzbin = ""',
                    'priority = -100',
                ]
            )
        )
        order += 1

    additions = []
    if not has_categories_section:
        additions.append("[categories]")
    additions.extend(blocks)
    config_path.write_text(text.rstrip() + "\n" + "\n".join(additions) + "\n")
    return True


def ensure_sab_host_whitelist(config_path: Path, hosts) -> bool:
    lines = config_path.read_text().splitlines()
    for idx, line in enumerate(lines):
        if not line.startswith("host_whitelist ="):
            continue
        current = [item.strip() for item in line.split("=", 1)[1].split(",") if item.strip()]
        updated = list(current)
        for host in hosts:
            if host and host not in updated:
                updated.append(host)
        if updated == current:
            return False
        lines[idx] = f"host_whitelist = {', '.join(updated)}"
        config_path.write_text("\n".join(lines) + "\n")
        return True
    lines.append(f"host_whitelist = {', '.join(host for host in hosts if host)}")
    config_path.write_text("\n".join(lines) + "\n")
    return True


def restart_sabnzbd():
    subprocess.run(["docker", "compose", "restart", "sabnzbd"], cwd=ROOT_DIR, check=True, stdout=subprocess.DEVNULL)


def restart_nzbdav():
    subprocess.run(["docker", "compose", "restart", "nzbdav"], cwd=ROOT_DIR, check=True, stdout=subprocess.DEVNULL)


def upsert_sqlite_config_items(db_path: Path, items):
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    try:
        cur = conn.cursor()
        for key, value in items.items():
            cur.execute(
                "insert into ConfigItems(ConfigName, ConfigValue) values(?, ?) on conflict(ConfigName) do update set ConfigValue=excluded.ConfigValue",
                (key, value),
            )
        conn.commit()
    finally:
        conn.close()


def read_nzbdav_api_key(db_path: Path) -> str:
    conn = sqlite3.connect(db_path)
    try:
        cur = conn.cursor()
        row = cur.execute("select ConfigValue from ConfigItems where ConfigName = 'api.key'").fetchone()
        if not row or not row[0]:
            raise RuntimeError(f"Missing api.key in {db_path}")
        return row[0]
    finally:
        conn.close()


def configure_nzbdav(db_path: Path, *, payload, internal_radarr_url: str, internal_sonarr_url: str, radarr_key: str, sonarr_key: str):
    import_strategy = env("TARGET_NZBDAV_IMPORT_STRATEGY", "strm")
    config_items = {
        "usenet.providers": json.dumps({"Providers": payload.get("downloader", {}).get("usenetProviders", [])}),
        "arr.instances": json.dumps(
            {
                "RadarrInstances": [{"Host": internal_radarr_url, "ApiKey": radarr_key}],
                "SonarrInstances": [{"Host": internal_sonarr_url, "ApiKey": sonarr_key}],
                "QueueRules": [],
            }
        ),
        "api.import-strategy": import_strategy,
        "api.categories": "movies,tv,audio,software",
    }

    if import_strategy == "strm":
        config_items["api.completed-downloads-dir"] = env("TARGET_NZBDAV_COMPLETED_DOWNLOADS_DIR", "/downloads/nzbdav-completed")
        config_items["general.base-url"] = env("TARGET_NZBDAV_BASE_URL", f"http://nzbdav:{env('NZBDAV_PORT', '3000')}")
    else:
        config_items["rclone.mount-dir"] = env("TARGET_NZBDAV_RCLONE_MOUNT_DIR", "/mnt/nzbdav")

    upsert_sqlite_config_items(db_path, config_items)


def existing_by_name(items):
    return {item.get("name"): item for item in items}


def ensure_indexers(prowlarr_url: str, prowlarr_key: str, seed_indexers):
    existing = existing_by_name(http_json(f"{prowlarr_url}/api/v1/indexer", prowlarr_key))
    created = 0
    skipped = 0
    failed = 0
    for payload in seed_indexers:
        name = payload.get("name")
        if name in existing:
            skipped += 1
            print(f"Indexer exists, skipping: {name}")
            continue
        try:
            http_json(f"{prowlarr_url}/api/v1/indexer", prowlarr_key, method="POST", payload=payload)
            created += 1
            print(f"Created indexer: {name}")
        except urllib.error.HTTPError as exc:
            failed += 1
            print(f"WARNING: failed to create indexer {name}: {http_error_details(exc)}")
    return created, skipped, failed


def ensure_download_client(base_url: str, api_key: str, payload, label: str):
    endpoint = f"{base_url}/api/v3/downloadclient"
    existing = existing_by_name(http_json(endpoint, api_key))
    name = payload.get("name")
    if name in existing:
        payload = json.loads(json.dumps(payload))
        payload["id"] = existing[name]["id"]
        http_json(f"{endpoint}/{payload['id']}", api_key, method="PUT", payload=payload)
        print(f"Updated {label} download client: {name}")
        return True
    try:
        http_json(endpoint, api_key, method="POST", payload=payload)
        print(f"Created {label} download client: {name}")
        return True
    except urllib.error.HTTPError as exc:
        print(f"WARNING: failed to create {label} download client {name}: {http_error_details(exc)}")
        return False


def configure_download_client_payload(template, *, sab_host, sab_port, sab_api_key, sab_username, sab_password):
    payload = json.loads(json.dumps(template))
    set_field_value(payload["fields"], "host", sab_host)
    set_field_value(payload["fields"], "port", int(sab_port))
    set_field_value(payload["fields"], "useSsl", False)
    set_field_value(payload["fields"], "urlBase", "")
    set_field_value(payload["fields"], "apiKey", sab_api_key)
    for optional, value in (("username", sab_username), ("password", sab_password)):
        try:
            set_field_value(payload["fields"], optional, value)
        except RuntimeError:
            pass
    return payload


def configure_application_payload(template, *, name, base_url, prowlarr_url, target_api_key):
    payload = json.loads(json.dumps(template))
    payload["name"] = name
    set_field_value(payload["fields"], "prowlarrUrl", prowlarr_url)
    set_field_value(payload["fields"], "baseUrl", base_url)
    set_field_value(payload["fields"], "apiKey", target_api_key)
    for optional in ("authUsername", "authPassword"):
        try:
            set_field_value(payload["fields"], optional, "")
        except RuntimeError:
            pass
    return payload


def ensure_prowlarr_application(prowlarr_url: str, prowlarr_key: str, payload, label: str):
    endpoint = f"{prowlarr_url}/api/v1/applications"
    existing = existing_by_name(http_json(endpoint, prowlarr_key))
    name = payload.get("name")
    if name in existing:
        print(f"Prowlarr application exists, skipping {label}: {name}")
        return False
    http_json(endpoint, prowlarr_key, method="POST", payload=payload)
    print(f"Created Prowlarr application: {name}")
    return True


def apply_data(input_path: Path, timeout_seconds: int):
    data = json.loads(input_path.read_text())
    use_nzbdav = env("ENABLE_NZBDAV", "false").lower() == "true"

    prowlarr_config = Path(env("PROWLARR_CONFIG", "./config/prowlarr")) / "config.xml"
    sonarr_config = Path(env("SONARR_CONFIG", "./config/sonarr")) / "config.xml"
    radarr_config = Path(env("RADARR_CONFIG", "./config/radarr")) / "config.xml"
    sabnzbd_config = Path(env("SABNZBD_CONFIG", "./config/sabnzbd")) / "sabnzbd.ini"
    nzbdav_db = Path(env("NZBDAV_CONFIG", "./config/nzbdav")) / "db.sqlite"

    config_paths = [prowlarr_config, sonarr_config, radarr_config]
    if use_nzbdav:
        config_paths.append(nzbdav_db)
    else:
        config_paths.append(sabnzbd_config)

    for path in config_paths:
        wait_for_config(path, timeout_seconds)

    prowlarr_key = read_api_key(str(prowlarr_config))
    sonarr_key = read_api_key(str(sonarr_config))
    radarr_key = read_api_key(str(radarr_config))
    prowlarr_url_base = read_url_base(str(prowlarr_config))
    sonarr_url_base = read_url_base(str(sonarr_config))
    radarr_url_base = read_url_base(str(radarr_config))

    prowlarr_url = env("TARGET_PROWLARR_URL", f"http://127.0.0.1:{env('PROWLARR_PORT', '9696')}{prowlarr_url_base}")
    sonarr_url = env("TARGET_SONARR_URL", f"http://127.0.0.1:{env('SONARR_PORT', '8989')}{sonarr_url_base}")
    radarr_url = env("TARGET_RADARR_URL", f"http://127.0.0.1:{env('RADARR_PORT', '7878')}{radarr_url_base}")

    internal_prowlarr_url = env("TARGET_INTERNAL_PROWLARR_URL", f"http://prowlarr:9696{prowlarr_url_base}")
    internal_sonarr_url = env("TARGET_INTERNAL_SONARR_URL", f"http://sonarr:8989{sonarr_url_base}")
    internal_radarr_url = env("TARGET_INTERNAL_RADARR_URL", f"http://radarr:7878{radarr_url_base}")

    wait_for_api(f"{prowlarr_url}/api/v1/system/status", prowlarr_key, "Prowlarr", timeout_seconds)
    wait_for_api(f"{sonarr_url}/api/v3/system/status", sonarr_key, "Sonarr", timeout_seconds)
    wait_for_api(f"{radarr_url}/api/v3/system/status", radarr_key, "Radarr", timeout_seconds)

    if use_nzbdav:
        configure_nzbdav(
            nzbdav_db,
            payload=data,
            internal_radarr_url=internal_radarr_url,
            internal_sonarr_url=internal_sonarr_url,
            radarr_key=radarr_key,
            sonarr_key=sonarr_key,
        )
        restart_nzbdav()
        nzbdav_key = read_nzbdav_api_key(nzbdav_db)
        nzbdav_url = env("TARGET_NZBDAV_URL", f"http://127.0.0.1:{env('NZBDAV_PORT', '3000')}")
        wait_for_sab_api(nzbdav_url, nzbdav_key, timeout_seconds)
        downloader_host = env("TARGET_INTERNAL_NZBDAV_HOST", "nzbdav")
        downloader_port = int(env("TARGET_INTERNAL_NZBDAV_PORT", env("NZBDAV_PORT", "3000")))
        downloader_api_key = nzbdav_key
        downloader_username = ""
        downloader_password = ""
    else:
        sabnzbd_key = read_ini_value(str(sabnzbd_config), "api_key")
        sabnzbd_username = read_ini_value(str(sabnzbd_config), "username")
        sabnzbd_password = read_ini_value(str(sabnzbd_config), "password")
        sabnzbd_url = env("TARGET_SABNZBD_URL", f"http://127.0.0.1:{env('SABNZBD_PORT', '8080')}")
        sabnzbd_host = env("TARGET_INTERNAL_SABNZBD_HOST", "sabnzbd")
        sabnzbd_port = int(env('TARGET_INTERNAL_SABNZBD_PORT', '8080'))
        wait_for_sab_api(sabnzbd_url, sabnzbd_key, timeout_seconds)

        required_sab_categories = {
            get_field_value(data["sonarr"]["downloadClient"].get("fields", []), "tvCategory", ""),
            get_field_value(data["radarr"]["downloadClient"].get("fields", []), "movieCategory", ""),
        }
        if ensure_sab_categories(sabnzbd_config, required_sab_categories):
            restart_sabnzbd()
            wait_for_sab_api(sabnzbd_url, sabnzbd_key, timeout_seconds)

        if ensure_sab_host_whitelist(sabnzbd_config, [sabnzbd_host, "localhost"]):
            restart_sabnzbd()
            wait_for_sab_api(sabnzbd_url, sabnzbd_key, timeout_seconds)

        downloader_host = sabnzbd_host
        downloader_port = sabnzbd_port
        downloader_api_key = sabnzbd_key
        downloader_username = sabnzbd_username
        downloader_password = sabnzbd_password

    created, skipped, failed = ensure_indexers(prowlarr_url, prowlarr_key, data["prowlarr"]["indexers"])
    sonarr_download_client = configure_download_client_payload(
        data["sonarr"]["downloadClient"],
        sab_host=downloader_host,
        sab_port=downloader_port,
        sab_api_key=downloader_api_key,
        sab_username=downloader_username,
        sab_password=downloader_password,
    )
    radarr_download_client = configure_download_client_payload(
        data["radarr"]["downloadClient"],
        sab_host=downloader_host,
        sab_port=downloader_port,
        sab_api_key=downloader_api_key,
        sab_username=downloader_username,
        sab_password=downloader_password,
    )
    ensure_download_client(sonarr_url, sonarr_key, sonarr_download_client, "Sonarr")
    ensure_download_client(radarr_url, radarr_key, radarr_download_client, "Radarr")

    sonarr_payload = configure_application_payload(
        data["prowlarr"]["applicationTemplates"]["sonarr"],
        name="Sonarr",
        base_url=internal_sonarr_url,
        prowlarr_url=internal_prowlarr_url,
        target_api_key=sonarr_key,
    )
    radarr_payload = configure_application_payload(
        data["prowlarr"]["applicationTemplates"]["radarr"],
        name="Radarr",
        base_url=internal_radarr_url,
        prowlarr_url=internal_prowlarr_url,
        target_api_key=radarr_key,
    )

    ensure_prowlarr_application(prowlarr_url, prowlarr_key, sonarr_payload, "Sonarr")
    ensure_prowlarr_application(prowlarr_url, prowlarr_key, radarr_payload, "Radarr")

    print(f"Applied bootstrap data from {input_path}")
    print(f"Indexer summary: created={created} skipped={skipped} failed={failed}")


def main(argv=None):
    parser = argparse.ArgumentParser(description="Export/apply portable media stack bootstrap data")
    subparsers = parser.add_subparsers(dest="command", required=True)

    export_parser = subparsers.add_parser("export", help="Export bootstrap data from a live stack")
    export_parser.add_argument(
        "--output",
        default=env("BOOTSTRAP_DATA_FILE", str(ROOT_DIR / "bootstrap-data/local/bootstrap-data.json")),
        help="Path to write exported bootstrap data",
    )

    apply_parser = subparsers.add_parser("apply", help="Apply bootstrap data to the local portable stack")
    apply_parser.add_argument(
        "--input",
        default=env("BOOTSTRAP_DATA_FILE", str(ROOT_DIR / "bootstrap-data/local/bootstrap-data.json")),
        help="Path to exported bootstrap data",
    )
    apply_parser.add_argument(
        "--timeout",
        type=int,
        default=int(env("BOOTSTRAP_WAIT_SECONDS", "180")),
        help="Seconds to wait for target apps/configs to become ready",
    )

    args = parser.parse_args(argv)

    try:
        if args.command == "export":
            export_data(Path(args.output))
        elif args.command == "apply":
            apply_data(Path(args.input), args.timeout)
        else:
            parser.error(f"Unknown command {args.command}")
    except urllib.error.HTTPError as exc:
        sys.stderr.write(f"HTTP error {exc.code} talking to Arr API: {exc.reason}\n")
        raise
    except Exception as exc:
        sys.stderr.write(f"ERROR: {exc}\n")
        raise


if __name__ == "__main__":
    main()
