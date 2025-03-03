#!/bin/bash

# Create directory structure for volumes
mkdir -p volumes/prometheus_data volumes/grafana_data
chmod -R 777 volumes/prometheus_data volumes/grafana_data

# Create Grafana provisioning directories
mkdir -p grafana-provisioning/datasources grafana-provisioning/dashboards
chmod -R 777 grafana-provisioning

# Create a default datasource for Prometheus
cat > grafana-provisioning/datasources/prometheus.yaml << EOL
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

# Create a default dashboard provider
cat > grafana-provisioning/dashboards/default.yaml << EOL
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

# Create directories for Docker volumes
mkdir -p volumes/spark volumes/spark-worker-1 volumes/zookeeper_data volumes/kafka_data 
mkdir -p volumes/cassandra_data volumes/minio_data volumes/postgres_data volumes/airflow_logs volumes/airflow_config
mkdir -p notebooks dags plugins

# Set proper permissions
chmod -R 777 volumes notebooks dags plugins
echo "Setup complete. You can now run 'docker-compose up -d' to start the services."
