#!/bin/bash
set -e

# Print debug info
echo "Current user: $(whoami)"
echo "Current PATH: $PATH"
echo "Airflow home: $AIRFLOW_HOME"

# Make sure airflow is in PATH
export PATH="/home/airflow/.local/bin:$PATH"

# Debug check: where is airflow installed?
which airflow || echo "Airflow command not found in PATH"
python -m pip list | grep airflow || echo "Airflow not found in pip list"

# Initialize the database if needed
if [[ "$1" == "webserver" ]]; then
  echo "Initializing Airflow database..."
  airflow db init
  
  echo "Upgrading Airflow database..."
  airflow db upgrade
  
  echo "Creating Airflow admin user..."
  airflow users create \
    -r Admin \
    -u airflow \
    -p airflow \
    -f admin \
    -l user \
    -e admin@example.com \
    --if-not-exists
  
  echo "Starting Airflow webserver..."
  exec airflow webserver
elif [[ "$1" == "scheduler" ]]; then
  echo "Starting Airflow scheduler..."
  exec airflow scheduler
else
  echo "Running custom command: $@"
  exec "$@"
fi
