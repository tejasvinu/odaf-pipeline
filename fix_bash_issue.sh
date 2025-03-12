#!/bin/sh
# Script to fix common environment issues related to bash and Spark
# This simplified version is designed to work with the integrated Docker setup

echo "===== Running environment checks ====="

# Check if bash is available
if ! command -v bash > /dev/null; then
  echo "CRITICAL: bash is not available in this container!"
  echo "Attempting to install bash..."
  if command -v apt-get > /dev/null; then
    apt-get update && apt-get install -y bash
  elif command -v apk > /dev/null; then
    apk add --no-cache bash
  elif command -v yum > /dev/null; then
    yum install -y bash
  else
    echo "ERROR: Could not install bash, package manager not found"
    exit 1
  fi
else
  echo "✓ bash is installed at $(which bash)"
fi

# Verify spark-submit wrapper is in place
if [ ! -f "/usr/local/bin/spark-submit-wrapper" ]; then
  echo "Creating spark-submit wrapper..."
  SPARK_SUBMIT=$(which spark-submit 2>/dev/null || echo "not-found")
  if [ "$SPARK_SUBMIT" != "not-found" ]; then
    mkdir -p /usr/local/bin
    cat > "/usr/local/bin/spark-submit-wrapper" << EOF
#!/bin/sh
# Wrapper script for spark-submit to ensure proper shell usage
exec $SPARK_SUBMIT "\$@"
EOF
    chmod +x "/usr/local/bin/spark-submit-wrapper"
    ln -sf /usr/local/bin/spark-submit-wrapper /usr/local/bin/spark-submit
    echo "✓ Created spark-submit wrapper"
  else
    echo "WARNING: spark-submit not found in PATH"
  fi
fi

# Set environment variables if not already set
if [ -z "$JAVA_HOME" ]; then
  export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
  echo "Set JAVA_HOME=$JAVA_HOME"
fi

# Check that Java is in PATH
if ! command -v java > /dev/null; then
  export PATH=$JAVA_HOME/bin:/bin:/usr/bin:/usr/local/bin:$PATH
  echo "Added Java to PATH"
fi

echo "Environment variables:"
echo "JAVA_HOME=$JAVA_HOME"
echo "PATH=$PATH"

echo "===== Environment checks completed ====="
exit 0