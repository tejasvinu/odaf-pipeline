from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.providers.apache.spark.operators.spark_submit import SparkSubmitOperator
from airflow.operators.python import PythonOperator
from airflow.models import Variable

default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 3,
    'retry_delay': timedelta(minutes=2),
}

dag = DAG(
    'metrics_pipeline',
    default_args=default_args,
    description='Pipeline for collecting and processing metrics',
    schedule_interval=timedelta(minutes=5),
    start_date=datetime(2023, 1, 1),
    catchup=False,
    tags=['metrics', 'spark', 'kafka', 'cassandra', 'minio'],
)

# Check service dependencies with proper error messages
check_kafka = BashOperator(
    task_id='check_kafka',
    bash_command='nc -z kafka 29092 || (echo "Kafka is not available" && exit 1)',
    dag=dag,
)

check_cassandra = BashOperator(
    task_id='check_cassandra',
    bash_command='nc -z cassandra 9042 || (echo "Cassandra is not available" && exit 1)',
    dag=dag,
)

check_prometheus = BashOperator(
    task_id='check_prometheus',
    bash_command='nc -z prometheus 9090 || (echo "Prometheus is not available" && exit 1)',
    dag=dag,
)

check_minio = BashOperator(
    task_id='check_minio',
    bash_command='nc -z minio 9000 || (echo "MinIO is not available" && exit 1)',
    dag=dag,
)

# Create Kafka topics
create_kafka_topics = BashOperator(
    task_id='create_kafka_topics',
    bash_command='''
    kafka-topics.sh --create --if-not-exists --bootstrap-server kafka:29092 --replication-factor 1 --partitions 1 --topic ipmi-metrics &&
    kafka-topics.sh --create --if-not-exists --bootstrap-server kafka:29092 --replication-factor 1 --partitions 1 --topic node-metrics &&
    kafka-topics.sh --create --if-not-exists --bootstrap-server kafka:29092 --replication-factor 1 --partitions 1 --topic gpu-metrics &&
    kafka-topics.sh --create --if-not-exists --bootstrap-server kafka:29092 --replication-factor 1 --partitions 1 --topic slurm-metrics
    ''',
    dag=dag,
)

# Initialize Cassandra schema and MinIO bucket
init_storage = SparkSubmitOperator(
    task_id='init_storage',
    application='/opt/airflow/dags/spark_scripts/metrics_processor.py',
    conn_id='spark_default',
    conf={
        'spark.driver.memory': '1g',
        'spark.executor.memory': '1g',
        'spark.jars.packages': 'org.apache.hadoop:hadoop-aws:3.3.2'
    },
    application_args=['--init-only'],
    env_vars={
        'MINIO_ENDPOINT': 'http://minio:9000',
        'MINIO_ACCESS_KEY': 'minioadmin',
        'MINIO_SECRET_KEY': 'minioadmin',
        'MINIO_BUCKET': 'metrics'
    },
    dag=dag,
)

# Start the Prometheus to Kafka connector
start_prometheus_kafka = SparkSubmitOperator(
    task_id='start_prometheus_kafka',
    application='/opt/airflow/dags/spark_scripts/prometheus_to_kafka.py',
    conn_id='spark_default',
    conf={
        'spark.driver.memory': '1g',
        'spark.executor.memory': '1g'
    },
    dag=dag,
)

# Start the metrics processor
start_metrics_processor = SparkSubmitOperator(
    task_id='start_metrics_processor',
    application='/opt/airflow/dags/spark_scripts/metrics_processor.py',
    conn_id='spark_default',
    conf={
        'spark.driver.memory': '1g',
        'spark.executor.memory': '1g',
        'spark.cores.max': '2',
        'spark.jars.packages': 'org.apache.hadoop:hadoop-aws:3.3.2'
    },
    env_vars={
        'MINIO_ENDPOINT': 'http://minio:9000',
        'MINIO_ACCESS_KEY': 'minioadmin',
        'MINIO_SECRET_KEY': 'minioadmin',
        'MINIO_BUCKET': 'metrics'
    },
    dag=dag,
)

# Monitor pipeline health
monitor_pipeline = BashOperator(
    task_id='monitor_pipeline',
    bash_command='''
    kafka-topics.sh --bootstrap-server kafka:29092 --describe &&
    echo "Checking Kafka topics and partitions..." &&
    mc config host add myminio http://minio:9000 minioadmin minioadmin &&
    mc ls myminio/metrics/ &&
    echo "Pipeline monitoring completed"
    ''',
    dag=dag,
)

# Define task dependencies
[check_kafka, check_cassandra, check_prometheus, check_minio] >> create_kafka_topics >> init_storage
init_storage >> start_prometheus_kafka >> start_metrics_processor >> monitor_pipeline