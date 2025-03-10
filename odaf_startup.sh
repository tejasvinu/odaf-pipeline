#!/bin/bash
#
# ODAF Pipeline Startup Script for CentOS 7
# This script automates the startup of the ODAF pipeline containers

# Exit on any error
set -e

# Script location - get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Color codes for prettier output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="$SCRIPT_DIR/odaf_startup.log"

# Function for logging
log() {
    local message="$1"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "${timestamp} - ${message}"
    echo -e "${timestamp} - ${message}" >> "$LOG_FILE"
}

log_success() {
    log "${GREEN}SUCCESS: $1${NC}"
}

log_info() {
    log "${BLUE}INFO: $1${NC}"
}

log_warning() {
    log "${YELLOW}WARNING: $1${NC}"
}

log_error() {
    log "${RED}ERROR: $1${NC}"
}

# Function to check SELinux status
check_selinux() {
    log_info "Checking SELinux configuration..."
    if ! command -v semanage &> /dev/null; then
        log_error "SELinux tools not found. Installing policycoreutils-python..."
        yum -y install policycoreutils-python
    fi
    
    # Ensure container file contexts are set
    semanage fcontext -a -t container_file_t "$SCRIPT_DIR/volumes(/.*)?" || true
    restorecon -Rv "$SCRIPT_DIR/volumes"
    log_success "SELinux context updated for volumes"
}

# Function to check system prerequisites
check_prerequisites() {
    log_info "Checking system prerequisites..."
    
    # Check if Docker is running
    if ! systemctl is-active --quiet docker; then
        log_error "Docker is not running"
        log_info "Starting Docker service..."
        systemctl start docker || {
            log_error "Failed to start Docker service"
            return 1
        }
    fi
    
    # Check if firewalld is running
    if ! systemctl is-active --quiet firewalld; then
        log_warning "Firewalld is not running. Starting firewalld..."
        systemctl start firewalld || log_warning "Failed to start firewalld"
    fi
    
    log_success "System prerequisites checked"
    return 0
}

# Function to set up volume directories with correct permissions
setup_volumes() {
    log_info "Setting up volume directories with correct permissions..."
    
    # Create directories if they don't exist
    local VOLUME_DIRS=(
        "./volumes/prometheus_data"
        "./volumes/grafana_data"
        "./volumes/airflow_logs"
        "./volumes/airflow_config"
        "./volumes/spark"
        "./volumes/spark-worker-1"
        "./volumes/zookeeper_data"
        "./volumes/kafka_data"
        "./volumes/cassandra_data"
        "./volumes/minio_data"
        "./volumes/postgres_data"
        "./volumes/jupyter_data"
        "./volumes/data"
    )
    
    for dir in "${VOLUME_DIRS[@]}"; do
        mkdir -p "$dir"
        chmod -R 777 "$dir"
    done
    
    # Update SELinux context for all volume directories
    semanage fcontext -a -t container_file_t "$SCRIPT_DIR/volumes(/.*)?" || true
    restorecon -Rv "$SCRIPT_DIR/volumes"
    
    log_success "Volume directories created with proper permissions"
}

# Function to fix line endings in script files
fix_line_endings() {
    log_info "Fixing line endings in script files..."
    
    find "$SCRIPT_DIR" -type f -name "*.sh" -exec sed -i 's/\r$//' {} \;
    find "$SCRIPT_DIR" -type f -name "*.sh" -exec chmod +x {} \;
    
    log_success "Line endings fixed for script files"
}

# Function to start all containers
start_containers() {
    log_info "Starting all containers with docker-compose..."
    
    # Pull latest images if needed
    if [ "$1" == "pull" ]; then
        log_info "Pulling latest Docker images..."
        docker-compose pull
    fi
    
    # Start containers in the background
    docker-compose up -d
    
    if [ $? -eq 0 ]; then
        log_success "Containers started successfully"
        return 0
    else
        log_error "Failed to start containers"
        return 1
    fi
}

