# TVD App Deployment Scripts

**Reusable GitHub Actions workflows** for standardized deployment across all TVD applications. This repository provides centralized CI/CD workflows that can be called from any TVD app repository.

## 🚀 Quick Start

Add this to your app's `.github/workflows/deploy.yml`:

```yaml
name: Deploy My App

on:
  push:
    branches: [ main, develop ]
  workflow_dispatch:

jobs:
  deploy-production:
    if: github.ref == 'refs/heads/main'
    uses: tvdapp/deployment-scripts/.github/workflows/deploy-app.yml@main
    with:
      app-name: "my-app"
      app-type: "static-web"  # or python-api, node-api
      container-port: 8080
      host-port: 3000
      domain: "my-app.tvdapp.nl"
    secrets: inherit
```

That's it! Your app will now deploy automatically on every push to main.

## Supported App Types

- **`static-web`**: Static websites served by nginx (like app-dashboard)
- **`python-api`**: Python Flask/FastAPI services (like Movie app)
- **`node-api`**: Node.js/Express APIs (like sheet-to-calendar backend)
- **`fullstack`**: Multi-service applications with database

## Configuration

Each app needs a `deployment-config.yml` file that defines:

### App Configuration
```yaml
app:
  name: "my-app"
  type: "static-web"  # or python-api, node-api, fullstack
  description: "My awesome application"
```

### Container Settings
```yaml
container:
  base_image_type: "nginx"  # nginx, python, node, custom
  port: 8080
  host_port: 3000
  health_endpoint: "/health"
```

### Deployment Strategy
```yaml
deployment:
  strategy: "replace"  # replace, blue-green, rolling
  wait_for_health: true
  health_timeout: 120
  restart_policy: "unless-stopped"
```

### Resource Limits
```yaml
resources:
  memory_limit: "128M"
  memory_reservation: "64M" 
  cpu_limit: "0.5"
  cpu_reservation: "0.1"
```

### Security
```yaml
security:
  run_as_non_root: true
  read_only_filesystem: true
  no_new_privileges: true
```

### Volumes
```yaml
volumes:
  - type: "bind"
    source: "./config.json"
    target: "/usr/share/nginx/html/config.json"
    read_only: true
```

### Networking & Reverse Proxy
```yaml
networks:
  - name: "traefik"
    external: true

labels:
  traefik.enable: "true"
  traefik.http.routers.my-app.rule: "Host(`my-app.tvdapp.nl`)"
  traefik.http.routers.my-app.entrypoints: "websecure"
```

## GitHub Actions Integration

Update your `.github/workflows/deploy.yml`:

```yaml
- name: Deploy with shared script
  run: |
    curl -sL https://raw.githubusercontent.com/tvdapp/deployment-scripts/main/deploy.sh | bash
```

Or for more control:

```yaml
- name: Download deployment script
  run: |
    curl -O https://raw.githubusercontent.com/tvdapp/deployment-scripts/main/deploy.sh
    chmod +x deploy.sh

- name: Deploy application
  run: ./deploy.sh
```

## Examples

### Static Web App (like app-dashboard)
```yaml
app:
  name: "my-dashboard"
  type: "static-web"
container:
  base_image_type: "nginx"
  port: 8080
  host_port: 3000
```

### Python API (like Movie app)
```yaml
app:
  name: "my-api"
  type: "python-api"
container:
  base_image_type: "python"
  port: 5000
  host_port: 1339
volumes:
  - type: "bind"
    source: "./auth"
    target: "/app/auth"
    read_only: true
```

### Node.js API
```yaml
app:
  name: "my-node-api"
  type: "node-api"
container:
  base_image_type: "node"
  port: 3000
  host_port: 3001
environment:
  NODE_ENV: "production"
  DATABASE_URL: "${DATABASE_URL}"
```

### Full-stack App with Database
```yaml
app:
  name: "my-fullstack-app"
  type: "fullstack"
services:
  - name: "frontend"
    port: 5173
    host_port: 8080
  - name: "backend"
    port: 3001
    host_port: 3001
  - name: "database"
    image: "postgres:15"
    port: 5432
```

## Advanced Features

### Custom Health Checks
```yaml
health:
  endpoint: "/api/health"
  timeout: 60
  retries: 5
  start_period: 30
```

### Multi-stage Deployments
```yaml
deployment:
  strategy: "blue-green"
  rollback_on_failure: true
  smoke_tests:
    - "curl -f http://localhost:3000/health"
    - "curl -f http://localhost:3000/api/status"
```

### Environment-specific Configuration
```yaml
environments:
  development:
    host_port: 3000
    resources:
      memory_limit: "64M"
  production:
    host_port: 80
    resources:
      memory_limit: "256M"
    labels:
      traefik.enable: "true"
```

## Migration Guide

### From Custom GitHub Actions

1. **Copy your current deployment logic** into `deployment-config.yml`
2. **Replace deployment steps** with the shared script
3. **Test the deployment** in a development environment
4. **Update production** workflow

### From Manual Deployment

1. **Create** `deployment-config.yml` based on your current setup
2. **Add** `deploy.sh` to your project
3. **Test locally** with `./deploy.sh`
4. **Add to GitHub Actions** when ready

## Troubleshooting

### Common Issues

**Container won't start:**
- Check port conflicts: `docker ps -a`
- Verify health endpoint: `curl http://localhost:PORT/health`
- Check container logs: `docker logs APP_NAME`

**Health check fails:**
- Increase `health_timeout` in config
- Verify `health_endpoint` is correct
- Check if app takes time to start

**Volume mount issues:**
- Ensure source files exist
- Check file permissions
- Verify paths are absolute

### Debug Mode

Run with debug output:
```bash
DEBUG=1 ./deploy.sh
```

## Contributing

1. **Test changes** with multiple app types
2. **Update documentation** for new features
3. **Maintain backward compatibility**
4. **Add example configurations**

## Supported Platforms

- ✅ Self-hosted GitHub Actions runners
- ✅ Local development environments  
- ✅ Docker-based deployments
- ✅ Traefik reverse proxy integration
- 🔄 Kubernetes (planned)
- 🔄 Docker Swarm (planned)