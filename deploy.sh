#!/bin/bash

# TVD App Universal Deployment Script v1.0
# This script provides standardized deployment for all TVD applications
# https://github.com/tvdapp/deployment-scripts

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/deployment-config.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

error() {
    echo -e "${RED}❌${NC} $1"
}

debug() {
    if [[ "${DEBUG:-}" == "1" ]]; then
        echo -e "${PURPLE}🔍${NC} $1"
    fi
}

info() {
    echo -e "${CYAN}ℹ️${NC} $1"
}

# Check dependencies
check_dependencies() {
    local missing=()
    
    if ! command -v docker &> /dev/null; then
        missing+=("docker")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing[*]}"
        error "Please install them and try again"
        exit 1
    fi
}

# Parse YAML configuration (simple parsing for key-value pairs)
parse_config() {
    local key="$1"
    local default="${2:-}"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "$default"
        return
    fi
    
    # Handle nested keys like app.name or container.port
    if [[ "$key" == *.* ]]; then
        local section="${key%%.*}"
        local field="${key##*.}"
        
        # Extract the section and then the field within it
        local result
        result=$(awk "
            /^${section}:/ { in_section=1; next }
            /^[a-zA-Z]/ && in_section { in_section=0 }
            in_section && /^[[:space:]]*${field}:/ {
                gsub(/^[[:space:]]*${field}:[[:space:]]*/, \"\")
                gsub(/[\"']/, \"\")
                print
                exit
            }
        " "$CONFIG_FILE" 2>/dev/null | xargs)
        
        echo "${result:-$default}"
    else
        # Simple top-level key
        local result
        result=$(grep -E "^\s*${key}:" "$CONFIG_FILE" 2>/dev/null | head -1 | sed -E 's/.*:\s*"?([^"]*)"?.*/\1/' | xargs)
        echo "${result:-$default}"
    fi
}

# Parse array values from YAML
parse_config_array() {
    local key="$1"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return
    fi
    
    grep -A 100 "^${key}:" "$CONFIG_FILE" | grep -E "^\s*-\s" | sed 's/^\s*-\s*//' | xargs
}

# Load and validate configuration
load_config() {
    log "📋 Loading deployment configuration..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Deployment configuration not found: $CONFIG_FILE"
        info "Create a deployment-config.yml file or download template:"
        info "curl -O https://raw.githubusercontent.com/tvdapp/deployment-scripts/main/templates/deployment-config.yml"
        exit 1
    fi
    
    # Load configuration
    APP_NAME=$(parse_config "app.name" "$(basename "$SCRIPT_DIR")")
    APP_TYPE=$(parse_config "app.type" "static-web")
    APP_DESCRIPTION=$(parse_config "app.description" "TVD Application")
    
    # Container configuration
    BASE_IMAGE_TYPE=$(parse_config "container.base_image_type" "nginx")
    CONTAINER_PORT=$(parse_config "container.port" "8080")
    HOST_PORT=$(parse_config "container.host_port" "3000")
    HEALTH_ENDPOINT=$(parse_config "container.health_endpoint" "/health")
    
    # Deployment configuration
    DEPLOYMENT_STRATEGY=$(parse_config "deployment.strategy" "replace")
    WAIT_FOR_HEALTH=$(parse_config "deployment.wait_for_health" "true")
    HEALTH_TIMEOUT=$(parse_config "deployment.health_timeout" "120")
    RESTART_POLICY=$(parse_config "deployment.restart_policy" "unless-stopped")
    
    # Resource configuration
    MEMORY_LIMIT=$(parse_config "resources.memory_limit" "128M")
    MEMORY_RESERVATION=$(parse_config "resources.memory_reservation" "64M")
    CPU_LIMIT=$(parse_config "resources.cpu_limit" "0.5")
    CPU_RESERVATION=$(parse_config "resources.cpu_reservation" "0.1")
    
    # Security configuration
    RUN_AS_NON_ROOT=$(parse_config "security.run_as_non_root" "true")
    READ_ONLY_FILESYSTEM=$(parse_config "security.read_only_filesystem" "false")
    NO_NEW_PRIVILEGES=$(parse_config "security.no_new_privileges" "true")
    
    # Cleanup configuration
    KEEP_IMAGES=$(parse_config "cleanup.keep_images" "3")
    REMOVE_UNUSED=$(parse_config "cleanup.remove_unused" "true")
    
    IMAGE_NAME="${APP_NAME}-prod"
    
    debug "Configuration loaded:"
    debug "  APP_NAME: $APP_NAME"
    debug "  APP_TYPE: $APP_TYPE"
    debug "  IMAGE_NAME: $IMAGE_NAME"
    debug "  PORTS: $HOST_PORT → $CONTAINER_PORT"
    debug "  HEALTH: $HEALTH_ENDPOINT (timeout: ${HEALTH_TIMEOUT}s)"
    debug "  RESOURCES: ${MEMORY_LIMIT} memory, ${CPU_LIMIT} CPU"
}

# Build Docker image
build_image() {
    log "🔨 Building Docker image: ${IMAGE_NAME}:latest"
    
    if [[ ! -f "Dockerfile" ]]; then
        error "Dockerfile not found in current directory"
        exit 1
    fi
    
    if docker build -t "${IMAGE_NAME}:latest" .; then
        success "Docker image built successfully"
    else
        error "Failed to build Docker image"
        exit 1
    fi
}

# Parse volumes from configuration
parse_volumes() {
    local volume_args=""
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo ""
        return
    fi
    
    # Simple volume parsing - look for bind mounts
    local in_volumes=false
    while IFS= read -r line; do
        # Check if we're in the volumes section
        if [[ $line =~ ^volumes: ]]; then
            in_volumes=true
            continue
        elif [[ $line =~ ^[a-zA-Z] ]] && [[ "$in_volumes" == "true" ]]; then
            in_volumes=false
        fi
        
        if [[ "$in_volumes" == "true" ]]; then
            # Extract source and target from YAML
            if [[ $line =~ source:.*[\"\'](.*)[\"\'] ]]; then
                local source="${BASH_REMATCH[1]}"
                # Look for target on next few lines
                local target=""
                for i in {1..3}; do
                    local next_line
                    next_line=$(sed -n "$((NR+i))p" <<< "$line" 2>/dev/null || echo "")
                    if [[ $next_line =~ target:.*[\"\'](.*)[\"\'] ]]; then
                        target="${BASH_REMATCH[1]}"
                        break
                    fi
                done
                
                if [[ -n "$target" && -f "$source" ]]; then
                    # Check if read_only is specified
                    local mount_option=""
                    if grep -A 5 "source.*$source" "$CONFIG_FILE" | grep -q "read_only.*true"; then
                        mount_option=":ro"
                    fi
                    volume_args="$volume_args -v ${source}:${target}${mount_option}"
                    debug "Adding volume: ${source}:${target}${mount_option}"
                fi
            fi
        fi
    done <<< "$(cat "$CONFIG_FILE")"
    
    echo "$volume_args"
}

# Parse labels from configuration
parse_labels() {
    local label_args=""
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo ""
        return
    fi
    
    # Extract labels section
    local in_labels=false
    while IFS= read -r line; do
        if [[ $line =~ ^labels: ]]; then
            in_labels=true
            continue
        elif [[ $line =~ ^[a-zA-Z] ]] && [[ "$in_labels" == "true" ]]; then
            in_labels=false
        fi
        
        if [[ "$in_labels" == "true" && $line =~ ^[[:space:]]+([^:]+):[[:space:]]*[\"\'](.*)[\"\']\$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            label_args="$label_args --label ${key}=${value}"
            debug "Adding label: ${key}=${value}"
        fi
    done <<< "$(cat "$CONFIG_FILE")"
    
    echo "$label_args"
}

# Stop and remove existing container
remove_existing_container() {
    log "🔍 Checking for existing container: $APP_NAME"
    
    if docker ps -a --format "table {{.Names}}" | grep -q "^${APP_NAME}\$"; then
        warning "Existing container found"
        
        log "🛑 Stopping existing container..."
        if docker stop "$APP_NAME" 2>/dev/null; then
            success "Container stopped"
        else
            warning "Container was not running or failed to stop"
        fi
        
        log "🗑️ Removing existing container..."
        if docker rm "$APP_NAME" 2>/dev/null; then
            success "Container removed"
        else
            warning "Failed to remove container (may not exist)"
        fi
    else
        info "No existing container found"
    fi
}

# Start new container
start_container() {
    log "🚀 Starting new container: $APP_NAME"
    
    # Parse volumes and labels
    local volume_args
    volume_args=$(parse_volumes)
    local label_args
    label_args=$(parse_labels)
    
    # Build security arguments
    local security_args=""
    if [[ "$RUN_AS_NON_ROOT" == "true" ]]; then
        # This is handled in Dockerfile typically
        debug "Non-root user specified (handled in Dockerfile)"
    fi
    if [[ "$READ_ONLY_FILESYSTEM" == "true" ]]; then
        security_args="$security_args --read-only"
        # Add common tmpfs mounts for read-only containers
        security_args="$security_args --tmpfs /tmp:rw,size=10M"
        security_args="$security_args --tmpfs /var/cache:rw,size=10M"
        security_args="$security_args --tmpfs /var/run:rw,size=5M"
    fi
    if [[ "$NO_NEW_PRIVILEGES" == "true" ]]; then
        security_args="$security_args --security-opt no-new-privileges:true"
    fi
    
    # Build the docker run command
    local docker_cmd="docker run -d \
        --name $APP_NAME \
        --restart $RESTART_POLICY \
        -p ${HOST_PORT}:${CONTAINER_PORT} \
        --memory $MEMORY_LIMIT \
        --memory-reservation $MEMORY_RESERVATION \
        --cpus $CPU_LIMIT \
        --health-cmd=\"wget --no-verbose --tries=1 --spider http://localhost:${CONTAINER_PORT}${HEALTH_ENDPOINT} || exit 1\" \
        --health-interval=30s \
        --health-timeout=10s \
        --health-retries=3 \
        --health-start-period=40s \
        $security_args \
        $volume_args \
        $label_args \
        ${IMAGE_NAME}:latest"
    
    debug "Running: $docker_cmd"
    
    if eval "$docker_cmd"; then
        success "Container started successfully"
    else
        error "Failed to start container"
        error "Check the configuration and try again"
        exit 1
    fi
}

# Wait for container health
wait_for_health() {
    if [[ "$WAIT_FOR_HEALTH" != "true" ]]; then
        info "Health check disabled, skipping..."
        return
    fi
    
    log "⏳ Waiting for container to become healthy (timeout: ${HEALTH_TIMEOUT}s)..."
    
    local start_time
    start_time=$(date +%s)
    
    timeout "$HEALTH_TIMEOUT" bash -c "
        while true; do
            status=\$(docker inspect --format='{{.State.Health.Status}}' '$APP_NAME' 2>/dev/null || echo 'unknown')
            case \$status in
                'healthy')
                    echo '✅ Container is healthy!'
                    exit 0
                    ;;
                'unhealthy')
                    echo '❌ Container is unhealthy!'
                    exit 1
                    ;;
                'starting'|'unknown')
                    echo \"⌛ Container health: \$status\"
                    sleep 5
                    ;;
                *)
                    echo \"⚠️ Unknown health status: \$status\"
                    sleep 5
                    ;;
            esac
        done
    " || {
        warning "Health check timeout or failure"
        local container_status
        container_status=$(docker inspect --format='{{.State.Health.Status}}' "$APP_NAME" 2>/dev/null || echo 'unknown')
        warning "Final health status: $container_status"
        
        # Show container logs for debugging
        if [[ "${DEBUG:-}" == "1" ]]; then
            error "Container logs (last 20 lines):"
            docker logs --tail 20 "$APP_NAME" || true
        fi
    }
    
    # Test HTTP endpoint directly
    log "🌐 Testing HTTP endpoint: http://localhost:${HOST_PORT}${HEALTH_ENDPOINT}"
    timeout 60 bash -c "
        until curl -sf http://localhost:${HOST_PORT}${HEALTH_ENDPOINT} >/dev/null 2>&1; do
            echo '⌛ Waiting for HTTP response...'
            sleep 3
        done
        echo '✅ HTTP endpoint is responding'
    " || warning "HTTP endpoint test failed (container may still be starting)"
}

# Verify deployment
verify_deployment() {
    log "🔍 Verifying deployment..."
    
    echo ""
    info "📊 Container Status:"
    if docker ps --filter name="$APP_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -q "$APP_NAME"; then
        docker ps --filter name="$APP_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        
        local health_status
        health_status=$(docker inspect --format="{{.State.Health.Status}}" "$APP_NAME" 2>/dev/null || echo "no health check")
        
        echo ""
        info "🏥 Health Status: $health_status"
        
        echo ""
        info "🌐 Access Points:"
        echo "   📱 Local: http://localhost:${HOST_PORT}"
        if [[ "$HEALTH_ENDPOINT" != "/" ]]; then
            echo "   🏥 Health: http://localhost:${HOST_PORT}${HEALTH_ENDPOINT}"
        fi
        
        # Show any configured public domains
        if grep -q "traefik.http.routers" "$CONFIG_FILE" 2>/dev/null; then
            local domain
            domain=$(grep "traefik.http.routers.*rule" "$CONFIG_FILE" | head -1 | sed -E 's/.*Host\(`([^`]*)`\).*/\1/' 2>/dev/null | xargs)
            if [[ -n "$domain" ]]; then
                echo "   🌍 Public: https://$domain"
            fi
        fi
        
        echo ""
        success "🎉 Deployment completed successfully!"
        return 0
    else
        echo ""
        error "❌ Deployment failed - container not running"
        
        if [[ "${DEBUG:-}" == "1" ]]; then
            error "Recent container logs:"
            docker logs --tail 20 "$APP_NAME" 2>/dev/null || echo "No logs available"
        fi
        
        return 1
    fi
}

# Cleanup old images
cleanup_images() {
    if [[ "$REMOVE_UNUSED" != "true" ]]; then
        debug "Image cleanup disabled"
        return
    fi
    
    log "🧹 Cleaning up old images (keeping latest $KEEP_IMAGES)..."
    
    # Get list of images for this app, sorted by creation date
    local images_to_remove
    images_to_remove=$(docker images "${IMAGE_NAME}" --format "table {{.ID}}\t{{.CreatedAt}}" | \
                      tail -n +2 | \
                      sort -k2 -r | \
                      tail -n +$((KEEP_IMAGES + 1)) | \
                      awk '{print $1}')
    
    if [[ -n "$images_to_remove" ]]; then
        echo "$images_to_remove" | xargs -r docker rmi 2>/dev/null || true
        success "Old images cleaned up"
    else
        debug "No old images to clean up"
    fi
    
    # Remove dangling images
    local dangling
    dangling=$(docker images -f "dangling=true" -q)
    if [[ -n "$dangling" ]]; then
        echo "$dangling" | xargs -r docker rmi 2>/dev/null || true
        debug "Dangling images removed"
    fi
}

# Print usage
usage() {
    echo "TVD App Universal Deployment Script v1.0"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -v, --version  Show version information"
    echo "  --debug        Enable debug output"
    echo "  --config FILE  Use custom config file (default: deployment-config.yml)"
    echo ""
    echo "Environment variables:"
    echo "  DEBUG=1        Enable debug output"
    echo ""
    echo "Examples:"
    echo "  $0                    # Deploy using deployment-config.yml"
    echo "  $0 --debug            # Deploy with debug output"
    echo "  DEBUG=1 $0            # Same as above"
    echo ""
}

# Main deployment function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--version)
                echo "TVD App Universal Deployment Script v1.0"
                exit 0
                ;;
            --debug)
                DEBUG=1
                ;;
            --config)
                CONFIG_FILE="$2"
                shift
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
        shift
    done
    
    # Script header
    echo ""
    echo -e "${CYAN}🚀 TVD App Universal Deployment Script v1.0${NC}"
    echo -e "${CYAN}════════════════════════════════════════════${NC}"
    echo ""
    
    # Run deployment steps
    check_dependencies
    load_config
    
    log "🚀 Starting deployment for: ${APP_NAME}"
    log "📋 App type: ${APP_TYPE}"
    log "📦 Image: ${IMAGE_NAME}:latest"
    log "🔌 Port mapping: ${HOST_PORT} → ${CONTAINER_PORT}"
    echo ""
    
    build_image
    remove_existing_container
    start_container
    wait_for_health
    
    if verify_deployment; then
        cleanup_images
        echo ""
        log "🏁 Deployment pipeline completed successfully!"
        echo ""
    else
        echo ""
        error "💥 Deployment failed!"
        echo ""
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi