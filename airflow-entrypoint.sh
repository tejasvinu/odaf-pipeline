#!/bin/bash
set +e  # Don't exit on errors

# Print debug info
echo "Current user: $(whoami)"
echo "Current PATH: $PATH"
echo "Python path: $(which python)"
echo "Airflow home: $AIRFLOW_HOME"

# Make sure the correct Python packages are in the PATH
export PYTHONPATH="${PYTHONPATH:+${PYTHONPATH}:}/opt/airflow:/home/airflow/.local/lib/python3.7/site-packages"
export PATH="/home/airflow/.local/bin:$PATH"

# Create necessary folders with proper permissions (if mounted volumes)
mkdir -p "${AIRFLOW_HOME}/logs" "${AIRFLOW_HOME}/dags" "${AIRFLOW_HOME}/plugins" "${AIRFLOW_HOME}/config"
chmod -R 777 "${AIRFLOW_HOME}/logs" "${AIRFLOW_HOME}/dags" "${AIRFLOW_HOME}/plugins" "${AIRFLOW_HOME}/config" || true
chown -R airflow:root "${AIRFLOW_HOME}" || true

# Handle different startup commands
if [[ "$1" == "webserver" ]]; then
  # The database should already be initialized during build, but check and upgrade if needed
  if ! airflow db check >/dev/null 2>&1; then
    echo "Database check failed, attempting to initialize..."
    airflow db init
  fi
  
  echo "Upgrading Airflow database if needed..."
  airflow db upgrade || echo "Warning: Database upgrade failed, but continuing..."
  
  # Create admin user only if it doesn't exist
  if ! airflow users list | grep -q "airflow"; then
    echo "Creating default admin user..."
    airflow users create \
      -r Admin \
      -u airflow \
      -p airflow \
      -f admin \
      -l user \
      -e admin@example.com || echo "Warning: User creation failed, but continuing..."
  fi
  
  echo "Starting Airflow webserver..."
  exec airflow webserver
  
elif [[ "$1" == "scheduler" ]]; then
  # The scheduler also needs the database to be ready
  if ! airflow db check >/dev/null 2>&1; then
    echo "Database check failed for scheduler, waiting for webserver to initialize it..."
    sleep 10
  fi
  
  echo "Starting Airflow scheduler..."
  exec airflow scheduler
  
else
  echo "Running custom command: $@"
  exec "$@"
fi
