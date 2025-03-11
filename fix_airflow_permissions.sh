#!/bin/bash

# Create necessary directories if they don't exist
mkdir -p ./volumes/airflow_logs
mkdir -p ./volumes/airflow_logs/scheduler
mkdir -p ./volumes/airflow_logs/webserver
mkdir -p ./volumes/airflow_logs/worker
mkdir -p ./volumes/airflow_config
mkdir -p ./volumes/airflow_logs/dag_processor_manager
mkdir -p ./volumes/airflow_logs/triggerer
mkdir -p ./dags
mkdir -p ./plugins

# Set very permissive permissions to avoid permission denied errors
chmod -R 777 ./volumes/airflow_logs
chmod -R 777 ./volumes/airflow_config
chmod -R 777 ./dags
chmod -R 777 ./plugins

# Create necessary files to prevent permission errors
touch ./volumes/airflow_logs/.gitkeep
touch ./volumes/airflow_config/.gitkeep

echo "Airflow permissions fixed!"
echo "Next step: Run 'docker-compose down' and then 'docker-compose up -d' to restart the environment."
echo "Note: If you still experience permission issues, you may need to run: docker-compose down -v"
echo "      This will remove volumes, requiring database reinitialization but fixing persistent permission issues."