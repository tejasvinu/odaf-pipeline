#!/bin/bash

# This script checks if important files exist in the Airflow container

echo "Checking files in Airflow container..."

# Container name
CONTAINER="odaf-pipeline-airflow-1"

echo "1. Checking verify_environment.sh exists in container:"
docker exec $CONTAINER ls -la /opt/airflow/verify_environment.sh || echo "File not found!"

echo "2. Checking file permissions:"
docker exec $CONTAINER ls -la /opt/airflow/

echo "3. Checking if the file is executable:"
docker exec $CONTAINER test -x /opt/airflow/verify_environment.sh && echo "File is executable" || echo "File is not executable!"

echo "4. Checking if file has correct line endings:"
docker exec $CONTAINER cat -A /opt/airflow/verify_environment.sh | head -1

echo "5. Checking bash interpreter in container:"
docker exec $CONTAINER which bash

echo "Check complete!"
