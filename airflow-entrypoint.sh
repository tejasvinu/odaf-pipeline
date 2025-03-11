#!/bin/bash

# Don't exit on errors so the container doesn't crash
set +e

# Print debug info
echo "Current user: $(whoami)"
echo "Current PATH: $PATH"
echo "Python path: $(which python)"
echo "Airflow home: $AIRFLOW_HOME"

# Make sure the correct Python packages are in the PATH
export PYTHONPATH="${PYTHONPATH:+${PYTHONPATH}:}/opt/airflow:/home/airflow/.local/lib/python3.7/site-packages"
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

# First upgrade pip to avoid version issues
echo "Upgrading pip..."
python -m pip install --upgrade pip

# Debug check: where is airflow installed?
which airflow || echo "Airflow command not found in PATH"
python -m pip list | grep airflow || echo "Airflow not found in pip list"

# Print Python path for debugging
echo "Current Python sys.path:"
python -c "import sys; print(sys.path)"

# Check if airflow module is properly installed
echo "Testing airflow module import..."
if ! python -c "import airflow; print(f'Airflow {airflow.__version__} found')" 2>/dev/null; then
  echo "Airflow module cannot be imported, will reinstall"
  AIRFLOW_NEEDS_INSTALL=true
else
  echo "Airflow module can be imported"
  AIRFLOW_NEEDS_INSTALL=false
fi

# If airflow command not found or module import failed, try to reinstall
if ! which airflow > /dev/null 2>&1 || [ "$AIRFLOW_NEEDS_INSTALL" = true ]; then
  echo "Airflow installation issues detected, performing full reinstallation..."
  
  # Clean previous installation artifacts
  echo "Cleaning previous installation..."
  pip uninstall -y apache-airflow || echo "No existing airflow package to remove"
  
  # Ensure we have the right dependencies
  echo "Installing airflow with pip..."
  pip install --no-cache-dir "apache-airflow==2.5.0" \
    --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-2.5.0/constraints-3.7.txt"
  
  # Verify installation was successful
  echo "PATH after installation: $PATH"
  which airflow || echo "ERROR: Airflow still not found in PATH after installation"
  
  # Verify module can be imported
  if ! python -c "import airflow; print(f'Airflow {airflow.__version__} installed successfully')" 2>/dev/null; then
    echo "ERROR: Airflow module still cannot be imported after reinstallation"
    echo "Python sys.path:"
    python -c "import sys; print(sys.path)"
    echo "Will attempt to install without constraints..."
    pip install --no-cache-dir "apache-airflow==2.5.0" --user
    if ! python -c "import airflow; print(f'Airflow {airflow.__version__} installed successfully')" 2>/dev/null; then
      echo "ERROR: Airflow installation failed. Continuing anyway, but expect problems..."
    else
      echo "Airflow reinstallation successful!"
    fi
  else
    echo "Airflow reinstallation successful!"
  fi
fi

# Create necessary folders with proper permissions
mkdir -p "${AIRFLOW_HOME}/logs" "${AIRFLOW_HOME}/dags" "${AIRFLOW_HOME}/plugins" "${AIRFLOW_HOME}/config"
chmod -R 777 "${AIRFLOW_HOME}/logs" "${AIRFLOW_HOME}/dags" "${AIRFLOW_HOME}/plugins" "${AIRFLOW_HOME}/config"
chown -R airflow:root "${AIRFLOW_HOME}" || echo "Warning: Could not change ownership of AIRFLOW_HOME"

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
