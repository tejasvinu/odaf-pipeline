#!/bin/sh
# Master script to fix all Spark-related issues in the Airflow container

echo "===== Starting comprehensive fix for Spark issues ====="

# Make all scripts executable
chmod +x /opt/airflow/fix_bash_issue.sh /opt/airflow/fix_airflow_connections.sh

# Fix the bash issue first
echo "Step 1: Fixing bash and environment issues..."
/opt/airflow/fix_bash_issue.sh

# Create proper Airflow connections
echo "Step 2: Setting up Airflow connections..."
/opt/airflow/fix_airflow_connections.sh

# Verify environment is ready
echo "Step 3: Verifying environment..."
/opt/airflow/verify_environment.sh

# Restart Airflow services to apply all changes
echo "Step 4: Restarting Airflow services..."
if command -v supervisorctl >/dev/null 2>&1; then
  supervisorctl restart all
else
  echo "Note: supervisorctl not available, services must be restarted manually"
  
  # Alternatively try to restart services directly
  if pgrep -f "airflow webserver" >/dev/null; then
    pkill -f "airflow webserver" && airflow webserver -D
    echo "Airflow webserver restarted"
  fi
  
  if pgrep -f "airflow scheduler" >/dev/null; then
    pkill -f "airflow scheduler" && airflow scheduler -D
    echo "Airflow scheduler restarted"
  fi
fi

echo ""
echo "===== Fix complete ====="
echo ""
echo "To apply these fixes in your container:"
echo "1. Copy these scripts to your Airflow container:"
echo "   docker cp fix_bash_issue.sh <container_id>:/opt/airflow/"
echo "   docker cp fix_airflow_connections.sh <container_id>:/opt/airflow/"
echo "   docker cp fix_spark_issues.sh <container_id>:/opt/airflow/"
echo ""
echo "2. Execute the master fix script in the container:"
echo "   docker exec -it <container_id> sh /opt/airflow/fix_spark_issues.sh"
echo ""
echo "3. If issues persist, you may need to recreate your container with bash pre-installed"
echo "   by adding bash installation to your Dockerfile.airflow"
echo ""