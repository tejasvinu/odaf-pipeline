#!/bin/bash
# setup_spark_connection.sh - Creates the spark_default connection in Airflow

# Wait for Airflow webserver to be ready
echo "Waiting for Airflow webserver to be ready..."
for i in {1..30}; do
  curl -s http://localhost:8081/health >/dev/null && break
  echo "Waiting for Airflow webserver ($i/30)..."
  sleep 5
done

# Check if Airflow webserver is ready
if curl -s http://localhost:8081/health >/dev/null; then
  echo "Airflow webserver is ready"
else
  echo "Airflow webserver is not ready after 30 attempts. Proceeding anyway..."
fi

echo "Creating spark_default connection..."

# Use docker exec to run the airflow command inside the container
# Note: Container is named 'airflow', not 'airflow-webserver'
docker exec -it $(docker ps -qf "name=odaf-pipeline-airflow-1") airflow connections delete spark_default || true
docker exec -it $(docker ps -qf "name=odaf-pipeline-airflow-1") airflow connections add spark_default \
    --conn-type spark \
    --conn-host local \
    --conn-port "" \
    --conn-extra '{"spark-home": "/home/airflow/.local/lib/python3.7/site-packages/pyspark", "deploy-mode": "client"}'

echo "spark_default connection created successfully"