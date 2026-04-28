# TVD App NUC Server Documentation

This document provides a comprehensive overview of the NUC server setup for the TVD App deployment infrastructure.

## 🖥️ Server Overview

**Hardware**: Intel NUC  
**OS**: Ubuntu Linux  
**IP Address**: 192.168.1.151  
**User**: thijsvandam  
**SSH Access**: `ssh Tvdapp` (configured in SSH config)

## Post-Reboot Verification

```bash
# On NUC: services + containers
ssh Tvdapp 'systemctl is-enabled docker github-runner ssh && systemctl is-active docker github-runner ssh && docker ps --format "table {{.Names}}\t{{.Status}}"'

# From outside: public smoke test
curl -fsS https://community.tvdapp.nl/api/health
curl -fsS https://dev.community.tvdapp.nl/api/health
```

Expected: services `enabled`+`active`, containers `Up`, HTTP 200.

| Symptom | Fix |
|---|---|
| `github-runner` disabled | `sudo systemctl enable --now github-runner` |
| Container `exited` | check `RestartPolicy` is `unless-stopped` (except one-shot jobs) |
| Public URL down but container `Up` | check NPM container running, NPM admin at `:81` from LAN |

## Docker Infrastructure

Public traffic: NPM (`npm` container, 80/81/443) terminates Let's Encrypt TLS, routes by `Host:` header. Admin UI at `:81` from LAN. (The reusable deploy workflow still emits Traefik labels — harmless no-ops.)

### Public-facing apps (via NPM)

| Subdomain | Container | Host port | Description |
|---|---|---|---|
| `community.tvdapp.nl` | community | 3003 | Lauraway prod (Next.js) |
| `dev.community.tvdapp.nl` | community-dev | 3004 | Lauraway dev (Next.js) |
| `dashboard.tvdapp.nl` | app-dashboard | 3000 | App index dashboard |
| `movie.tvdapp.nl` | movie-app | 4000 | Python Flask movie sync |
| `health.tvdapp.nl` | health-app | 5000 | SvelteKit health tracker |
| `jellyfin.tvdapp.nl` | jellyfin | 8096 | Media server |
| `n8n.tvdapp.nl` | n8n | 5678 | Workflow automation |
| `nodered.tvdapp.nl` | nodered | 1880 | Node-RED automation |
| `ha.tvdapp.nl` | homeassistant | host net | Home Assistant |
| `portainer.tvdapp.nl` | portainer | 9443 | Docker management UI |
| `uptime.tvdapp.nl` | uptime-kuma | 3001 | Uptime monitoring |

### Internal-only services

| Service | Port | Description |
|---|---|---|
| ipcam-stream | 8090 | IP camera stream relay |
| affine_server | 3010 | Affine project mgmt (+ redis, postgres) |
| mosquitto | 1883/9001 | MQTT broker |
| glances | — | System metrics (Python web UI) |

## 🚀 Deployment Framework

All TVD apps use a standardized GitHub Actions deployment workflow with the following features:

- **Automated builds** on push to main/develop branches
- **Health checks** with automatic restart
- **Resource limits** (memory and CPU)
- **Volume mounts** for persistent data
- **Environment variables** for configuration
- **Rollback capability** through container management

### Deployment Workflow Features

```yaml
# Example deployment configuration
- Build Docker image from source
- Stop and remove existing container
- Start new container with:
  - Health checks (30s intervals)
  - Memory limits (256M-512M)
  - CPU limits (0.5-1.0 cores)
  - Restart policy: unless-stopped
  - Volume mounts for auth/data
```

## 🔧 GitHub Actions Runner

The NUC runs a self-hosted GitHub Actions runner managed as a systemd service.

### Runner Setup

1. **Installation Location**: `/home/thijsvandam/actions-runner`
2. **Service Name**: `github-runner`
3. **Auto-start**: Should be enabled — verify with `systemctl is-enabled github-runner`
4. **User**: thijsvandam

**Gotcha:** unit can be `disabled` after reboot — deployments then silently no-op (`validate` job runs in cloud, `deploy` needs `self-hosted`). Fix: `sudo systemctl enable --now github-runner`.

### Runner Management Commands

