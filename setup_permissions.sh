#!/bin/bash
# setup_permissions.sh - Create and set correct permissions for volume directories

# Exit on error
set -e

echo "Creating volume directories with correct permissions..."

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

echo "Directory permissions set successfully"
echo "You can now start the containers with 'docker-compose up -d'"