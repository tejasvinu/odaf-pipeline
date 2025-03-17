from pyspark.sql import SparkSession
import sys
from pyspark.sql.functions import from_json, col, to_json, struct, expr
from pyspark.sql.types import StructType, StructField, StringType, DoubleType, MapType, TimestampType
import os

# MinIO configuration
MINIO_ENDPOINT = os.environ.get('MINIO_ENDPOINT', 'http://minio:9000')
MINIO_ACCESS_KEY = os.environ.get('MINIO_ACCESS_KEY', 'minioadmin')
MINIO_SECRET_KEY = os.environ.get('MINIO_SECRET_KEY', 'minioadmin')
MINIO_BUCKET = os.environ.get('MINIO_BUCKET', 'metrics')

def create_spark_session():
    """Create and return a Spark Session configured for streaming."""
    return (SparkSession.builder
            .appName("Node-Aware Metrics Processor")
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
    """Create keyspace and tables in Cassandra for node-aware metrics."""
    try:
        # Test Cassandra connection first
        print("Testing Cassandra connection...")
        spark.sql("SELECT now() FROM system.local").show()
        print("Successfully connected to Cassandra")
        
        # Create keyspace with explicit IF NOT EXISTS
        print("Creating keyspace...")
        spark.sql("""
            CREATE KEYSPACE IF NOT EXISTS metrics
            WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '1'}
        """)
        print("Keyspace creation successful")
        
        # Create tables with node identification
        tables = {
            'node_metrics': """
                CREATE TABLE IF NOT EXISTS metrics.node_metrics (
                    node_name text,
                    instance text,
                    job text,
                    metric_name text,
                    value double,
                    timestamp timestamp,
                    labels map<text, text>,
                    PRIMARY KEY ((node_name), timestamp, metric_name)
                )
            """,
            'node_resource_usage': """
                CREATE TABLE IF NOT EXISTS metrics.node_resource_usage (
                    node_name text,
                    instance text,
                    job text,
                    metric_name text,
                    value double,
                    timestamp timestamp,
                    labels map<text, text>,
                    PRIMARY KEY ((node_name), timestamp, metric_name)
                )
            """,
            'node_health_status': """
                CREATE TABLE IF NOT EXISTS metrics.node_health_status (
                    node_name text,
                    instance text,
                    job text,
                    metric_name text,
                    value double,
                    timestamp timestamp,
                    labels map<text, text>,
                    PRIMARY KEY ((node_name), timestamp, metric_name)
                )
            """
        }
        
        for table_name, create_stmt in tables.items():
            print(f"Creating table {table_name}...")
            spark.sql(create_stmt)
            # Verify table was created
            spark.sql(f"SELECT COUNT(*) FROM metrics.{table_name} LIMIT 1").show()
            print(f"Successfully created/verified table {table_name}")
            
        print("Successfully created all Cassandra schemas with node tracking")
        return True
    except Exception as e:
        print(f"Error creating Cassandra schema: {str(e)}")
        import traceback
        traceback.print_exc()
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

def get_metric_schema():
    """Define the schema for incoming metrics with node information."""
    return StructType([
        StructField("name", StringType(), True),
        StructField("value", DoubleType(), True),
        StructField("timestamp", StringType(), True),
        StructField("node", StructType([
            StructField("instance", StringType(), True),
            StructField("job", StringType(), True),
            StructField("node_name", StringType(), True),
            StructField("machine", StringType(), True),
            StructField("os", StringType(), True),
            StructField("system", StringType(), True)
        ]), True),
        StructField("group", StringType(), True),
        StructField("labels", MapType(StringType(), StringType()), True)
    ])

def process_metrics_stream(spark, topic, table_name):
    """Process metrics from Kafka and store in Cassandra with node tracking."""
    try:
        # Read from Kafka
        stream_df = (spark
                    .readStream
                    .format("kafka")
                    .option("kafka.bootstrap.servers", "kafka:29092")
                    .option("subscribe", topic)
                    .option("startingOffsets", "earliest")
                    .option("failOnDataLoss", "false")
                    .load())
        # Parse JSON with node information
        metric_schema = get_metric_schema()
        parsed_df = (stream_df
                    .selectExpr("CAST(value AS STRING) as json")
                    .select(from_json("json", metric_schema).alias("data"))
                    .select("data.*"))
        
        # Transform for Cassandra storage
        processed_df = (parsed_df
                       .select(
                           col("node.node_name").alias("node_name"),
                           col("node.instance").alias("instance"),
                           col("node.job").alias("job"),
                           col("name").alias("metric_name"),
                           col("value"),
                           expr("cast(timestamp as timestamp)").alias("timestamp"),
                           col("labels")
                       ))
        
        # Write to Cassandra
        query = (processed_df.writeStream
                .foreachBatch(lambda df, epoch_id: df.write
                            .format("org.apache.spark.sql.cassandra")
                            .options(table=table_name, keyspace="metrics")
                            .mode("append")
                            .save())
                .option("checkpointLocation", f"/tmp/checkpoints/{topic}")
                .start())
        
        return query
    except Exception as e:
        print(f"Error processing stream for topic {topic}: {e}")
        raise

def main():
    """Main function to start the Spark Streaming jobs with node tracking."""
    spark = create_spark_session()
    print(f"Spark version: {spark.version}")
    
    # Check if running in initialization mode - check for both --init-schema and --init-only for compatibility
    if len(sys.argv) > 1 and (sys.argv[1] == '--init-only' or sys.argv[1] == '--init-schema'):
        print("Running in schema initialization mode only...")
        success = setup_cassandra_schema(spark) and setup_minio(spark)
        print(f"Schema initialization {'completed successfully' if success else 'failed'}")
        spark.stop()
        sys.exit(0 if success else 1)
    
    # Ensure schemas exist
    setup_cassandra_schema(spark)
    setup_minio(spark)
    
    # Process each topic
    queries = []
    metric_configs = [
        ("node-metrics", "node_metrics"),
        ("node-resource-usage", "node_resource_usage"),
        ("node-health-status", "node_health_status")
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
        for query in queries:
            if query and query.isActive:
                query.stop()
        raise

if __name__ == "__main__":
    main()