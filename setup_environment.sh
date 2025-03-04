#!/bin/bash

echo "Setting up environment for ODAF Pipeline..."

# Fix line endings in all shell scripts
echo "Converting line endings in shell scripts..."
find . -name "*.sh" -type f -exec sed -i 's/\r$//' {} \;
echo "Line endings conversion complete."

# Set executable permissions
echo "Setting executable permissions..."
find . -name "*.sh" -type f -exec chmod +x {} \;
echo "Permissions set."

# Generate Fernet key if needed
echo "Checking if we need to generate a Fernet key..."
if ! grep -q "AIRFLOW__CORE__FERNET_KEY=" docker-compose.yml || grep -q "AIRFLOW__CORE__FERNET_KEY=''" docker-compose.yml; then
    echo "Fernet key missing or empty, generating a new one..."
    if command -v python3 &>/dev/null; then
        python3 generate_fernet_key.py
    else
        echo "Warning: Python3 not found, please manually generate a Fernet key."
        echo "You can use the following command from a Python environment:"
        echo "python3 -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())'"
    fi
fi

echo "Environment setup complete."
echo "You can now build and run the Docker containers with:"
echo "docker-compose build"
echo "docker-compose up -d"
