# ODAF Pipeline - Optimized for Development

This repository contains an optimized data pipeline setup for development, featuring:

- Apache Spark for data processing
- Apache Kafka for message streaming
- Apache Cassandra for data storage
- Apache Airflow for workflow orchestration
- JupyterLab for interactive analysis
- MinIO for S3-compatible object storage
- Prometheus and Grafana for monitoring

## Resource Optimization

This setup has been optimized for local development by:

1. Using single instances where possible (Kafka, Cassandra)
2. Reducing memory allocations for resource-intensive services
3. Using local file paths for persistent storage
4. Adding Airflow for workflow orchestration

## Directory Structure

```
/odaf-pipeline/
├── dags/                  # Airflow DAG definitions
│   └── spark_scripts/     # Python scripts for Spark jobs
├── notebooks/             # Jupyter notebooks
├── plugins/               # Airflow plugins
├── volumes/               # Persistent storage
│   ├── airflow_logs/
│   ├── cassandra_data/
│   ├── data/              # Shared data directory
│   ├── grafana_data/
│   ├── jupyter_data/
│   ├── kafka_data/
│   ├── minio_data/
│   ├── postgres_data/
│   ├── prometheus_data/
│   ├── spark/
│   └── zookeeper_data/
├── .env                   # Environment variables
├── docker-compose.yml     # Services definition
├── Dockerfile.jupyterlab  # JupyterLab container definition
├── prometheus.yml         # Prometheus configuration
└── spark-defaults.conf    # Spark configuration
```

## Getting Started

1. Ensure Docker and Docker Compose are installed
2. Clone this repository
3. Start the services:

```bash
docker-compose up -d
```

4. Access services via the following URLs:
   - Spark UI: http://localhost:8084
   - Kafka UI: http://localhost:8085
   - JupyterLab: http://localhost:8890
   - Airflow: http://localhost:8080 (username: airflow, password: airflow)
   - MinIO: http://localhost:9001 (username: minioadmin, password: minioadmin)
   - Grafana: http://localhost:3000 (username: admin, password: admin)
   - Prometheus: http://localhost:9090

## Service Ports

The following ports are configured in the docker-compose setup:

- **Spark Master**
  - UI: 8084
  - Spark Master: 7077
- **Spark Worker**
  - (No external ports exposed)
- **Zookeeper**
  - 2182
- **Kafka**
  - Broker: 9092
- **Kafka UI**
  - 8085
- **Cassandra**
  - 9042
- **MinIO**
  - API: 9000
  - Console: 9001
- **Prometheus**
  - 9091
- **Grafana**
  - 3001
- **JupyterLab**
  - 8890 (maps to container port 8888)
- **Airflow**
  - 8081 (maps to container port 8080)
- **PostgreSQL**
  - 5432

## Working with the Stack

### Running Spark Jobs via Airflow

Airflow DAGs are defined in the `dags` directory. To create a new Spark job:

1. Add a Python script in `dags/spark_scripts/`
2. Create a new DAG or modify the example in `dags/example_spark_dag.py`
3. Trigger the DAG from the Airflow UI

### Working with Jupyter

Access JupyterLab at http://localhost:8890 and create new notebooks to interact with:

- Spark via the `SparkSession`
- Kafka using `kafka-python`
- Cassandra through the `cassandra-driver`

Example notebook for connecting to Spark:

```python
import findspark
findspark.init()

from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("JupyterSparkSession") \
    .master("spark://spark-master:7077") \
    .getOrCreate()

print(f"Spark version: {spark.version}")
```

## Scaling for Production

To scale this setup for production:
- Increase memory allocations in docker-compose.yml
- Add multiple Kafka brokers and Cassandra nodes
- Configure authentication for services
- Use external storage volumes
- Set up proper networking and security
