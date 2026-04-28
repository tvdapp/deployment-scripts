#!/usr/bin/env python3
"""
Idempotently configure Uptime Kuma: ntfy notification, all monitors,
NUC heartbeat, and a public status page. Re-run after edits — existing
items are updated in place, obsolete ones removed.

Usage:
    pip install uptime-kuma-api
    KUMA_URL=https://uptime.tvdapp.nl \
    KUMA_USER=admin \
    KUMA_PASS='...' \
    NTFY_TOPIC='tvdapp-alerts-<slug>' \
    python kuma-setup.py
"""

from __future__ import annotations

import os
import sys
from getpass import getpass

try:
    from uptime_kuma_api import UptimeKumaApi, MonitorType, NotificationType
except ImportError:
    sys.exit("Missing dep: pip install uptime-kuma-api")


# Codes that indicate "the HTTP server is responding" — used for auth-required
# pages (302→login, 401, 403) and services without a root handler (404)
ALIVE_CODES = ["200-299", "300-399", "400-499"]
OK_CODES    = ["200-299"]

# Public HTTP monitors — full chain via NPM + cert
PUBLIC_HTTP = [
    # name              url                                            accepted
    ("Lauraway prod",  "https://community.tvdapp.nl/api/health",     OK_CODES),
    ("Dashboard",      "https://dashboard.tvdapp.nl",                OK_CODES),
    ("Movie",          "https://movie.tvdapp.nl/",                   OK_CODES),
    ("Health",         "https://health.tvdapp.nl",                   OK_CODES),
    ("Jellyfin",       "https://jellyfin.tvdapp.nl/health",          OK_CODES),
    ("n8n",            "https://n8n.tvdapp.nl/healthz",              OK_CODES),
    ("Node-RED",       "https://nodered.tvdapp.nl",                  ALIVE_CODES),
    ("Home Assistant", "https://ha.tvdapp.nl",                       ALIVE_CODES),
    ("Portainer",      "https://portainer.tvdapp.nl",                ALIVE_CODES),
]

# Internal HTTP monitors — Kuma can't reach 'localhost' (that's itself);
# use the NUC's static IP. Lauraway dev is here because its public URL has
# a Cloudflare→origin TLS issue separate from the app
INTERNAL_HTTP = [
    # name                       url                                            codes        interval
    ("Lauraway dev (internal)",  "http://192.168.1.151:3004/api/health",        OK_CODES,    30),
    ("Affine (internal)",        "http://192.168.1.151:3010",                   OK_CODES,    60),
    ("ipcam-stream (internal)",  "http://192.168.1.151:8090",                   ALIVE_CODES, 60),
]

INTERNAL_TCP = [
    # name              host             port  interval
    ("MQTT (internal)", "192.168.1.151", 1883, 60),
]

HEARTBEAT_NAME    = "NUC heartbeat"
STATUS_PAGE_SLUG  = "main"
STATUS_PAGE_TITLE = "TVD App Status"

# Docker container monitors — requires socket mounted into Kuma container
DOCKER_HOST_NAME = "nuc"
DOCKER_CONTAINERS = [
    "community", "community-dev", "movie-app", "ipcam-stream",
    "affine_server", "affine_redis", "affine_postgres",
    "health-app", "app-dashboard", "jellyfin",
    "n8n", "nodered", "mosquitto", "homeassistant",
    "npm", "portainer", "glances",
]

# Names previously created by older versions of this script that should be
# deleted on next run (renamed/replaced)
OBSOLETE_NAMES = {
    "Lauraway dev",  # renamed → "Lauraway dev (internal)"
}


def env_or_prompt(key: str, secret: bool = False) -> str:
    val = os.environ.get(key)
    if val:
        return val
    return (getpass if secret else input)(f"{key}: ")


def upsert_monitor(api: UptimeKumaApi, existing: list[dict], **params) -> str:
    """Create or update a monitor by name. Returns '+' (created) or '~' (updated)."""
    name = params["name"]
    match = next((m for m in existing if m["name"] == name), None)
    if match:
        api.edit_monitor(match["id"], **params)
        return "~"
    api.add_monitor(**params)
    return "+"


