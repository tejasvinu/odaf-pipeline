import json
import time
import os
from datetime import datetime
import requests
from kafka import KafkaProducer

# Configuration
PROMETHEUS_URL = os.environ.get('PROMETHEUS_URL', 'http://prometheus:9090')
KAFKA_BOOTSTRAP_SERVERS = os.environ.get('KAFKA_BOOTSTRAP_SERVERS', 'kafka:29092')
SCRAPE_INTERVAL = int(os.environ.get('SCRAPE_INTERVAL', '60'))  # seconds

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
    """Create and return a Kafka producer instance."""
    return KafkaProducer(
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
        value_serializer=lambda v: json.dumps(v).encode('utf-8')
    )

def fetch_metrics_from_prometheus(query):
    """Fetch metrics from Prometheus using the provided PromQL query."""
    try:
        response = requests.get(
            f"{PROMETHEUS_URL}/api/v1/query",
            params={'query': query}
        )
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"Error fetching metrics: {e}")
        return None

def simplify_metric(metric_data):
    """Convert Prometheus metric to simplified format with just name and value."""
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
                print(f"Got {len(metrics_data)} metrics for {exporter_name}")
                
                # Convert to simplified format and publish to Kafka
                for metric in metrics_data:
                    simple_metric = simplify_metric(metric)
                    producer.send(topic, simple_metric)
                
                producer.flush()
                print(f"Published {len(metrics_data)} {exporter_name} metrics to Kafka topic '{topic}'")
            else:
                print(f"No metrics found for {exporter_name} or query failed")
                
        print(f"Sleeping for {SCRAPE_INTERVAL} seconds...")
        time.sleep(SCRAPE_INTERVAL)

if __name__ == "__main__":
    main()