```bash
# Check runner status
sudo systemctl status github-runner

# Start/Stop/Restart runner
sudo systemctl start github-runner
sudo systemctl stop github-runner
sudo systemctl restart github-runner

# View runner logs
sudo journalctl -u github-runner -f

# Enable/Disable auto-start
sudo systemctl enable github-runner
sudo systemctl disable github-runner
```

### Runner Configuration

- **Name**: nuc-runner
- **Labels**: self-hosted, Linux, X64
- **Work Directory**: `/home/thijsvandam/actions-runner/_work`
- **Repository Access**: All tvdapp repositories

## 📁 Directory Structure

```
/home/thijsvandam/
├── actions-runner/          # GitHub Actions runner
│   ├── run.sh              # Runner executable
│   ├── config.sh           # Configuration script
│   └── _work/              # Workflow execution directory
└── Src/personal/tvdapp/    # Source code (if cloned locally)

/app/                       # Docker volume mounts
└── data/                   # Organized data directory
    ├── movie/              # Movie app data
    │   ├── auth/           # Production authentication files
    │   │   ├── trusty-banner-177912-b7832ed51e8e.json
    │   │   ├── calendar-url.txt
    │   │   ├── sheet-url.txt
    │   │   ├── tmdb-api-key.txt
    │   │   └── ...
    │   └── staging-auth/   # Staging authentication files
    └── health/             # Health app data (if needed)
```

## 🔐 Authentication & Secrets

### Movie App Authentication Files

Located in `/app/data/movie/auth/`:

- `trusty-banner-177912-b7832ed51e8e.json` - Google Service Account credentials
- `calendar-url.txt` - Google Calendar ID
- `sheet-url.txt` - Google Sheets URL
- `tmdb-api-key.txt` - TMDB API key for movie data
- `tmdb.json` - TMDB configuration
- `tmdb_cache.json` - Cached movie data
- `sheet_cache.json` - Cached sheet data

### Security Notes

- All auth files are mounted as Docker volumes (read-only where possible)
- Staging and production environments use separate auth directories
- SSH key-based authentication for GitHub (no HTTPS tokens needed)

## 🌐 Network & Access

### Internal Access

```bash
# SSH to NUC
ssh Tvdapp

# Application URLs (from NUC)
http://localhost:3000  # app-dashboard
http://localhost:4000  # Movie app
http://localhost:5000  # health app
```

### External Access (if configured)

```bash
# From local network
http://192.168.1.151:3000  # app-dashboard
http://192.168.1.151:4000  # Movie app
http://192.168.1.151:5000  # health app
```

## 📊 Container Management

### Viewing Running Containers

```bash
# List all containers
docker ps

# List TVD app containers specifically
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(movie|health|app-dashboard|NAMES)"

# View container logs
docker logs <container-name> --tail 50 -f

# Container stats
docker stats
```

### Manual Container Operations

```bash
# Stop a container
docker stop <container-name>

# Start a container
docker start <container-name>

# Restart a container
docker restart <container-name>

# Remove a container
docker rm <container-name>

# View container health
docker inspect <container-name> | grep -A5 Health
```

## 🔄 Maintenance & Troubleshooting

### Common Operations

```bash
# Check disk space
df -h

# Check memory usage
free -h

# Check Docker space usage
docker system df

# Clean up unused Docker resources
docker system prune -a

# View system resources
htop
```

### Health Check Endpoints

| App | Health Check URL | Expected Response |
|-----|------------------|-------------------|
| Movie | `http://localhost:4000/api/ping` | 200 OK |
| Health | `http://localhost:5000/` | SvelteKit app |
| app-dashboard | `http://localhost:3000/` | Dashboard HTML |

### Log Locations

```bash
# GitHub Actions runner logs
sudo journalctl -u github-runner -f

# Docker container logs
docker logs <container-name> -f

# System logs
sudo journalctl -f
```

## 🚨 Emergency Procedures

### Runner Issues

1. **Runner not picking up jobs**:
   ```bash
   sudo systemctl restart github-runner
   sudo journalctl -u github-runner -f
   ```

2. **Runner stuck/unresponsive**:
   ```bash
   sudo systemctl stop github-runner
   # Wait 30 seconds
   sudo systemctl start github-runner
   ```

