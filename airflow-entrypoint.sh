#!/bin/bash
set -e

# Print debug info
echo "Current user: $(whoami)"
echo "Current PATH: $PATH"
echo "Airflow home: $AIRFLOW_HOME"

# Check verify_environment script
echo "Checking verify_environment.sh script:"
ls -la /opt/airflow/verify_environment.sh || echo "verify_environment.sh not found!"
if [ -f /opt/airflow/verify_environment.sh ]; then
  # Make sure it's executable
  chmod +x /opt/airflow/verify_environment.sh
  echo "verify_environment.sh is executable"
fi

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
  # Remove --if-not-exists flag which is not supported in this version
  airflow users create \
    -r Admin \
    -u airflow \
    -p airflow \
    -f admin \
    -l user \
    -e admin@example.com || true  # Added || true to continue even if user exists
  
  echo "Starting Airflow webserver..."
  exec airflow webserver
elif [[ "$1" == "scheduler" ]]; then
  echo "Starting Airflow scheduler..."
  exec airflow scheduler
else
  echo "Running custom command: $@"
  exec "$@"
fi
