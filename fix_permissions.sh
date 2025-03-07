#!/bin/bash

# Make sure our script is executable
chmod +x verify_environment.sh

echo "Fixed permissions on verify_environment.sh"
echo "Now starting the containers..."

# Start containers
docker-compose up -d