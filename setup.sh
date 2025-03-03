#!/bin/bash

# Ensure script fails on any error
set -e

# Function to create directory with parent directories
create_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" 2>/dev/null || { echo "Error creating directory $dir"; exit 1; }
        echo "Created directory: $dir"
    else
        echo "Directory already exists: $dir"
    fi
}

echo "Creating directory structure..."

# Create base directories using array for better readability
directories=(
    "volumes/spark"
    "volumes/spark-worker-1"
    "volumes/zookeeper_data"
    "volumes/kafka_data"
    "volumes/cassandra_data"
    "volumes/minio_data"
    "volumes/postgres_data"
    "volumes/airflow_logs"
    "volumes/airflow_config"
    "volumes/prometheus_data"
    "volumes/grafana_data"
    "volumes/data"
    "volumes/jupyter_data"
    "dags/spark_scripts"
    "plugins"
    "notebooks"
)

# Create all directories
for dir in "${directories[@]}"; do
    create_dir "$dir"
done

# Create specialized directories
create_dir "volumes/minio_data/metrics"
create_dir "volumes/spark/checkpoints"
create_dir "volumes/airflow_logs"
create_dir "grafana-provisioning/datasources"
create_dir "grafana-provisioning/dashboards"

# Ensure proper permissions (works on both Linux and macOS)
if [ "$(uname)" != "Windows_NT" ]; then
    chmod -R 777 volumes || true
    chmod -R 777 dags || true
    chmod -R 777 plugins || true
    chmod -R 777 notebooks || true
fi

# Set up Grafana datasource
cat > grafana-provisioning/datasources/prometheus.yml << EOL
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    orgId: 1
    url: http://prometheus:9090
    basicAuth: false
    isDefault: true
    editable: true
EOL

# Set up Grafana dashboard provider
cat > grafana-provisioning/dashboards/dashboard.yml << EOL
apiVersion: 1

providers:
  - name: 'Default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOL

# Create requirements.txt for Python dependencies
cat > requirements.txt << EOL
apache-airflow-providers-apache-spark
kafka-python==2.0.2
cassandra-driver==3.25.0
boto3==1.28.38
prometheus-client==0.16.0
EOL

echo "Setup completed successfully!"
echo "Next steps:"
echo "1. Run 'docker-compose up -d' to start the services"
echo "2. Wait for all services to initialize"
echo "3. Run './check_health.sh' to verify the setup"
