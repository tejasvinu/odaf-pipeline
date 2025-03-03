from pyspark.sql import SparkSession
from pyspark.sql.functions import from_json, col
from pyspark.sql.types import StructType, StructField, StringType, DoubleType

def create_spark_session():
    """Create and return a Spark Session configured for streaming."""
    return (SparkSession.builder
            .appName("Simplified Metrics Processor")
            .config("spark.jars.packages", 
                   "org.apache.spark:spark-sql-kafka-0-10_2.12:3.3.0,"
                   "com.datastax.spark:spark-cassandra-connector_2.12:3.3.0")
            .config("spark.cassandra.connection.host", "cassandra")
            .getOrCreate())

def setup_cassandra_keyspace(spark):
    """Create keyspace and tables in Cassandra if they don't exist."""
    spark.sql("""
        CREATE DATABASE IF NOT EXISTS metrics
        COMMENT 'Metrics Database'
        LOCATION 'cassandra://cassandra:9042'
    """)
    
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

def process_metrics_stream(spark, topic, table_name):
    """Process metrics from a Kafka topic and write to Cassandra."""
    # Define schema for the simplified metrics
    metric_schema = StructType([
        StructField("name", StringType(), True),
        StructField("value", DoubleType(), True),
        StructField("timestamp", StringType(), True)
    ])
    
    # Read from Kafka
    stream_df = (spark
                .readStream
                .format("kafka")
                .option("kafka.bootstrap.servers", "kafka:29092")
                .option("subscribe", topic)
                .option("startingOffsets", "earliest")
                .load())
    
    # Parse JSON and select fields
    parsed_df = (stream_df
                .selectExpr("CAST(value AS STRING) as json")
                .select(from_json("json", metric_schema).alias("data"))
                .select("data.*"))
    
    # Write to Cassandra
    query = (parsed_df.writeStream
            .format("org.apache.spark.sql.cassandra")
            .option("checkpointLocation", f"/tmp/checkpoints/{topic}")
            .option("keyspace", "metrics")
            .option("table", table_name)
            .start())
    
    return query

def main():
    """Main function to start the Spark Streaming jobs."""
    spark = create_spark_session()
    print(f"Spark version: {spark.version}")
    
    # Set up Cassandra schema
    setup_cassandra_keyspace(spark)
    
    # Process each metric type
    queries = []
    metric_configs = [
        ("ipmi-metrics", "ipmi_metrics"),
        ("node-metrics", "node_metrics"),
        ("gpu-metrics", "gpu_metrics"),
        ("slurm-metrics", "slurm_metrics")
    ]
    
    for topic, table in metric_configs:
        print(f"Setting up stream for {topic} -> {table}")
        query = process_metrics_stream(spark, topic, table)
        queries.append(query)
    
    print("All streaming queries started. Waiting for termination...")
    for query in queries:
        query.awaitTermination()

if __name__ == "__main__":
    main()