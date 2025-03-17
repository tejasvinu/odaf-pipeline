from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.providers.apache.spark.operators.spark_submit import SparkSubmitOperator
from airflow.operators.python import PythonOperator
from airflow.models import Variable
import os
import subprocess
import json

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
    description='Pipeline for collecting and processing metrics with node tracking',
    schedule_interval=timedelta(minutes=5),
    start_date=datetime(2023, 1, 1),
    catchup=False,
    tags=['metrics', 'spark', 'kafka', 'cassandra'],
)

# Set up Java environment with improved error handling
setup_java = BashOperator(
    task_id='setup_java',
    bash_command='''
    # Verify Java is installed and configured
    echo "Checking Java installation..."
    export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
    export PATH=$JAVA_HOME/bin:$PATH
    
    if command -v java >/dev/null 2>&1; then
        which java
        java -version
        echo "JAVA_HOME=$JAVA_HOME"
        ls -la $JAVA_HOME/bin/java || echo "Java binary not found in $JAVA_HOME/bin/"
    else
        echo "ERROR: Java not found in PATH"
        echo "Current PATH=$PATH"
        echo "Looking for Java in standard locations..."
        find /usr/lib/jvm -name "java" 2>/dev/null || echo "No Java installation found"
        exit 1
    fi
    ''',
    env={'JAVA_HOME': '/usr/lib/jvm/java-11-openjdk-amd64', 'PATH': '/usr/lib/jvm/java-11-openjdk-amd64/bin:${PATH}'},
    dag=dag,
)

# Health checks for essential services
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

# Create Kafka topics with node identification
create_kafka_topics = BashOperator(
    task_id='create_kafka_topics',
    bash_command='''
    for topic in node-metrics node-resource-usage node-health-status; do
        kafka-topics.sh --create --if-not-exists \
            --bootstrap-server kafka:29092 \
            --replication-factor 1 \
            --partitions 3 \
            --config retention.ms=86400000 \
            --topic $topic || echo "Topic $topic already exists"
    done
    ''',
    dag=dag,
)

# Initialize Cassandra schema with node tracking
init_schema = SparkSubmitOperator(
    task_id='init_schema',
    conn_id='spark_default',
    application=os.path.join('/', 'opt', 'airflow', 'dags', 'spark_scripts', 'metrics_processor.py'),
    conf={
        'spark.driver.memory': '1g',
        'spark.executor.memory': '1g',
        'spark.cassandra.connection.host': 'cassandra',
        'spark.cassandra.connection.port': '9042',
        'spark.master': 'local[*]',
        'spark.yarn.appMasterEnv.JAVA_HOME': '/usr/lib/jvm/java-11-openjdk-amd64',
        'spark.yarn.appMasterEnv.PATH': '/usr/lib/jvm/java-11-openjdk-amd64/bin:/usr/local/bin:${PATH}'
    },
    application_args=['--init-schema'],
    name='init-schema',
    verbose=True,
    spark_binary="spark-submit",  # Add this line to specify which spark binary to use
    env_vars={
        'JAVA_HOME': '/usr/lib/jvm/java-11-openjdk-amd64',
        'PATH': '/usr/lib/jvm/java-11-openjdk-amd64/bin:/bin:/usr/bin:/usr/local/bin:${PATH}',
    },
    dag=dag,
)

# Start the Prometheus to Kafka connector with node identification
start_prometheus_kafka = SparkSubmitOperator(
    task_id='start_prometheus_kafka',
    conn_id='spark_default',
    application=os.path.join('/', 'opt', 'airflow', 'dags', 'spark_scripts', 'prometheus_to_kafka.py'),
    conf={
        'spark.driver.memory': '1g',
        'spark.executor.memory': '1g',
        'spark.master': 'local[*]'
    },
    name='prometheus-kafka',
    spark_binary="spark-submit",  # Add this line to specify which spark binary to use
    env_vars={
        'JAVA_HOME': '/usr/lib/jvm/java-11-openjdk-amd64',
        'PATH': '/usr/lib/jvm/java-11-openjdk-amd64/bin:/bin:/usr/bin:/usr/local/bin:${PATH}',
        'PROMETHEUS_URL': 'http://prometheus:9090',
        'KAFKA_BOOTSTRAP_SERVERS': 'kafka:29092',
        'INCLUDE_NODE_METADATA': 'true',
        'SCRAPE_INTERVAL': '60'
    },
    dag=dag,
)

# Process metrics and store in Cassandra with node tracking
process_metrics = SparkSubmitOperator(
    task_id='process_metrics',
    conn_id='spark_default',
    application=os.path.join('/', 'opt', 'airflow', 'dags', 'spark_scripts', 'metrics_processor.py'),
    conf={
        'spark.driver.memory': '1g',
        'spark.executor.memory': '1g',
        'spark.cores.max': '2',
        'spark.cassandra.connection.host': 'cassandra',
        'spark.cassandra.connection.port': '9042',
        'spark.master': 'local[*]'
    },
    spark_binary="spark-submit",  # Add this line to specify which spark binary to use
    env_vars={
        'JAVA_HOME': '/usr/lib/jvm/java-11-openjdk-amd64',
        'PATH': '/usr/lib/jvm/java-11-openjdk-amd64/bin:/bin:/usr/bin:/usr/local/bin:${PATH}',
        'KAFKA_BOOTSTRAP_SERVERS': 'kafka:29092',
        'CASSANDRA_HOST': 'cassandra'
    },
    name='metrics-processor',
    dag=dag,
)

# Monitor pipeline health with node status
monitor_pipeline = BashOperator(
    task_id='monitor_pipeline',
    bash_command='''
    # Check Kafka topics and partitions
    echo "Checking Kafka topics and partitions..."
    kafka-topics.sh --bootstrap-server kafka:29092 --list | grep "node-" && \
    kafka-topics.sh --bootstrap-server kafka:29092 --describe | grep "node-" && \
    
    # Check Cassandra keyspaces and tables
    echo "Checking Cassandra schema..."
    echo "describe keyspace metrics;" | cqlsh cassandra 9042 && \
    echo "select distinct node_name from metrics.node_metrics limit 5;" | cqlsh cassandra 9042 && \
    
    echo "Pipeline monitoring completed"
    ''',
    dag=dag,
)

# Define task dependencies
setup_java >> [check_kafka, check_cassandra, check_prometheus] >> create_kafka_topics >> init_schema
init_schema >> start_prometheus_kafka >> process_metrics >> monitor_pipeline