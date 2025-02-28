from pyspark.sql import SparkSession
from pyspark.sql.functions import col, to_timestamp, window

def main():
    # Initialize Spark session
    spark = SparkSession.builder \
        .appName("Example Spark Job") \
        .config("spark.jars.packages", "org.apache.spark:spark-sql-kafka-0-10_2.12:3.3.0") \
        .getOrCreate()
    
    # Log the Spark version
    print(f"Spark version: {spark.version}")
    
    try:
        # Create a sample dataframe
        data = [("Alice", 34), ("Bob", 45), ("Charlie", 29), ("Diana", 37)]
        columns = ["name", "age"]
        df = spark.createDataFrame(data, columns)
        
        # Perform some transformations
        result_df = df.filter(col("age") > 30).orderBy("age", ascending=False)
        
        # Show the results
        print("Results of the Spark job:")
        result_df.show()
        
        # Write results somewhere (e.g., to a CSV file)
        result_df.write.mode("overwrite").csv("/tmp/spark_job_output")
        
    finally:
        # Stop the Spark session
        spark.stop()
        
if __name__ == "__main__":
    main()
