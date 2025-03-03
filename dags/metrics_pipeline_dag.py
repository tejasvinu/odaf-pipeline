from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.providers.apache.spark.operators.spark_submit import SparkSubmitOperator

default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'simplified_metrics_pipeline',
    default_args=default_args,
    description='Pipeline for collecting simplified metrics',
    schedule_interval=timedelta(minutes=5),
    start_date=datetime(2023, 1, 1),
    catchup=False,
    tags=['metrics', 'spark', 'kafka', 'cassandra'],
)

# Check service dependencies
check_kafka = BashOperator(
    task_id='check_kafka',
    bash_command='nc -z kafka 29092',
    dag=dag,
)

check_cassandra = BashOperator(
    task_id='check_cassandra',
    bash_command='nc -z cassandra 9042',
    dag=dag,
)

check_prometheus = BashOperator(
    task_id='check_prometheus',
    bash_command='nc -z prometheus 9090',
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
        'spark.cores.max': '2'
    },
    dag=dag,
)

# Define task dependencies
[check_kafka, check_cassandra, check_prometheus] >> start_prometheus_kafka >> start_metrics_processor