#!/bin/bash

echo "Checking service health..."

# Function to check service health in Docker network with both busybox and GNU netcat support
check_docker_service() {
    local service=$1
    local container=$2
    local port=$3
    if docker exec $container sh -c "(nc -z localhost $port 2>/dev/null || nc -w 1 localhost $port 2>/dev/null)"; then
        echo "✅ $service is running"
        return 0
    else
        echo "❌ $service is not running"
        return 1
    fi
}

echo "Checking core services..."

# Check core services using Docker commands
for service in "Spark Master:spark-master:8080" "Kafka:kafka:9092" "Cassandra:cassandra:9042" \
              "MinIO:minio:9000" "MinIO Console:minio:9001" "Prometheus:prometheus:9090" \
              "Grafana:grafana:3000" "Airflow:airflow:8080"; do
    IFS=: read -r name container port <<< "$service"
    check_docker_service "$name" "$container" "$port"
done

echo -e "\nChecking data pipeline components..."

# Check Kafka topics
echo "Checking Kafka topics..."
docker exec kafka sh -c 'kafka-topics.sh --bootstrap-server localhost:9092 --list'

# Check MinIO bucket
echo -e "\nChecking MinIO bucket..."
docker exec minio sh -c 'mc alias set myminio http://localhost:9000 minioadmin minioadmin >/dev/null 2>&1 && mc ls myminio/metrics/'

# Check Cassandra keyspace
echo -e "\nChecking Cassandra keyspace..."
docker exec cassandra sh -c 'cqlsh -e "DESCRIBE KEYSPACES;"'

# Check Spark application status
echo -e "\nChecking Spark applications..."
docker exec spark-master spark-submit --version

# Check Airflow DAGs
echo -e "\nChecking Airflow DAGs..."
docker exec airflow airflow dags list

echo -e "\nHealth check completed!"