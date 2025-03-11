#!/bin/bash
set -e

echo "===== Environment Verification Script ====="

# Print system info
echo "=== System Information ==="
uname -a
echo ""

# Check Python installation
echo "Checking Python installation:"
python --version
which python
echo ""

# Check pip installation
echo "Checking pip installation:"
pip --version
which pip
echo ""

# Check PATH environment variable
echo "Checking PATH environment variable:"
echo $PATH
echo ""

# Check Airflow installation
echo "Checking Airflow installation:"
airflow version
python -c "import airflow; print(f'Airflow module version: {airflow.__version__}')"
echo ""

# Check Java installation
echo "=== Java Installation ==="
which java
java -version
echo "JAVA_HOME=$JAVA_HOME"
ls -la $JAVA_HOME/bin/java
echo ""

# Check essential commands
echo "=== Essential Commands ==="
for cmd in ps nc wget curl kafka-topics.sh spark-submit mc; do
  which $cmd || echo "$cmd not found"
done
echo ""

# Check Spark installation
echo "=== Spark Installation ==="
spark-submit --version
echo ""

# Check directory permissions
echo "=== Directory Permissions ==="
ls -la /opt/airflow
ls -la /opt/airflow/dags
ls -la /opt/airflow/logs
ls -la /opt/airflow/config
ls -la /opt/airflow/plugins
echo ""

# Check Python dependencies
echo "Checking Python dependencies:"
pip list | grep -E 'airflow|boto3|kafka|pyspark|spark'
echo ""

# Check network connectivity to services
echo "=== Network Connectivity ==="
for service in kafka:9092 cassandra:9042 prometheus:9090 minio:9000; do
  host=$(echo $service | cut -d':' -f1)
  port=$(echo $service | cut -d':' -f2)
  echo -n "Checking $service: "
  nc -z -v -w5 $host $port 2>&1 || echo "Failed to connect to $service"
done
echo ""

echo "Checking Kafka connectivity:"
nc -zv kafka 29092 || echo "Cannot connect to Kafka"
echo ""

echo "Checking Spark connectivity:"
nc -zv spark-master 7077 || echo "Cannot connect to Spark master"
echo ""

echo "Checking MinIO connectivity:"
nc -zv minio 9000 || echo "Cannot connect to MinIO"
echo ""

echo "Checking PostgreSQL connectivity:"
nc -zv postgres 5432 || echo "Cannot connect to PostgreSQL"
echo ""

echo "===== Environment Verification Complete ====="
