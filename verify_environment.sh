#!/bin/bash
set -e

echo "==== Starting environment verification ===="
echo "Current user: $(whoami)"
echo "Hostname: $(hostname)"
echo "Current directory: $(pwd)"

# Check environment variables
echo -e "\n==== Checking environment variables ===="
echo "JAVA_HOME: $JAVA_HOME"
echo "AIRFLOW_HOME: $AIRFLOW_HOME"
echo "PATH: $PATH"

# Print system info
echo "=== System Information ==="
uname -a
echo ""

# Check if bash is available
echo "=== Checking Bash ==="
if command -v bash > /dev/null; then
  echo "✓ bash is installed at $(which bash)"
else
  echo "CRITICAL: bash is not available in this container!"
  echo "Installing bash..."
  if command -v apt-get > /dev/null; then
    apt-get update && apt-get install -y bash
  elif command -v apk > /dev/null; then
    apk add --no-cache bash
  elif command -v yum > /dev/null; then
    yum install -y bash
  else
    echo "ERROR: Could not install bash, package manager not found"
    exit 1
  fi
fi
echo ""

# Verify Java installation
echo -e "\n==== Verifying Java installation ===="
if command -v java >/dev/null 2>&1; then
    which java
    java -version
    echo "Java installation verified ✓"
else
    echo "ERROR: Java not found in PATH"
    echo "Looking for Java in standard locations..."
    find /usr/lib/jvm -name "java" 2>/dev/null || echo "No Java installation found"
    exit 1
fi

# Check Python installation
echo "=== Python Installation ==="
python --version
which python
echo ""

# Check pip installation
echo "Checking pip installation:"
pip --version
which pip
echo ""

# Check Airflow installation
echo "=== Airflow Installation ==="
airflow version
python -c "import airflow; print(f'Airflow module version: {airflow.__version__}')"
echo ""

# Verify Spark installation
echo -e "\n==== Verifying Spark installation ===="
if command -v spark-submit >/dev/null 2>&1; then
    which spark-submit
    spark-submit --version
    echo "Spark installation verified ✓"
    
    # Check if it's a symlink to PySpark
    if [ -L "$(which spark-submit)" ]; then
        echo "spark-submit is a symlink to: $(readlink -f $(which spark-submit))"
    fi
else
    echo "ERROR: spark-submit not found in PATH"
    echo "Checking for alternative spark binaries..."
    for binary in spark2-submit spark3-submit; do
        if command -v $binary >/dev/null 2>&1; then
            echo "Found $binary: $(which $binary)"
        fi
    done
    echo "Checking /usr/local/bin for spark-related files..."
    ls -la /usr/local/bin/spark* 2>/dev/null || echo "No spark binaries found in /usr/local/bin/"
    exit 1
fi

# Verify Python and PySpark
echo -e "\n==== Verifying Python and PySpark ===="
if command -v python >/dev/null 2>&1; then
    which python
    python --version
    echo "Python installation verified ✓"
    
    echo "Checking for PySpark..."
    if python -c "import pyspark; print(f'PySpark version: {pyspark.__version__}')" 2>/dev/null; then
        echo "PySpark installation verified ✓"
    else
        echo "WARNING: PySpark module not found or cannot be imported"
        pip list | grep pyspark || echo "PySpark not found in pip list"
    fi
else
    echo "ERROR: Python not found in PATH"
    exit 1
fi

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
  which $cmd 2>/dev/null || echo "$cmd not found"
done
echo ""

# Check Spark installation
echo "=== Spark Installation ==="
if command -v spark-submit > /dev/null; then
  echo "✓ Spark is installed at $(which spark-submit)"
  spark-submit --version 2>&1 | grep "version" || echo "Could not get Spark version"
else
  echo "CRITICAL: spark-submit not found in PATH"
  echo "Current PATH: $PATH"
  exit 1
fi

# Check if spark-submit is executable
echo "Checking spark-submit permissions..."
SPARK_SUBMIT=$(which spark-submit 2>/dev/null || echo "not-found")
if [ "$SPARK_SUBMIT" != "not-found" ]; then
  if [ -x "$SPARK_SUBMIT" ]; then
    echo "✓ spark-submit is executable"
  else
    echo "ERROR: spark-submit is not executable, fixing permissions..."
    chmod +x "$SPARK_SUBMIT"
    echo "✓ Fixed spark-submit permissions"
  fi
fi
echo ""

# Check directory permissions
echo "=== Directory Permissions ==="
dirs="/opt/airflow/dags /opt/airflow/logs /opt/airflow/config /opt/airflow/plugins"
for dir in $dirs; do
  if [ -d "$dir" ]; then
    echo "Directory $dir exists with permissions: $(ls -ld $dir | awk '{print $1}')"
    if [ -r "$dir" ] && [ -x "$dir" ]; then
      echo "✓ Directory $dir is accessible"
    else
      echo "WARNING: Cannot access directory $dir (permission issues)"
      chmod -R 777 "$dir" 2>/dev/null || echo "Could not fix permissions for $dir"
    fi
  else
    echo "WARNING: Directory $dir does not exist"
    mkdir -p "$dir" 2>/dev/null && echo "Created directory $dir" || echo "Could not create $dir"
  fi
done
echo ""

# Check Python dependencies
echo "=== Python Dependencies ==="
pip list | grep -E 'airflow|boto3|kafka|pyspark|spark'
echo ""

# Verify Airflow connections
echo -e "\n==== Verifying Airflow connections ===="
if airflow connections get spark_default --output json 2>/dev/null; then
    echo "Spark connection verified ✓"
else
    echo "WARNING: spark_default connection not found or error retrieving it"
    echo "Current Airflow connections:"
    airflow connections list || echo "Error listing connections"
fi

# Check network connectivity to services
echo "=== Network Connectivity ==="
for service in kafka:9092 cassandra:9042 prometheus:9090 minio:9000; do
  host=$(echo $service | cut -d':' -f1)
  port=$(echo $service | cut -d':' -f2)
  echo -n "Checking $service: "
  nc -z -v -w5 $host $port 2>/dev/null && echo "Connected" || echo "Failed to connect to $service"
done
echo ""

# Check specific Kafka ports
echo "Checking Kafka connectivity:"
nc -zv kafka 29092 2>/dev/null && echo "Connected to Kafka:29092" || echo "Cannot connect to Kafka:29092"
echo ""

# Verify connectivity to other services
echo -e "\n==== Verifying connectivity to services ===="
services=("kafka:9092" "cassandra:9042" "prometheus:9090" "spark-master:7077")
for service in "${services[@]}"; do
    host=${service%:*}
    port=${service#*:}
    echo "Checking connectivity to $host:$port..."
    if nc -z -w 5 $host $port 2>/dev/null; then
        echo "$host:$port is reachable ✓"
    else
        echo "WARNING: Could not connect to $host:$port"
    fi
done

# Summarize findings
echo -e "\n==== Environment verification summary ===="
echo "✓ Verification completed"

echo "For any warnings or errors, please check the logs above for details"
exit 0

# Check Airflow connections
echo "=== Airflow Connections ==="
airflow connections get spark_default 2>/dev/null && echo "✓ spark_default connection exists" || echo "WARNING: spark_default connection is missing"
echo "spark_default connection will be created automatically by the entrypoint script"
echo ""

# Environment variables
echo "=== Environment Variables ==="
echo "JAVA_HOME=$JAVA_HOME"
echo "PYTHONPATH=$PYTHONPATH"
echo "PATH=$PATH"

echo "===== Environment Verification Complete ====="
