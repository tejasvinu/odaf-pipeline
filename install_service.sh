#!/bin/bash
#
# ODAF Pipeline Service Installation Script
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

# Install the systemd service
echo "Installing systemd service..."
cp $INSTALL_DIR/odaf-pipeline.service $SERVICE_FILE
systemctl daemon-reload
systemctl enable odaf-pipeline.service

# Create directory structure
echo "Creating volume directories with correct permissions..."
mkdir -p $INSTALL_DIR/volumes/prometheus_data
mkdir -p $INSTALL_DIR/volumes/grafana_data
mkdir -p $INSTALL_DIR/volumes/airflow_logs
mkdir -p $INSTALL_DIR/volumes/airflow_config
mkdir -p $INSTALL_DIR/volumes/spark
mkdir -p $INSTALL_DIR/volumes/spark-worker-1
mkdir -p $INSTALL_DIR/volumes/zookeeper_data
mkdir -p $INSTALL_DIR/volumes/kafka_data
mkdir -p $INSTALL_DIR/volumes/cassandra_data
mkdir -p $INSTALL_DIR/volumes/minio_data
mkdir -p $INSTALL_DIR/volumes/postgres_data
mkdir -p $INSTALL_DIR/volumes/jupyter_data
mkdir -p $INSTALL_DIR/volumes/data

# Set permissive permissions
chmod -R 777 $INSTALL_DIR/volumes

echo "ODAF Pipeline service installation completed successfully!"
echo "You can start the service immediately with: systemctl start odaf-pipeline"
echo "The service will also start automatically on system boot."
echo "To check the service status, run: systemctl status odaf-pipeline"
echo "To view logs, run: journalctl -u odaf-pipeline -f"