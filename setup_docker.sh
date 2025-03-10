#!/bin/bash
#
# Setup Docker for CentOS 7 with proper configuration
# This script must be run as root

set -e

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

echo "Setting up Docker for CentOS 7..."

# Remove any old versions
yum remove -y docker docker-client docker-client-latest docker-common \
    docker-latest docker-latest-logrotate docker-logrotate docker-engine

# Install required packages
yum install -y yum-utils device-mapper-persistent-data lvm2

# Add Docker repository
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Install Docker CE
yum install -y docker-ce docker-ce-cli containerd.io

# Create Docker daemon directory
mkdir -p /etc/docker

# Copy daemon configuration
cp ./docker/daemon.json /etc/docker/daemon.json

# Create systemd drop-in directory
mkdir -p /etc/systemd/system/docker.service.d

# Configure Docker to use systemd
cat > /etc/systemd/system/docker.service.d/docker.conf << EOF
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd --log-level=info
EOF

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create symbolic link
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Start and enable Docker service
systemctl daemon-reload
systemctl start docker
systemctl enable docker

# Configure SELinux for containers
setsebool -P container_manage_cgroup 1

# Test Docker installation
docker --version
docker-compose --version

# Add current user to docker group
usermod -aG docker $(logname)

echo "Docker setup completed successfully!"
echo "Please log out and log back in for group changes to take effect."