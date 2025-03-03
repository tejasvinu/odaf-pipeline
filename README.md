# ODAF Pipeline - Optimized for Development

This repository contains an optimized data pipeline setup for development, featuring:

- Apache Spark for data processing
- Apache Kafka for message streaming
- Apache Cassandra for data storage
- Apache Airflow for workflow orchestration
- JupyterLab for interactive analysis
- MinIO for S3-compatible object storage
- Prometheus and Grafana for monitoring

## 🚀 Quick Start

1. Ensure Docker and Docker Compose are installed
2. Clone this repository
3. Run the setup script to prepare directories and configurations:
```bash
chmod +x setup.sh
./setup.sh
```
4. Start the services:
```bash
docker-compose up -d
```
5. Access services via the provided URLs (see [Service URLs](#service-urls))

## 📊 Resource Optimization

This setup has been optimized for local development by:

1. Using single instances where possible (Kafka, Cassandra)
2. Reducing memory allocations for resource-intensive services
3. Using local file paths for persistent storage
4. Adding Airflow for workflow orchestration

## 📁 Directory Structure

```
/odaf-pipeline/
├── dags/                    # Airflow DAG definitions
│   └── spark_scripts/       # Python scripts for Spark jobs
├── grafana-provisioning/    # Grafana provisioning files
│   ├── dashboards/          # Dashboard configurations
│   └── datasources/         # Datasource configurations
├── notebooks/               # Jupyter notebooks
├── plugins/                 # Airflow plugins
├── volumes/                 # Persistent storage
│   ├── airflow_logs/
│   ├── airflow_config/
│   ├── cassandra_data/
│   ├── data/                # Shared data directory
│   ├── grafana_data/
│   ├── jupyter_data/
│   ├── kafka_data/
│   ├── minio_data/
│   ├── postgres_data/
│   ├── prometheus_data/
│   ├── spark/
│   ├── spark-worker-1/
│   └── zookeeper_data/
├── .env                     # Environment variables
├── docker-compose.yml       # Services definition
├── Dockerfile.airflow       # Airflow container definition
├── Dockerfile.jupyterlab    # JupyterLab container definition
├── prometheus.yml           # Prometheus configuration
├── setup.sh                 # Setup script
└── spark-defaults.conf      # Spark configuration
```

## 🔗 Service URLs

| Service       | URL                     | Credentials                            |
|---------------|-------------------------|------------------------------------|
| Spark UI      | http://localhost:8084   | -                                  |
| Kafka UI      | http://localhost:8085   | -                                  |
| JupyterLab    | http://localhost:8890   | No authentication                  |
| Airflow       | http://localhost:8081   | Username: `airflow`<br>Password: `airflow` |
| MinIO         | http://localhost:9001   | Username: `minioadmin`<br>Password: `minioadmin` |
| Grafana       | http://localhost:3001   | Username: `admin`<br>Password: `admin` |
| Prometheus    | http://localhost:9091   | -                                  |
| PostgreSQL    | localhost:5432          | Username: `airflow`<br>Password: `airflow` |

## 🔌 Service Ports

| Service            | Port(s)                  | Description                 |
|--------------------|--------------------------|----------------------------|
| **Spark Master**   | 8084, 7077              | UI, Spark Master           |
| **Zookeeper**      | 2182                    | Client port                |
| **Kafka**          | 9092                    | Broker                     |
| **Kafka UI**       | 8085                    | Management UI              |
| **Cassandra**      | 9042                    | CQL native transport       |
| **MinIO**          | 9000, 9001              | API, Console               |
| **Prometheus**     | 9091                    | Web UI                     |
| **Grafana**        | 3001                    | Web UI                     |
| **JupyterLab**     | 8890                    | Web UI                     |
| **Airflow**        | 8081                    | Web UI                     |
| **PostgreSQL**     | 5432                    | Database                   |

## 💻 Working with the Stack

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

### Monitoring with Grafana and Prometheus

1. Access Grafana at http://localhost:3001 (username: `admin`, password: `admin`)
2. The setup script has already configured Prometheus as a data source
3. Create dashboards to monitor your Spark jobs, Kafka topics, and system resources

## 🚀 Scaling for Production

To scale this setup for production:
- Increase memory allocations in docker-compose.yml
- Add multiple Kafka brokers and Cassandra nodes
- Configure authentication for services
- Use external storage volumes
- Set up proper networking and security

## 🔧 Troubleshooting

### Permission Issues

If you encounter permission issues with volumes, run:

```bash
chmod -R 777 volumes/
```

### Container Startup Problems

Check container logs with:

```bash
docker-compose logs [service-name]
```

### Monitoring Issues

If Prometheus or Grafana don't appear to be working:

1. Ensure both services are running: `docker-compose ps`
2. Check if the monitoring network is properly created
3. Verify that the provisioning files are correctly mounted

## 📚 Additional Resources

- [Apache Spark Documentation](https://spark.apache.org/docs/latest/)
- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Apache Airflow Documentation](https://airflow.apache.org/docs/)
- [JupyterLab Documentation](https://jupyterlab.readthedocs.io/)
- [Prometheus Documentation](https://prometheus.io/docs/introduction/overview/)
- [Grafana Documentation](https://grafana.com/docs/)
