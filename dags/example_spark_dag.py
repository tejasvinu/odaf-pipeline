from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator
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
    'spark_pipeline',
    default_args=default_args,
    description='A simple pipeline using Spark',
    schedule_interval=timedelta(days=1),
    start_date=datetime(2023, 1, 1),
    catchup=False,
    tags=['spark', 'etl'],
)

# Task to check if Spark is available
check_spark = BashOperator(
    task_id='check_spark_available',
    bash_command='nc -z spark-master 7077',
    dag=dag,
)

# Python function to prepare data
def prepare_data():
    """Prepare data for processing"""
    print("Preparing data for Spark processing")
    return "Data preparation complete"

prepare_task = PythonOperator(
    task_id='prepare_data',
    python_callable=prepare_data,
    dag=dag,
)

# Task to run Spark job
spark_job = SparkSubmitOperator(
    task_id='spark_job',
    application='/opt/airflow/dags/spark_scripts/example_job.py',
    conn_id='spark_default',
    verbose=True,
    conf={
        'spark.driver.memory': '1g',
        'spark.executor.memory': '1g',
        'spark.executor.cores': '1'
    },
    java_class=None,
    dag=dag,
)

# Task to log the results
log_results = BashOperator(
    task_id='log_results',
    bash_command='echo "Spark job completed at $(date)"',
    dag=dag,
)

# Define the workflow
check_spark >> prepare_task >> spark_job >> log_results
