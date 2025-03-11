#!/bin/bash

# Create necessary directories if they don't exist
mkdir -p ./volumes/airflow_logs
mkdir -p ./volumes/airflow_logs/scheduler
mkdir -p ./volumes/airflow_logs/webserver
mkdir -p ./volumes/airflow_logs/worker
mkdir -p ./volumes/airflow_config

# Set very permissive permissions to avoid permission denied errors
chmod -R 777 ./volumes/airflow_logs
chmod -R 777 ./volumes/airflow_config

echo "Airflow permissions fixed!"
echo "Next step: Run 'docker-compose down' and then 'docker-compose up -d' to restart the environment."