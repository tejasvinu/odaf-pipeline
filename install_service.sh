#!/bin/bash
#
# ODAF Pipeline Service Installation Script for CentOS 7
# This script installs the ODAF pipeline as a systemd service

# Exit on any error
set -e

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
   echo "This script must be run as root" 
   exit 1
fi

# Define variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INSTALL_DIR="/opt/odaf-pipeline"
SERVICE_FILE="/etc/systemd/system/odaf-pipeline.service"

echo "Starting ODAF Pipeline Service Installation..."

# Install required packages
echo "Installing required packages..."
yum -y update
yum -y install epel-release
yum -y install docker docker-compose nc wget curl java-11-openjdk-devel

# Start and enable Docker service
echo "Configuring Docker service..."
systemctl start docker
systemctl enable docker

# Configure SELinux
echo "Configuring SELinux..."
# Install SELinux management tools
yum -y install policycoreutils-python

# Set SELinux context for the installation directory
semanage fcontext -a -t container_file_t "$INSTALL_DIR(/.*)?"
restorecon -Rv "$INSTALL_DIR"

# Configure firewall
echo "Configuring firewall..."
# Install firewalld if not present
yum -y install firewalld
systemctl start firewalld
systemctl enable firewalld

# Add firewall rules for ODAF services
firewall-cmd --permanent --add-port=8081/tcp  # Airflow
firewall-cmd --permanent --add-port=8084/tcp  # Spark UI
firewall-cmd --permanent --add-port=3001/tcp  # Grafana
firewall-cmd --permanent --add-port=9091/tcp  # Prometheus
firewall-cmd --permanent --add-port=8085/tcp  # Kafka UI
firewall-cmd --permanent --add-port=8890/tcp  # JupyterLab
firewall-cmd --permanent --add-port=9001/tcp  # MinIO Console
firewall-cmd --permanent --add-port=9000/tcp  # MinIO API
firewall-cmd --permanent --add-port=9092/tcp  # Kafka
firewall-cmd --permanent --add-port=2182/tcp  # Zookeeper
firewall-cmd --permanent --add-port=5432/tcp  # PostgreSQL
firewall-cmd --reload

# Create installation directory
echo "Creating installation directory..."
mkdir -p $INSTALL_DIR

# Copy files to installation directory
echo "Copying ODAF Pipeline files to $INSTALL_DIR..."
cp -r $SCRIPT_DIR/* $INSTALL_DIR/

# Fix permissions
echo "Setting appropriate permissions..."
chmod +x $INSTALL_DIR/*.sh
chmod -R 755 $INSTALL_DIR

# Create directory structure
echo "Creating volume directories with correct permissions..."
mkdir -p $INSTALL_DIR/volumes/{prometheus_data,grafana_data,airflow_logs,airflow_config,spark,spark-worker-1,zookeeper_data,kafka_data,cassandra_data,minio_data,postgres_data,jupyter_data,data}

# Set permissive permissions and SELinux context
chmod -R 777 $INSTALL_DIR/volumes
semanage fcontext -a -t container_file_t "$INSTALL_DIR/volumes(/.*)?"
restorecon -Rv "$INSTALL_DIR/volumes"

# Install the systemd service
echo "Installing systemd service..."
cp $INSTALL_DIR/odaf-pipeline.service $SERVICE_FILE
systemctl daemon-reload
systemctl enable odaf-pipeline.service

# Configure system limits for production use
echo "Configuring system limits..."
cat > /etc/sysctl.d/99-odaf-pipeline.conf << EOF
# Increase max file descriptors
fs.file-max = 2097152

# Increase max number of processes
kernel.pid_max = 4194304

# Increase system IP port limits
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
EOF

# Apply sysctl settings
sysctl --system

# Create limits file for the service
cat > /etc/security/limits.d/99-odaf-pipeline.conf << EOF
*         soft    nproc     65535
*         hard    nproc     65535
*         soft    nofile    65535
*         hard    nofile    65535
root      soft    nproc     65535
root      hard    nproc     65535
root      soft    nofile    65535
root      hard    nofile    65535
EOF

echo "ODAF Pipeline service installation completed successfully!"
echo "----------------------------------------------------------------"
echo "Next steps:"
echo "1. Start the service: systemctl start odaf-pipeline"
echo "2. Check status: systemctl status odaf-pipeline"
echo "3. View logs: journalctl -u odaf-pipeline -f"
echo "4. Services will be available at:"
echo "   - Airflow: http://localhost:8081 (user: airflow, password: airflow)"
echo "   - Spark UI: http://localhost:8084"
echo "   - Grafana: http://localhost:3001 (user: admin, password: admin)"
echo "   - Prometheus: http://localhost:9091"
echo "   - Kafka UI: http://localhost:8085"
echo "   - JupyterLab: http://localhost:8890"
echo "   - MinIO: http://localhost:9001 (user: minioadmin, password: minioadmin)"
echo "----------------------------------------------------------------"
echo "Note: A system reboot is recommended to apply all changes."