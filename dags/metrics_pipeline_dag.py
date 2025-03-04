from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.providers.apache.spark.operators.spark_submit import SparkSubmitOperator
from airflow.operators.python import PythonOperator
from airflow.models import Variable
import os

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

# Set up Java environment
setup_java = BashOperator(
    task_id='setup_java',
    bash_command='''
    # Install OpenJDK if not present
    if ! command -v java &> /dev/null; then
        apt-get update && apt-get install -y openjdk-11-jdk
    fi
    # Export JAVA_HOME
    export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
    echo "JAVA_HOME set to $JAVA_HOME"
    ''',
    dag=dag,
)

# Health checks for services using netcat (available in both busybox and full netcat)
check_kafka = BashOperator(
    task_id='check_kafka',
    bash_command='''kafka_host="kafka" && kafka_port="9092" && (nc -z $kafka_host $kafka_port || nc -w 1 $kafka_host $kafka_port) || (echo "Kafka is not available" && exit 1)''',
    dag=dag,
)

check_cassandra = BashOperator(
    task_id='check_cassandra',
    bash_command='''cassandra_host="cassandra" && cassandra_port="9042" && (nc -z $cassandra_host $cassandra_port || nc -w 1 $cassandra_host $cassandra_port) || (echo "Cassandra is not available" && exit 1)''',
    dag=dag,
)

check_prometheus = BashOperator(
    task_id='check_prometheus',
    bash_command='''prometheus_host="prometheus" && prometheus_port="9090" && (nc -z $prometheus_host $prometheus_port || nc -w 1 $prometheus_host $prometheus_port) || (echo "Prometheus is not available" && exit 1)''',
    dag=dag,
)

check_minio = BashOperator(
    task_id='check_minio',
    bash_command='''minio_host="minio" && minio_port="9000" && (nc -z $minio_host $minio_port || nc -w 1 $minio_host $minio_port) || (echo "MinIO is not available" && exit 1)''',
    dag=dag,
)

# Create Kafka topics using the kafka-topics script (works across distributions)
create_kafka_topics = BashOperator(
    task_id='create_kafka_topics',
    bash_command='''
    for topic in ipmi-metrics node-metrics gpu-metrics slurm-metrics; do
        kafka-topics.sh --create --if-not-exists \
            --bootstrap-server kafka:29092 \
            --replication-factor 1 \
            --partitions 1 \
            --topic $topic || echo "Topic $topic already exists"
    done
    ''',
    dag=dag,
)

# Initialize Cassandra schema and MinIO bucket
init_storage = SparkSubmitOperator(
    task_id='init_storage',
    application=os.path.join('/', 'opt', 'airflow', 'dags', 'spark_scripts', 'metrics_processor.py'),
    conn_id='spark_default',
    conf={
        'spark.driver.memory': '1g',
        'spark.executor.memory': '1g',
        'spark.jars.packages': 'org.apache.hadoop:hadoop-aws:3.3.2',
        'spark.master': 'local[*]',  # Set master directly in conf
    },
    application_args=['--init-only'],
    name='metrics-init',
    verbose=True,
    env_vars={
        'MINIO_ENDPOINT': 'http://minio:9000',
        'MINIO_ACCESS_KEY': 'minioadmin',
        'MINIO_SECRET_KEY': 'minioadmin',
        'MINIO_BUCKET': 'metrics',
        'JAVA_HOME': '/usr/lib/jvm/java-11-openjdk-amd64'
    },
    # Remove the problematic spark_binary parameter
    dag=dag,
)

# Start the Prometheus to Kafka connector
start_prometheus_kafka = SparkSubmitOperator(
    task_id='start_prometheus_kafka',
    application=os.path.join('/', 'opt', 'airflow', 'dags', 'spark_scripts', 'prometheus_to_kafka.py'),
    conn_id='spark_default',
    conf={
        'spark.driver.memory': '1g',
        'spark.executor.memory': '1g',
        'spark.master': 'local[*]',  # Set master directly in conf
    },
    name='prometheus-kafka',
    env_vars={
        'JAVA_HOME': '/usr/lib/jvm/java-11-openjdk-amd64'
    },
    # Remove the problematic spark_binary parameter
    dag=dag,
)

# Start the metrics processor
start_metrics_processor = SparkSubmitOperator(
    task_id='start_metrics_processor',
    application=os.path.join('/', 'opt', 'airflow', 'dags', 'spark_scripts', 'metrics_processor.py'),
    conn_id='spark_default',
    conf={
        'spark.driver.memory': '1g',
        'spark.executor.memory': '1g',
        'spark.cores.max': '2',
        'spark.jars.packages': 'org.apache.hadoop:hadoop-aws:3.3.2',
        'spark.master': 'local[*]',  # Set master directly in conf
    },
    env_vars={
        'MINIO_ENDPOINT': 'http://minio:9000',
        'MINIO_ACCESS_KEY': 'minioadmin',
        'MINIO_SECRET_KEY': 'minioadmin',
        'MINIO_BUCKET': 'metrics',
        'JAVA_HOME': '/usr/lib/jvm/java-11-openjdk-amd64'
    },
    name='metrics-processor',
    # Remove the problematic spark_binary parameter
    dag=dag,
)

# Monitor pipeline health with cross-platform compatible commands
monitor_pipeline = BashOperator(
    task_id='monitor_pipeline',
    bash_command='''
    # Check Kafka topics
    kafka-topics.sh --bootstrap-server kafka:29092 --list && \
    echo "Checking Kafka topics and partitions..." && \
    # Setup and check MinIO using mc
    (mc config host add myminio http://minio:9000 minioadmin minioadmin || true) && \
    mc ls myminio/metrics/ && \
    echo "Pipeline monitoring completed"
    ''',
    dag=dag,
)

# Define task dependencies
setup_java >> [check_kafka, check_cassandra, check_prometheus, check_minio] >> create_kafka_topics >> init_storage
init_storage >> start_prometheus_kafka >> start_metrics_processor >> monitor_pipeline