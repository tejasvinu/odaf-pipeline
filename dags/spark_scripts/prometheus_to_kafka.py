import json
import time
import os
from datetime import datetime
import requests
from kafka import KafkaProducer
from kafka.errors import KafkaError
from requests.adapters import HTTPAdapter
from requests.packages.urllib3.util.retry import Retry

# Configuration
PROMETHEUS_URL = os.environ.get('PROMETHEUS_URL', 'http://prometheus:9090')
KAFKA_BOOTSTRAP_SERVERS = os.environ.get('KAFKA_BOOTSTRAP_SERVERS', 'kafka:29092')
SCRAPE_INTERVAL = int(os.environ.get('SCRAPE_INTERVAL', '60'))  # seconds
MAX_RETRIES = int(os.environ.get('MAX_RETRIES', '3'))

# Configure Prometheus HTTP client with retries
session = requests.Session()
retry_strategy = Retry(
    total=MAX_RETRIES,
    backoff_factor=1,
    status_forcelist=[429, 500, 502, 503, 504],
)
session.mount("http://", HTTPAdapter(max_retries=retry_strategy))
session.mount("https://", HTTPAdapter(max_retries=retry_strategy))

# Mapping of exporters to their topics and queries
EXPORTERS = [
    {
        'name': 'ipmi',
        'query': 'ipmi_*',
        'topic': 'ipmi-metrics'
    },
    {
        'name': 'node',
        'query': 'node_*',
        'topic': 'node-metrics'
    },
    {
        'name': 'dcgm',
        'query': 'DCGM_*',
        'topic': 'gpu-metrics'
    },
    {
        'name': 'slurm',
        'query': 'slurm_*',
        'topic': 'slurm-metrics'
    }
]

def create_kafka_producer():
    """Create and return a Kafka producer instance with retries."""
    return KafkaProducer(
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
        value_serializer=lambda v: json.dumps(v).encode('utf-8'),
        retries=MAX_RETRIES,
        retry_backoff_ms=1000,
        acks='all'
    )

def fetch_metrics_from_prometheus(query):
    """Fetch metrics from Prometheus using the provided PromQL query with retries."""
    try:
        response = session.get(
            f"{PROMETHEUS_URL}/api/v1/query",
            params={'query': query},
            timeout=30
        )
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"Error fetching metrics: {e}")
        return None

def simplify_metric(metric_data):
    """Convert Prometheus metric to simplified format with just name and value."""
    try:
        metric_name = next((v for k, v in metric_data['metric'].items() if k == '__name__'), None)
        if not metric_name:
            # If no __name__ found, create name from labels
            labels = [f"{k}={v}" for k, v in metric_data['metric'].items() if k != '__name__']
            metric_name = '_'.join(labels)
        
        return {
            'name': metric_name,
            'value': float(metric_data['value'][1]) if len(metric_data['value']) > 1 else None,
            'timestamp': datetime.utcnow().isoformat()
        }
    except (KeyError, IndexError, ValueError) as e:
        print(f"Error simplifying metric: {e}")
        return None

def send_to_kafka(producer, topic, data):
    """Send data to Kafka with error handling."""
    try:
        future = producer.send(topic, data)
        future.get(timeout=10)  # Wait for the send to complete
        return True
    except KafkaError as e:
        print(f"Error sending to Kafka topic {topic}: {e}")
        return False

def main():
    """Main function to periodically fetch metrics and send to Kafka."""
    print(f"Starting Prometheus to Kafka connector")
    print(f"Prometheus URL: {PROMETHEUS_URL}")
    print(f"Kafka Bootstrap Servers: {KAFKA_BOOTSTRAP_SERVERS}")
    
    producer = create_kafka_producer()
    
    while True:
        for exporter in EXPORTERS:
            exporter_name = exporter['name']
            query = exporter['query']
            topic = exporter['topic']
            
            print(f"Fetching {exporter_name} metrics with query: {query}")
            result = fetch_metrics_from_prometheus(query)
            
            if result and result.get('status') == 'success' and result.get('data', {}).get('result'):
                metrics_data = result['data']['result']
                success_count = 0
                
                for metric in metrics_data:
                    simple_metric = simplify_metric(metric)
                    if simple_metric:
                        if send_to_kafka(producer, topic, simple_metric):
                            success_count += 1
                
                producer.flush()
                print(f"Successfully published {success_count}/{len(metrics_data)} {exporter_name} metrics to topic '{topic}'")
            else:
                print(f"No metrics found for {exporter_name} or query failed")
        
        print(f"Sleeping for {SCRAPE_INTERVAL} seconds...")
        time.sleep(SCRAPE_INTERVAL)

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Fatal error in main loop: {e}")
        raise