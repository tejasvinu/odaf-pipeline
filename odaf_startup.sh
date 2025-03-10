#!/bin/bash
#
# ODAF Pipeline Startup Script
# This script automates the startup of the ODAF pipeline containers,
# handles permissions, and monitors container health.

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

# Function to check if Docker is running
check_docker() {
    log_info "Checking if Docker is running..."
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running or not installed."
        log_info "Attempting to start Docker service..."
        if systemctl start docker; then
            log_success "Docker service started successfully."
        else
            log_error "Failed to start Docker service. Please ensure Docker is installed and configured correctly."
            return 1
        fi
    else
        log_success "Docker is running."
    fi
    return 0
}

# Function to set up volume directories with correct permissions
setup_volumes() {
    log_info "Setting up volume directories with correct permissions..."
    
    # Create directories if they don't exist
    mkdir -p ./volumes/prometheus_data
    mkdir -p ./volumes/grafana_data
    mkdir -p ./volumes/airflow_logs
    mkdir -p ./volumes/airflow_config
    mkdir -p ./volumes/spark
    mkdir -p ./volumes/spark-worker-1
    mkdir -p ./volumes/zookeeper_data
    mkdir -p ./volumes/kafka_data
    mkdir -p ./volumes/cassandra_data
    mkdir -p ./volumes/minio_data
    mkdir -p ./volumes/postgres_data
    mkdir -p ./volumes/jupyter_data
    mkdir -p ./volumes/data
    
    # Set permissive permissions (anyone can read/write)
    chmod -R 777 ./volumes/prometheus_data
    chmod -R 777 ./volumes/grafana_data
    chmod -R 777 ./volumes/airflow_logs
    chmod -R 777 ./volumes/airflow_config
    chmod -R 777 ./volumes/spark
    chmod -R 777 ./volumes/spark-worker-1
    chmod -R 777 ./volumes/zookeeper_data
    chmod -R 777 ./volumes/kafka_data
    chmod -R 777 ./volumes/cassandra_data
    chmod -R 777 ./volumes/minio_data
    chmod -R 777 ./volumes/postgres_data
    chmod -R 777 ./volumes/jupyter_data
    chmod -R 777 ./volumes/data
    
    log_success "Volume directories created with proper permissions."
}

# Function to fix line endings in script files
fix_line_endings() {
    log_info "Fixing line endings in script files..."
    
    # List of script files to check
    script_files=(
        "airflow-entrypoint.sh"
        "check_container_files.sh"
        "check_health.sh"
        "fix_line_endings.sh"
        "fix_permissions.sh"
        "setup_environment.sh"
        "setup_permissions.sh"
        "setup_spark_connection.sh"
        "setup.sh"
        "verify_environment.sh"
    )
    
    for file in "${script_files[@]}"; do
        if [ -f "$file" ]; then
            log_info "Fixing line endings for $file"
            sed -i 's/\r$//' "$file"
            chmod +x "$file"
        else
            log_warning "Script file $file not found, skipping"
        fi
    done
    
    log_success "Line endings fixed for script files."
}

# Function to start all containers
start_containers() {
    log_info "Starting all containers with docker-compose..."
    
    # Pull latest images if needed
    if [ "$1" == "pull" ]; then
        log_info "Pulling latest Docker images..."
        docker-compose pull
        log_success "Docker images pulled successfully."
    fi
    
    # Start containers in the background
    docker-compose up -d
    
    if [ $? -eq 0 ]; then
        log_success "Containers started successfully."
        return 0
    else
        log_error "Failed to start containers."
        return 1
    fi
}

# Function to restart specific container
restart_container() {
    local container_name="$1"
    log_info "Restarting container: $container_name"
    
    if docker-compose restart "$container_name"; then
        log_success "Container $container_name restarted successfully."
        return 0
    else
        log_error "Failed to restart container $container_name."
        return 1
    fi
}

