#!/bin/bash

# Script to fix spark-submit path issues
set -e

echo "Checking spark-submit binary availability..."

# Check where the real spark-submit binary is located
SPARK_BINARY=$(find /home/airflow/.local -name "spark-submit" 2>/dev/null | head -1)

if [ -z "$SPARK_BINARY" ]; then
    echo "spark-submit binary not found in /home/airflow/.local - searching elsewhere..."
    SPARK_BINARY=$(find / -name "spark-submit" 2>/dev/null | grep -v "/usr/local/bin/spark" | head -1)
fi

if [ -z "$SPARK_BINARY" ]; then
    echo "No spark-submit binary found. Creating a link to the pyspark launcher..."
    
    # Find pyspark installation directory
    PYSPARK_DIR=$(python -c "import pyspark; print(pyspark.__path__[0])" 2>/dev/null)
    
    if [ ! -z "$PYSPARK_DIR" ]; then
        echo "Found PySpark at: $PYSPARK_DIR"
        
        # Create bin directory if it doesn't exist
        mkdir -p /home/airflow/.local/bin
        
        # Check if bin/spark-submit exists in the PySpark directory structure
        if [ -f "$PYSPARK_DIR/bin/spark-submit" ]; then
            echo "Found spark-submit in PySpark installation"
            ln -sf "$PYSPARK_DIR/bin/spark-submit" /home/airflow/.local/bin/spark-submit
            SPARK_BINARY=/home/airflow/.local/bin/spark-submit
        else
            # Create a simple wrapper that uses pyspark's launcher
            echo "#!/bin/bash" > /home/airflow/.local/bin/spark-submit
            echo "# Wrapper script that uses pyspark launcher" >> /home/airflow/.local/bin/spark-submit
            echo "python -m pyspark.bin.spark-submit \"\$@\"" >> /home/airflow/.local/bin/spark-submit
            chmod +x /home/airflow/.local/bin/spark-submit
            SPARK_BINARY=/home/airflow/.local/bin/spark-submit
        fi
    else
        echo "PySpark not found. Cannot create spark-submit wrapper."
        exit 1
    fi
fi

echo "Found spark-submit at: $SPARK_BINARY"

# Fix the /usr/local/bin/spark-submit wrapper script to point to the correct binary
echo "#!/bin/bash" > /usr/local/bin/spark-submit
echo "# Wrapper script for spark-submit" >> /usr/local/bin/spark-submit
echo "exec $SPARK_BINARY \"\$@\"" >> /usr/local/bin/spark-submit
chmod +x /usr/local/bin/spark-submit

# Create the other allowed binary names
ln -sf /usr/local/bin/spark-submit /usr/local/bin/spark2-submit
ln -sf /usr/local/bin/spark-submit /usr/local/bin/spark3-submit

echo "Checking if spark-submit is properly in PATH..."
which spark-submit || echo "spark-submit not in PATH"

echo "Spark submit wrapper fixed and ready to use."

exit 0