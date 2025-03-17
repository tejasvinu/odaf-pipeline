#!/usr/bin/env python3
import sys
import os
from cassandra.cluster import Cluster
from cassandra.auth import PlainTextAuthProvider
import time
import boto3
from botocore.client import Config

def main():
    """Initialize Cassandra schema and MinIO bucket directly without Spark dependencies."""
    print("Starting Cassandra schema and MinIO bucket initialization...")
    
    # Set up connection parameters
    cassandra_host = os.environ.get('CASSANDRA_HOST', 'cassandra')
    cassandra_port = int(os.environ.get('CASSANDRA_PORT', '9042'))
    minio_endpoint = os.environ.get('MINIO_ENDPOINT', 'http://minio:9000')
    minio_access_key = os.environ.get('MINIO_ACCESS_KEY', 'minioadmin')
    minio_secret_key = os.environ.get('MINIO_SECRET_KEY', 'minioadmin')
    minio_bucket = os.environ.get('MINIO_BUCKET', 'metrics')
    
    success = setup_cassandra_schema(cassandra_host, cassandra_port) and setup_minio(
        minio_endpoint, minio_access_key, minio_secret_key, minio_bucket
    )
    
    print(f"Schema initialization {'completed successfully' if success else 'failed'}")
    sys.exit(0 if success else 1)

def setup_cassandra_schema(host, port):
    """Create keyspace and tables in Cassandra."""
    try:
        print(f"Connecting to Cassandra at {host}:{port}...")
        # Retry connection a few times
        max_retries = 5
        retry_delay = 5  # seconds
        cluster = None
        
        for attempt in range(1, max_retries + 1):
            try:
                cluster = Cluster([host], port=port, connect_timeout=30)
                session = cluster.connect()
                print(f"Connected to Cassandra cluster: {cluster.metadata.cluster_name}")
                break
            except Exception as e:
                print(f"Connection attempt {attempt}/{max_retries} failed: {str(e)}")
                if attempt < max_retries:
                    print(f"Retrying in {retry_delay} seconds...")
                    time.sleep(retry_delay)
                else:
                    print("Max retries reached. Could not connect to Cassandra.")
                    return False
        
        if not cluster:
            return False
            
        # Create keyspace
        print("Creating keyspace...")
        session.execute("""
            CREATE KEYSPACE IF NOT EXISTS metrics
            WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '1'}
        """)
        print("Keyspace creation successful")
        
        # Create tables
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
            session.execute(create_stmt)
            # Verify table exists
            rows = session.execute(f"SELECT COUNT(*) FROM metrics.{table_name} LIMIT 1")
            count = rows.one()[0]
            print(f"Table {table_name} created and verified with {count} rows")
            
        print("Successfully created all Cassandra schemas")
        cluster.shutdown()
        return True
    except Exception as e:
        print(f"Error creating Cassandra schema: {str(e)}")
        import traceback
        traceback.print_exc()
        return False

def setup_minio(endpoint, access_key, secret_key, bucket_name):
    """Create MinIO bucket if it doesn't exist."""
    try:
        print(f"Connecting to MinIO at {endpoint}...")
        s3_client = boto3.client('s3',
                              endpoint_url=endpoint,
                              aws_access_key_id=access_key,
                              aws_secret_access_key=secret_key,
                              verify=False,
                              config=Config(connect_timeout=30, retries={'max_attempts': 5}))
        
        try:
            s3_client.head_bucket(Bucket=bucket_name)
            print(f"Bucket {bucket_name} already exists")
        except:
            s3_client.create_bucket(Bucket=bucket_name)
            print(f"Created MinIO bucket: {bucket_name}")
        
        return True
    except Exception as e:
        print(f"Error setting up MinIO: {str(e)}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    main()