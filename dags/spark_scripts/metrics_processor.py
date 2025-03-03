from pyspark.sql import SparkSession
import sys
from pyspark.sql.functions import from_json, col, to_json, struct
from pyspark.sql.types import StructType, StructField, StringType, DoubleType
import os

# MinIO configuration
MINIO_ENDPOINT = os.environ.get('MINIO_ENDPOINT', 'http://minio:9000')
MINIO_ACCESS_KEY = os.environ.get('MINIO_ACCESS_KEY', 'minioadmin')
MINIO_SECRET_KEY = os.environ.get('MINIO_SECRET_KEY', 'minioadmin')
MINIO_BUCKET = os.environ.get('MINIO_BUCKET', 'metrics')

def create_spark_session():
    """Create and return a Spark Session configured for streaming."""
    return (SparkSession.builder
            .appName("Simplified Metrics Processor")
            .config("spark.jars.packages", 
                   "org.apache.spark:spark-sql-kafka-0-10_2.12:3.3.0,"
                   "com.datastax.spark:spark-cassandra-connector_2.12:3.3.0,"
                   "org.apache.hadoop:hadoop-aws:3.3.2")
            .config("spark.cassandra.connection.host", "cassandra")
            .config("spark.cassandra.connection.keep_alive_ms", "60000")
            .config("spark.hadoop.fs.s3a.endpoint", MINIO_ENDPOINT)
            .config("spark.hadoop.fs.s3a.access.key", MINIO_ACCESS_KEY)
            .config("spark.hadoop.fs.s3a.secret.key", MINIO_SECRET_KEY)
            .config("spark.hadoop.fs.s3a.path.style.access", "true")
            .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
            .getOrCreate())

def setup_cassandra_schema(spark):
    """Create keyspace and tables in Cassandra if they don't exist."""
    try:
        # Create keyspace
        spark.sql("""
            CREATE KEYSPACE IF NOT EXISTS metrics
            WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '1'}
        """)
        
        # Create tables with proper partitioning
        tables = ['ipmi_metrics', 'node_metrics', 'gpu_metrics', 'slurm_metrics']
        for table in tables:
            spark.sql(f"""
                CREATE TABLE IF NOT EXISTS metrics.{table} (
                    name STRING,
                    value DOUBLE,
                    timestamp STRING,
                    PRIMARY KEY (name, timestamp)
                )
                USING cassandra
                OPTIONS (
                    table "{table}",
                    keyspace "metrics"
                )
            """)
        print("Successfully created Cassandra schema")
        return True
    except Exception as e:
        print(f"Error creating Cassandra schema: {e}")
        return False

def setup_minio(spark):
    """Create MinIO bucket if it doesn't exist."""
    try:
        import boto3
        s3_client = boto3.client('s3',
                              endpoint_url=MINIO_ENDPOINT,
                              aws_access_key_id=MINIO_ACCESS_KEY,
                              aws_secret_access_key=MINIO_SECRET_KEY,
                              verify=False)
        
        try:
            s3_client.head_bucket(Bucket=MINIO_BUCKET)
        except:
            s3_client.create_bucket(Bucket=MINIO_BUCKET)
            print(f"Created MinIO bucket: {MINIO_BUCKET}")
        
        return True
    except Exception as e:
        print(f"Error setting up MinIO: {e}")
        return False

def foreach_batch_function(df, epoch_id, topic):
    """Process each batch of data."""
    try:
        # Write to MinIO in Parquet format
        timestamp = df.select("timestamp").first()[0].split("T")[0]  # Get date part
        minio_path = f"s3a://{MINIO_BUCKET}/{topic}/{timestamp}"
        
        df.write.mode("append").parquet(minio_path)
        print(f"Wrote batch to MinIO: {minio_path}")
        
        # Write to Cassandra
        table_name = topic.replace("-", "_")
        (df.write
         .format("org.apache.spark.sql.cassandra")
         .mode("append")
         .options(table=table_name, keyspace="metrics")
         .save())
        
        print(f"Wrote batch to Cassandra table: metrics.{table_name}")
    except Exception as e:
        print(f"Error in foreach_batch_function: {e}")
        raise

def process_metrics_stream(spark, topic, table_name):
    """Process metrics from a Kafka topic and write to both Cassandra and MinIO."""
    try:
        # Define schema for the simplified metrics
        metric_schema = StructType([
            StructField("name", StringType(), True),
            StructField("value", DoubleType(), True),
            StructField("timestamp", StringType(), True)
        ])
        
        # Read from Kafka with error handling
        stream_df = (spark
                    .readStream
                    .format("kafka")
                    .option("kafka.bootstrap.servers", "kafka:29092")
                    .option("subscribe", topic)
                    .option("startingOffsets", "earliest")
                    .option("failOnDataLoss", "false")
                    .load())
        
        # Parse JSON and select fields
        parsed_df = (stream_df
                    .selectExpr("CAST(value AS STRING) as json")
                    .select(from_json("json", metric_schema).alias("data"))
                    .select("data.*"))
        
        # Write stream with foreachBatch to handle both MinIO and Cassandra
        query = (parsed_df.writeStream
                .foreachBatch(lambda df, epoch_id: foreach_batch_function(df, epoch_id, topic))
                .option("checkpointLocation", f"/tmp/checkpoints/{topic}")
                .start())
        
        return query
    except Exception as e:
        print(f"Error processing stream for topic {topic}: {e}")
        raise

def main():
    """Main function to start the Spark Streaming jobs."""
    spark = create_spark_session()
    print(f"Spark version: {spark.version}")
    
    # Check if running in initialization mode
    if len(sys.argv) > 1 and sys.argv[1] == '--init-only':
        success = setup_cassandra_schema(spark) and setup_minio(spark)
        sys.exit(0 if success else 1)
    
    # Ensure schemas exist
    setup_cassandra_schema(spark)
    setup_minio(spark)
    
    # Process each metric type
    queries = []
    metric_configs = [
        ("ipmi-metrics", "ipmi_metrics"),
        ("node-metrics", "node_metrics"),
        ("gpu-metrics", "gpu_metrics"),
        ("slurm-metrics", "slurm_metrics")
    ]
    
    try:
        for topic, table in metric_configs:
            print(f"Setting up stream for {topic} -> {table}")
            query = process_metrics_stream(spark, topic, table)
            queries.append(query)
        
        print("All streaming queries started. Waiting for termination...")
        for query in queries:
            query.awaitTermination()
    except Exception as e:
        print(f"Error in main processing loop: {e}")
        # Clean up any running queries
        for query in queries:
            if query and query.isActive:
                query.stop()
        raise

if __name__ == "__main__":
    main()