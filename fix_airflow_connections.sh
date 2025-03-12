#!/bin/sh
# Script to create necessary Airflow connections

echo "===== Fixing Airflow connections ====="

# Wait for Airflow webserver to be available
echo "Waiting for Airflow webserver..."
for i in $(seq 1 30); do
  if nc -z localhost 8080 >/dev/null 2>&1; then
    echo "Airflow webserver is up!"
    break
  fi
  echo "Waiting for Airflow webserver... ($i/30)"
  sleep 2
  if [ "$i" -eq 30 ]; then
    echo "Airflow webserver not available after 60 seconds, continuing anyway..."
  fi
done

# Create the spark_default connection
echo "Creating spark_default connection..."
airflow connections delete spark_default 2>/dev/null || true
airflow connections add 'spark_default' \
  --conn-type 'spark' \
  --conn-host 'local[*]' \
  --conn-extra '{"spark-home": "/home/airflow/.local/", "spark-binary": "/home/airflow/.local/bin/spark-submit"}'

# Verify connection was created
echo "Verifying connection was created..."
if airflow connections get spark_default >/dev/null 2>&1; then
  echo "✓ Connection 'spark_default' created successfully"
else
  echo "ERROR: Failed to create connection 'spark_default'"
  echo "Trying alternative connection creation method..."
  
  # Create connection using environment variable
  export AIRFLOW_CONN_SPARK_DEFAULT="spark://local[*]?spark-home=/home/airflow/.local/&spark-binary=/home/airflow/.local/bin/spark-submit"
  echo "Set AIRFLOW_CONN_SPARK_DEFAULT environment variable as fallback"
  
  # Add to container's environment files for persistence
  for profile in /root/.bashrc /root/.profile /etc/profile /home/airflow/.bashrc; do
    if [ -f "$profile" ]; then
      grep -q "AIRFLOW_CONN_SPARK_DEFAULT=" "$profile" || echo "export AIRFLOW_CONN_SPARK_DEFAULT=\"$AIRFLOW_CONN_SPARK_DEFAULT\"" >> "$profile"
      echo "✓ Updated $profile with connection environment variable"
    fi
  done
fi

# Reset the Airflow connection cache
echo "Resetting Airflow's connection cache..."
if pgrep -f "airflow scheduler" >/dev/null; then
  echo "Restarting Airflow scheduler to apply connection changes..."
  pkill -f "airflow scheduler" || echo "Failed to restart scheduler"
  sleep 2
  airflow scheduler -D
  echo "Airflow scheduler restarted"
fi

echo "===== Airflow connections fix complete ====="
exit 0