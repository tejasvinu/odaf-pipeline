from airflow.plugins_manager import AirflowPlugin
from airflow.hooks.base import BaseHook
from airflow.models import Connection

class SparkHook(BaseHook):
    """
    Hook for interacting with Apache Spark
    """
    conn_name_attr = 'spark_conn_id'
    default_conn_name = 'spark_default'
    conn_type = 'spark'
    hook_name = 'Spark'
    
    def __init__(self, spark_conn_id='spark_default'):
        super().__init__()
        self.spark_conn_id = spark_conn_id
        self.connection = self.get_connection(spark_conn_id)
        self.host = self.connection.host
        self.port = self.connection.port
        self.schema = self.connection.schema
        
    def get_spark_master_url(self):
        """Returns the Spark master URL"""
        if not self.host:
            return "spark://spark-master:7077"  # Default value
        elif not self.port:
            return f"spark://{self.host}:7077"  # Default port
        else:
            return f"spark://{self.host}:{self.port}"
        
    @staticmethod
    def get_ui_field_behaviour():
        """Returns custom UI field behavior for the connection form"""
        return {
            "hidden_fields": ["login", "password", "extra"],
            "relabeling": {
                "host": "Spark Master Host",
                "port": "Spark Master Port",
                "schema": "Spark Application Name"
            },
        }

class SparkAirflowPlugin(AirflowPlugin):
    name = "spark_plugin"
    hooks = [SparkHook]
    executors = []
    macros = []
    admin_views = []
    flask_blueprints = []
    menu_links = []
    appbuilder_views = []
    appbuilder_menu_items = []