# Function to check container health
check_container_health() {
    log_info "Checking health of all containers..."
    
    # List of critical containers to check
    critical_containers=(
        "prometheus"
        "grafana"
        "airflow"
        "airflow-scheduler"
        "postgres"
        "spark-master"
        "kafka"
        "zookeeper"
        "cassandra"
    )
    
    unhealthy_containers=()
    
    for container in "${critical_containers[@]}"; do
        container_id=$(docker-compose ps -q $container 2>/dev/null)
        
        if [ -z "$container_id" ]; then
            log_warning "Container $container is not running"
            unhealthy_containers+=("$container")
            continue
        fi
        
        # Check container status
        status=$(docker inspect --format='{{.State.Status}}' "$container_id" 2>/dev/null)
        
        if [ "$status" != "running" ]; then
            log_warning "Container $container is not running (status: $status)"
            unhealthy_containers+=("$container")
            continue
        fi
        
        log_success "Container $container is healthy (status: $status)"
    done
    
    if [ ${#unhealthy_containers[@]} -eq 0 ]; then
        log_success "All critical containers are healthy."
        return 0
    else
        log_warning "Unhealthy containers: ${unhealthy_containers[*]}"
        return 1
    fi
}

# Function to fix Prometheus permissions
fix_prometheus_permissions() {
    log_info "Fixing Prometheus permissions..."
    
    docker-compose exec -T prometheus sh -c "chmod -R 777 /prometheus"
    
    if [ $? -eq 0 ]; then
        log_success "Prometheus permissions fixed."
        return 0
    else
        log_error "Failed to fix Prometheus permissions."
        return 1
    fi
}

# Function to fix Grafana permissions
fix_grafana_permissions() {
    log_info "Fixing Grafana permissions..."
    
    docker-compose exec -T grafana sh -c "chmod -R 777 /var/lib/grafana"
    
    if [ $? -eq 0 ]; then
        log_success "Grafana permissions fixed."
        return 0
    else
        log_error "Failed to fix Grafana permissions."
        return 1
    fi
}

# Function to fix Airflow permissions
fix_airflow_permissions() {
    log_info "Fixing Airflow permissions..."
    
    docker-compose exec -T airflow sh -c "mkdir -p /opt/airflow/logs/scheduler /opt/airflow/logs/dag_processor && chmod -R 777 /opt/airflow"
    
    if [ $? -eq 0 ]; then
        log_success "Airflow permissions fixed."
        return 0
    else
        log_error "Failed to fix Airflow permissions."
        return 1
    fi
}

# Main function
main() {
    log_info "Starting ODAF Pipeline..."
    log_info "-------------------------"
    
    # Check if Docker is running
    if ! check_docker; then
        log_error "Docker is not available. Cannot proceed."
        exit 1
    fi
    
    # Set up volume directories
    setup_volumes
    
    # Fix line endings in script files
    fix_line_endings
    
    # Check if any containers are running
    if docker-compose ps -q | grep -q .; then
        log_info "Some containers are already running."
        
        # Prompt user for action
        read -p "Do you want to restart all containers? (y/n): " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            log_info "Stopping all containers..."
            docker-compose down
            start_containers
        else
            log_info "Skipping container restart."
        fi
    else
        # Start all containers
        start_containers
    fi
    
    # Wait for containers to initialize
    log_info "Waiting 30 seconds for containers to initialize..."
    sleep 30
    
    # Check container health
    if ! check_container_health; then
        log_warning "Some containers are not healthy. Attempting to fix issues..."
        
        # Fix permissions for critical services
        fix_prometheus_permissions
        fix_grafana_permissions
        fix_airflow_permissions
        
        # Restart unhealthy containers
        restart_container "prometheus"
        restart_container "grafana"
        restart_container "airflow"
        restart_container "airflow-scheduler"
        
        # Wait for services to restart
        log_info "Waiting 15 seconds for services to restart..."
        sleep 15
        
        # Check health again
        if ! check_container_health; then
            log_error "Some containers are still unhealthy. Manual intervention may be required."
            log_info "You can check the logs with: docker-compose logs <service-name>"
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
}

# Run the main function
main "$@"