3. **Re-register runner** (if token expires):
   ```bash
   cd ~/actions-runner
   sudo systemctl stop github-runner
   ./config.sh remove --token <removal-token>
   ./config.sh --url https://github.com/tvdapp --token <new-token> --name "nuc-runner"
   sudo systemctl start github-runner
   ```

### Application Issues

1. **App not responding**:
   ```bash
   docker restart <app-name>
   docker logs <app-name> --tail 50
   ```

2. **Deployment stuck**:
   ```bash
   # Check if container is running
   docker ps | grep <app-name>
   
   # Force stop and remove
   docker stop <app-name>
   docker rm <app-name>
   
   # Trigger new deployment by pushing to GitHub
   ```

3. **Auth file issues** (Movie app):
   ```bash
   # Check auth files exist
   ls -la /app/data/movie/auth/
   
   # Re-copy from local if needed
   scp ~/path/to/auth/* Tvdapp:~/temp-auth/
   # Then use Docker to copy with proper permissions
   docker run --rm -v /app:/app -v ~/temp-auth:/src alpine cp /src/* /app/data/movie/auth/
   ```

### System Recovery

1. **Full system restart**:
   ```bash
   sudo reboot
   ```

2. **Docker service issues**:
   ```bash
   sudo systemctl restart docker
   ```

3. **Free up disk space**:
   ```bash
   docker system prune -a
   sudo apt autoremove
   sudo apt autoclean
   ```

## 📈 Monitoring

### Key Metrics to Watch

- **Disk Usage**: Should stay below 80%
- **Memory Usage**: Monitor for memory leaks in containers
- **CPU Usage**: Should be reasonable during deployments
- **Container Health**: All apps should show "healthy" status

### Monitoring Commands

```bash
# System overview
htop

# Docker container stats
docker stats

# Disk usage by directory
du -sh /* 2>/dev/null | sort -hr

# Check if all apps are responding
curl -f http://localhost:3000/ && echo "✅ Dashboard OK"
curl -f http://localhost:4000/api/ping && echo "✅ Movie API OK"  
curl -f http://localhost:5000/ && echo "✅ Health OK"
```

### Uptime Kuma

UI: https://uptime.tvdapp.nl. Watches every public endpoint + key internals, alerts via ntfy + email. Setup details and full monitor list: [MONITORING.md](./MONITORING.md).

## 🔧 Configuration Files

### Systemd Service

**Location**: `/etc/systemd/system/github-runner.service`

```ini
[Unit]
Description=GitHub Actions Runner
After=network.target

[Service]
Type=simple
User=thijsvandam
Group=thijsvandam
WorkingDirectory=/home/thijsvandam/actions-runner
ExecStart=/home/thijsvandam/actions-runner/run.sh
Restart=always
RestartSec=5
TimeoutStopSec=30
KillMode=process
StandardOutput=journal
StandardError=journal

Environment=RUNNER_ALLOW_RUNASROOT=false
Environment=DOTNET_RUNNING_IN_CONTAINER=false

[Install]
WantedBy=multi-user.target
```

## 📋 Deployment Checklist

When deploying a new app:

- [ ] Create Dockerfile in app directory
- [ ] Create `.github/workflows/deploy.yml` with standardized deployment
- [ ] Configure appropriate port mapping
- [ ] Set up health check endpoint
- [ ] Create auth/config volumes if needed
- [ ] Test deployment on develop branch first
- [ ] Deploy to main branch for production
- [ ] Verify app is accessible and healthy
- [ ] Add app to monitoring/health checks

## 🔗 Useful Links

- [GitHub Actions Runner Documentation](https://docs.github.com/en/actions/hosting-your-own-runners)
- [Docker Documentation](https://docs.docker.com/)
- [systemd Service Management](https://www.digitalocean.com/community/tutorials/how-to-use-systemctl-to-manage-systemd-services-and-units)

## 📝 Change Log

- **2025-12-08**: Initial NUC setup with 3 deployed apps
- **2025-12-08**: Standardized deployment framework implemented
- **2025-12-08**: GitHub Actions runner configured as systemd service

---

**Last Updated**: December 8, 2025  
**Maintainer**: Thijs van Dam  
**Server**: Intel NUC (192.168.1.151)