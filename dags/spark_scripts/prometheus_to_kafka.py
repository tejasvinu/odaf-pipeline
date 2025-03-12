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

# Define metrics mapping with node identification
METRIC_GROUPS = [
    {
        'name': 'node',
        'query': '{__name__=~"node_.*", instance=~".+"}',  # Explicitly request instance label
        'topic': 'node-metrics',
        'required_labels': ['instance', 'job']
    },
    {
        'name': 'resource',
        'query': '{__name__=~"node_(cpu|memory|disk|filesystem|network).*", instance=~".+"}',
        'topic': 'node-resource-usage',
        'required_labels': ['instance', 'job']
    },
    {
        'name': 'health',
        'query': '{__name__=~"up|node_(uname_info|time|load1|memory_MemAvailable_bytes)", instance=~".+"}',
        'topic': 'node-health-status',
        'required_labels': ['instance', 'job']
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

def extract_node_info(metric_data):
    """Extract node identification information from metric labels."""
    labels = metric_data.get('metric', {})
    node_info = {
        'instance': labels.get('instance', 'unknown'),
        'job': labels.get('job', 'unknown'),
        'node_name': labels.get('nodename', labels.get('instance', 'unknown').split(':')[0])
    }
    
    # Add additional node metadata if available
    if 'node_uname_info' in str(labels.get('__name__', '')):
        node_info.update({
            'machine': labels.get('machine', ''),
            'os': labels.get('operating_system', ''),
            'system': labels.get('system', '')
        })
    
    return node_info

def format_metric(metric_data, group_name):
    """Format metric with node identification and metadata."""
    try:
        metric_name = metric_data['metric'].get('__name__', 'unnamed_metric')
        node_info = extract_node_info(metric_data)
        timestamp = datetime.utcnow().isoformat()
        
        return {
            'name': metric_name,
            'value': float(metric_data['value'][1]) if len(metric_data['value']) > 1 else None,
            'timestamp': timestamp,
            'node': node_info,
            'group': group_name,
            'labels': {k: v for k, v in metric_data['metric'].items() 
                      if k not in ['__name__', 'instance', 'job']}  # Additional labels
        }
    except (KeyError, IndexError, ValueError) as e:
        print(f"Error formatting metric: {e}")
        return None

def send_to_kafka(producer, topic, data):
    """Send data to Kafka with error handling."""
    try:
        future = producer.send(topic, data)
        future.get(timeout=10)  # Wait for send to complete
        return True
    except KafkaError as e:
        print(f"Error sending to Kafka topic {topic}: {e}")
        return False

def main():
    """Main function to collect and forward metrics with node identification."""
    print(f"Starting Prometheus to Kafka connector with node tracking")
    print(f"Prometheus URL: {PROMETHEUS_URL}")
    print(f"Kafka Bootstrap Servers: {KAFKA_BOOTSTRAP_SERVERS}")
    
    producer = create_kafka_producer()
    
    while True:
        for group in METRIC_GROUPS:
            print(f"Fetching {group['name']} metrics...")
            result = fetch_metrics_from_prometheus(group['query'])
            
            if result and result.get('status') == 'success':
                metrics = result.get('data', {}).get('result', [])
                success_count = 0
                
                for metric in metrics:
                    # Verify required labels are present
                    labels = metric.get('metric', {})
                    if all(label in labels for label in group['required_labels']):
                        formatted_metric = format_metric(metric, group['name'])
                        if formatted_metric:
                            if send_to_kafka(producer, group['topic'], formatted_metric):
                                success_count += 1
                    else:
                        print(f"Skipping metric missing required labels: {labels}")
                
                producer.flush()
                print(f"Published {success_count}/{len(metrics)} {group['name']} metrics to {group['topic']}")
            else:
                print(f"No metrics found for {group['name']} or query failed")
        
        print(f"Sleeping for {SCRAPE_INTERVAL} seconds...")
        time.sleep(SCRAPE_INTERVAL)

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Fatal error in main loop: {e}")
        raise