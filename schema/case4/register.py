import os
import requests
import json
import sys

# Read from environment variables
SCHEMA_REGISTRY_URL = os.getenv("SCHEMA_REGISTRY_URL")
USERNAME = os.getenv("SCHEMA_REGISTRY_USERNAME")
PASSWORD = os.getenv("SCHEMA_REGISTRY_PASSWORD")

SUBJECT = "case4.avro_verification-value"

# Validate env vars
if not all([SCHEMA_REGISTRY_URL, USERNAME, PASSWORD]):
    print("Missing required environment variables:")
    print("  SCHEMA_REGISTRY_URL")
    print("  SCHEMA_REGISTRY_USERNAME")
    print("  SCHEMA_REGISTRY_PASSWORD")
    sys.exit(1)

# Avro schema
schema = {
    "type": "record",
    "name": "avro_verification",
    "namespace": "case4",
    "fields": [
        {"name": "customer_id", "type": "string"},
        {"name": "transaction_amount", "type": "double"},
        {"name": "promotion_code", "type": ["null", "string"], "default": None}
    ]
}

payload = {
    "schema": json.dumps(schema)
}

url = f"{SCHEMA_REGISTRY_URL}/subjects/{SUBJECT}/versions"

response = requests.post(
    url,
    auth=(USERNAME, PASSWORD),
    headers={"Content-Type": "application/vnd.schemaregistry.v1+json"},
    json=payload,
    timeout=10
)

if response.status_code == 200:
    print("✅ Schema registered successfully!")
    print("Schema ID:", response.json()["id"])
else:
    print("❌ Failed to register schema")
    print("Status:", response.status_code)
    print("Response:", response.text)