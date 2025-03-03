#!/bin/bash

# Ensure script runs as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (sudo)"
    exit 1
fi

echo "Installing ODAF Pipeline on CentOS..."

# Install required packages
yum update -y
yum install -y yum-utils device-mapper-persistent-data lvm2 epel-release

# Install Docker
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install -y docker-ce docker-ce-cli containerd.io

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/download/v2.20.3/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Start and enable Docker service
systemctl start docker
systemctl enable docker

# Create installation directory
mkdir -p /opt/odaf-pipeline
cp -r ./* /opt/odaf-pipeline/

# Set up systemd service
cp odaf-pipeline.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable odaf-pipeline

# Set proper permissions
chmod +x /opt/odaf-pipeline/setup.sh
chmod +x /opt/odaf-pipeline/check_health.sh

# Create data directories with proper SELinux context
for dir in /opt/odaf-pipeline/volumes/*; do
    mkdir -p "$dir"
    # Set SELinux context for container volumes
    chcon -Rt container_file_t "$dir"
done

# Run setup script
cd /opt/odaf-pipeline
./setup.sh

echo "Installation completed!"
echo "To start the pipeline, run: systemctl start odaf-pipeline"
echo "To check status, run: ./check_health.sh"