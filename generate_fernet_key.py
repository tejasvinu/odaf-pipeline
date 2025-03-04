#!/usr/bin/env python3
"""
Generate a Fernet key for Airflow.
This can be used to generate a key for the AIRFLOW__CORE__FERNET_KEY environment variable.
"""

from cryptography.fernet import Fernet

def generate_fernet_key():
    # Generate a random Fernet key
    key = Fernet.generate_key().decode()
    print(f"Generated Fernet key: {key}")
    print("\nAdd this to your docker-compose.yml file as:")
    print(f'AIRFLOW__CORE__FERNET_KEY={key}')
    
    return key

if __name__ == "__main__":
    generate_fernet_key()