def main() -> None:
    url   = env_or_prompt("KUMA_URL")
    user  = env_or_prompt("KUMA_USER")
    pw    = env_or_prompt("KUMA_PASS", secret=True)
    totp  = os.environ.get("KUMA_TOTP")
    topic = env_or_prompt("NTFY_TOPIC")

    print(f"\n→ Connecting to {url} as {user}…")
    api = UptimeKumaApi(url)
    api.login(user, pw, token=totp) if totp else api.login(user, pw)
    print("✓ logged in\n")

    # 0. Clean up obsolete monitors
    for m in api.get_monitors():
        if m["name"] in OBSOLETE_NAMES:
            api.delete_monitor(m["id"])
            print(f"- removed obsolete: {m['name']}")

    # 1. Ntfy notification
    notifs = api.get_notifications()
    n = next((x for x in notifs if x.get("name") == "ntfy"), None)
    notif_params = dict(
        name="ntfy",
        type=NotificationType.NTFY,
        isDefault=True,
        applyExisting=True,
        ntfyserverurl="https://ntfy.sh",
        ntfytopic=topic,
        ntfyPriority=4,
    )
    if n:
        api.edit_notification(n["id"], **notif_params)
        notif_id = n["id"]
        print(f"~ ntfy notification (id={notif_id})")
    else:
        notif_id = api.add_notification(**notif_params)["id"]
        print(f"+ ntfy notification (id={notif_id})")

    notif_map = {str(notif_id): True}

    # 2. Public HTTP monitors (cert-expiry alert ON)
    monitors = api.get_monitors()
    print()
    for name, mon_url, codes in PUBLIC_HTTP:
        sym = upsert_monitor(api, monitors,
            type=MonitorType.HTTP,
            name=name,
            url=mon_url,
            interval=30,
            accepted_statuscodes=codes,
            notificationIDList=notif_map,
            expiryNotification=True,
        )
        print(f"{sym} [http]  {name}")

    # 3. Internal HTTP monitors
    for name, mon_url, codes, interval in INTERNAL_HTTP:
        sym = upsert_monitor(api, monitors,
            type=MonitorType.HTTP,
            name=name,
            url=mon_url,
            interval=interval,
            accepted_statuscodes=codes,
            notificationIDList=notif_map,
        )
        print(f"{sym} [http]  {name}")

    # 4. Internal TCP monitors
    for name, host, port, interval in INTERNAL_TCP:
        sym = upsert_monitor(api, monitors,
            type=MonitorType.PORT,
            name=name,
            hostname=host,
            port=port,
            interval=interval,
            notificationIDList=notif_map,
        )
        print(f"{sym} [tcp]   {name}")

    # 4.5 Docker host + per-container monitors
    print()
    hosts = api.get_docker_hosts()
    host = next((h for h in hosts if h["name"] == DOCKER_HOST_NAME), None)
    if host:
        api.edit_docker_host(host["id"], name=DOCKER_HOST_NAME,
                             dockerType="socket", dockerDaemon="/var/run/docker.sock")
        print(f"~ docker host: {DOCKER_HOST_NAME}")
    else:
        api.add_docker_host(name=DOCKER_HOST_NAME,
                            dockerType="socket", dockerDaemon="/var/run/docker.sock")
        host = next((h for h in api.get_docker_hosts() if h["name"] == DOCKER_HOST_NAME), None)
        print(f"+ docker host: {DOCKER_HOST_NAME}")
    host_id = host["id"]

    monitors = api.get_monitors()
    for cname in DOCKER_CONTAINERS:
        sym = upsert_monitor(api, monitors,
            type=MonitorType.DOCKER,
            name=f"{cname} (docker)",
            docker_container=cname,
            docker_host=host_id,
            interval=60,
            notificationIDList=notif_map,
        )
        print(f"{sym} [docker] {cname}")

    # 5. Heartbeat (Push)
    monitors = api.get_monitors()
    hb = next((m for m in monitors if m["name"] == HEARTBEAT_NAME), None)
    if not hb:
        api.add_monitor(
            type=MonitorType.PUSH,
            name=HEARTBEAT_NAME,
            interval=120,
            notificationIDList=notif_map,
        )
        hb = next((m for m in api.get_monitors() if m["name"] == HEARTBEAT_NAME), None)
        print(f"\n+ [push]  {HEARTBEAT_NAME}")
    else:
        print(f"\n= [push]  {HEARTBEAT_NAME}  (existing — token preserved)")
    push_token = hb.get("pushToken") if hb else None
    push_url   = f"{url.rstrip('/')}/api/push/{push_token}" if push_token else "(open in UI)"

    # 6. Public status page
    pages = api.get_status_pages()
    if not any(p["slug"] == STATUS_PAGE_SLUG for p in pages):
        api.add_status_page(slug=STATUS_PAGE_SLUG, title=STATUS_PAGE_TITLE)
        print(f"+ status page /status/{STATUS_PAGE_SLUG}")
    else:
        print(f"~ status page /status/{STATUS_PAGE_SLUG}")

    all_monitors = api.get_monitors()
    public_names   = {n for n, *_ in PUBLIC_HTTP}
    internal_names = {n for n, *_ in INTERNAL_HTTP} | {n for n, *_ in INTERNAL_TCP}
    docker_names   = {f"{c} (docker)" for c in DOCKER_CONTAINERS}
    api.save_status_page(
        slug=STATUS_PAGE_SLUG,
        title=STATUS_PAGE_TITLE,
        description="Public status of TVD apps",
        publicGroupList=[
            {"name": "Public services",   "monitorList": [{"id": m["id"]} for m in all_monitors if m["name"] in public_names]},
            {"name": "Internal services", "monitorList": [{"id": m["id"]} for m in all_monitors if m["name"] in internal_names]},
            {"name": "Docker containers","monitorList": [{"id": m["id"]} for m in all_monitors if m["name"] in docker_names]},
            {"name": "Server",            "monitorList": [{"id": m["id"]} for m in all_monitors if m["name"] == HEARTBEAT_NAME]},
        ],
    )
    print("✓ status page saved")

    api.disconnect()

    print(f"""
─── Done ─────────────────────────────────────────────────────────────
Status page:  {url.rstrip('/')}/status/{STATUS_PAGE_SLUG}
Ntfy topic:   {topic}

Heartbeat cron — install once on the NUC:
    sudo crontab -e
    */2 * * * * curl -fsS --max-time 10 {push_url} >/dev/null 2>&1
""")


if __name__ == "__main__":
    main()