# Function to check container health with increased timeout
check_container_health() {
    log_info "Checking health of all containers..."
    
    local TIMEOUT=300  # 5 minutes timeout for initial health check
    local INTERVAL=10  # Check every 10 seconds
    local elapsed=0
    
    while [ $elapsed -lt $TIMEOUT ]; do
        local unhealthy=0
        
        # Check each container's status
        for container in prometheus grafana airflow airflow-scheduler postgres spark-master kafka zookeeper cassandra; do
            local status=$(docker-compose ps -q $container | xargs -I {} docker inspect -f '{{.State.Status}}' {} 2>/dev/null)
            
            if [ "$status" != "running" ]; then
                unhealthy=1
                log_warning "Container $container is not running (status: $status)"
            fi
        done
        
        if [ $unhealthy -eq 0 ]; then
            log_success "All containers are healthy"
            return 0
        fi
        
        sleep $INTERVAL
        elapsed=$((elapsed + INTERVAL))
        log_info "Waiting for containers to become healthy... ($elapsed/$TIMEOUT seconds)"
    done
    
    log_error "Health check timed out after ${TIMEOUT} seconds"
    return 1
}

# Function to fix permissions in containers
fix_container_permissions() {
    log_info "Fixing container permissions..."
    
    docker-compose exec -T prometheus sh -c "chmod -R 777 /prometheus" || log_warning "Failed to fix Prometheus permissions"
    docker-compose exec -T grafana sh -c "chmod -R 777 /var/lib/grafana" || log_warning "Failed to fix Grafana permissions"
    docker-compose exec -T airflow sh -c "mkdir -p /opt/airflow/logs/scheduler /opt/airflow/logs/dag_processor && chmod -R 777 /opt/airflow" || log_warning "Failed to fix Airflow permissions"
    
    log_success "Container permissions fixed"
}

# Main function
main() {
    log_info "Starting ODAF Pipeline on CentOS 7..."
    log_info "-------------------------"
    
    # Check SELinux configuration
    check_selinux
    
    # Check prerequisites
    check_prerequisites || {
        log_error "Prerequisites check failed. Cannot proceed."
        exit 1
    }
    
    # Set up volume directories
    setup_volumes
    
    # Fix line endings in script files
    fix_line_endings
    
    # Start containers
    if docker-compose ps -q | grep -q .; then
        log_info "Some containers are already running"
        read -p "Do you want to restart all containers? (y/n): " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            log_info "Stopping all containers..."
            docker-compose down
            start_containers
        else
            log_info "Skipping container restart"
        fi
    else
        start_containers
    fi
    
    # Wait for containers to initialize
    log_info "Waiting for containers to initialize (up to 5 minutes)..."
    
    # Check container health
    if ! check_container_health; then
        log_warning "Some containers are not healthy. Attempting to fix issues..."
        fix_container_permissions
        
        # Check health again
        if ! check_container_health; then
            log_error "Some containers are still unhealthy. Please check the logs:"
            log_info "docker-compose logs <service-name>"
        fi
    fi
    
    # Display access information
    log_info ""
    log_info "ODAF Pipeline services:"
    log_info "----------------------"
    log_info "Airflow:     http://localhost:8081      (user: airflow, password: airflow)"
    log_info "Spark UI:    http://localhost:8084"
    log_info "Grafana:     http://localhost:3001      (user: admin, password: admin)"
    log_info "Prometheus:  http://localhost:9091"
    log_info "Kafka UI:    http://localhost:8085"
    log_info "JupyterLab:  http://localhost:8890      (no password)"
    log_info "MinIO:       http://localhost:9001      (user: minioadmin, password: minioadmin)"
    log_info ""
    log_info "ODAF Pipeline started successfully!"
    
    # Print helpful commands
    log_info ""
    log_info "Useful commands:"
    log_info "- View service logs: journalctl -u odaf-pipeline -f"
    log_info "- Check service status: systemctl status odaf-pipeline"
    log_info "- View container logs: docker-compose logs -f [service_name]"
    log_info "- Stop all containers: docker-compose down"
}

# Run the main function
main "$@"