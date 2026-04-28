# Monitoring & Alerts

UI: https://uptime.tvdapp.nl · LAN: `http://192.168.1.151:3001`

## Notifications

| Channel | Role | Cost |
|---|---|---|
| ntfy.sh | Phone push (primary) | Free, no account |
| Email (Gmail SMTP) | Fallback | Free (app password) |
| SMS (Twilio) | Skip unless SLA-critical | ~€0.07/SMS |

## Automated setup

`kuma-setup.py` configures everything below idempotently (re-runnable).

```bash
pip install -r kuma-requirements.txt
KUMA_URL=https://uptime.tvdapp.nl \
KUMA_USER=admin \
KUMA_PASS='...' \
NTFY_TOPIC='tvdapp-alerts-<slug>' \
python kuma-setup.py
```

2FA: pass `KUMA_TOTP=123456` if enabled. API keys (Kuma 1.23) only expose `/metrics`, not config — username/password is required for monitor management.

Manual fallback: Kuma UI → **Settings → Notifications → Setup notification**.
- Ntfy: server `https://ntfy.sh`, topic = unique slug (treat like a password)
- Email: host `smtp.gmail.com:465`, SSL on, app password

## Public monitors (HTTP, 30s)

Test full path NPM → cert → backend.

| Monitor | URL | Accept |
|---|---|---|
| Lauraway prod | `https://community.tvdapp.nl/api/health` | 200-299 |
| Lauraway dev | `https://dev.community.tvdapp.nl/api/health` | 200-299 |
| Dashboard | `https://dashboard.tvdapp.nl` | 200-299 |
| Movie | `https://movie.tvdapp.nl/api/ping` | 200-299 |
| Health | `https://health.tvdapp.nl` | 200-299 |
| Jellyfin | `https://jellyfin.tvdapp.nl/health` | 200-299 |
| n8n | `https://n8n.tvdapp.nl/healthz` | 200-299 |
| Node-RED | `https://nodered.tvdapp.nl` | 200-499 (auth) |
| Home Assistant | `https://ha.tvdapp.nl` | 200-499 (auth) |
| Portainer | `https://portainer.tvdapp.nl` | 200-499 (auth) |

Per monitor: tick **both** notification channels, enable **Certificate Expiry Notification** (alerts 14d before LE renewal failure).

## Internal monitors (60s)

| Monitor | Type | Target |
|---|---|---|
| MQTT | TCP | `localhost:1883` |
| Affine | HTTP | `http://localhost:3010` |
| ipcam-stream | HTTP | `http://localhost:8090` |

## NUC heartbeat (dead-man's-switch)

Local Kuma can't alert if the NUC is dead. Two layers:

**1. Push monitor in Kuma** (catches docker/network failures while NUC is alive):

Kuma → Add Monitor → Push → copy URL → install on NUC:
```bash
sudo crontab -e
# add:
*/2 * * * * curl -fsS --max-time 10 https://uptime.tvdapp.nl/api/push/<token> >/dev/null 2>&1
```

**2. Off-site check** (catches NUC-itself-dead) — recommended:

Free [Healthchecks.io](https://healthchecks.io) account → 1 check, 5min grace → second cron entry hitting their URL. Alerts via email/Slack/etc when the NUC stops checking in.

## Status page

Kuma → Settings → Status Pages → New → tick all monitors → publish at `/status/main`.
