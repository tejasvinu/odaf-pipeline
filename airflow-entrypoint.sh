#!/bin/bash

# Don't exit on errors so the container doesn't crash
set +e

# Print debug info
echo "Current user: $(whoami)"
echo "Current PATH: $PATH"
echo "Python path: $(which python)"
echo "Airflow home: $AIRFLOW_HOME"

# Make sure the correct Python packages are in the PATH
export PYTHONPATH="${PYTHONPATH:+${PYTHONPATH}:}/opt/airflow"
export PATH="/home/airflow/.local/bin:$PATH"

# Check verify_environment script
echo "Checking verify_environment.sh script:"
if [ -f /opt/airflow/verify_environment.sh ]; then
  ls -la /opt/airflow/verify_environment.sh || echo "Cannot list verify_environment.sh"
  # Note: We're not trying to chmod here since it often fails with mounted volumes
  # Instead, we'll always use bash to execute it
  echo "Note: To run verification script, use 'bash /opt/airflow/verify_environment.sh'"
else
  echo "verify_environment.sh not found!"
fi

# Debug check: where is airflow installed?
which airflow || echo "Airflow command not found in PATH"
python -m pip list | grep airflow || echo "Airflow not found in pip list"

# If airflow command not found, try to reinstall
if ! which airflow > /dev/null 2>&1; then
  echo "Airflow not found, attempting reinstallation..."
  pip install --no-cache-dir "apache-airflow==2.5.0" --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-2.5.0/constraints-3.7.txt"
  echo "PATH after installation: $PATH"
  which airflow || echo "Airflow still not found in PATH after installation"
fi

# Initialize the database if needed
if [[ "$1" == "webserver" ]]; then
  echo "Initializing Airflow database..."
  airflow db init || echo "Failed to initialize database, but continuing..."
  
  echo "Upgrading Airflow database..."
  airflow db upgrade || echo "Failed to upgrade database, but continuing..."
  
  echo "Creating Airflow admin user..."
  # Try to create user but don't fail if it exists
  airflow users create \
    -r Admin \
    -u airflow \
    -p airflow \
    -f admin \
    -l user \
    -e admin@example.com 2>/dev/null || echo "User may already exist, continuing..."
  
  echo "Starting Airflow webserver..."
  exec airflow webserver
elif [[ "$1" == "scheduler" ]]; then
  echo "Starting Airflow scheduler..."
  exec airflow scheduler
else
  echo "Running custom command: $@"
  exec "$@"
fi
