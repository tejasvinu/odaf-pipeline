#!/bin/bash

# Print system info
echo "=== System Information ==="
uname -a
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
ls -la /opt/airflow/dags
ls -la /opt/airflow/logs
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

echo "=== Environment Verification Complete ==="
