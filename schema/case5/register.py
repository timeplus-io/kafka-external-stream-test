import os
import requests
import json
import sys

# Read from environment variables
SCHEMA_REGISTRY_URL = os.getenv("SCHEMA_REGISTRY_URL")
USERNAME = os.getenv("SCHEMA_REGISTRY_USERNAME")
PASSWORD = os.getenv("SCHEMA_REGISTRY_PASSWORD")

SUBJECT = "sensor-update-value"

# Validate env vars
if not all([SCHEMA_REGISTRY_URL, USERNAME, PASSWORD]):
    print("Missing required environment variables:")
    print("  SCHEMA_REGISTRY_URL")
    print("  SCHEMA_REGISTRY_USERNAME")
    print("  SCHEMA_REGISTRY_PASSWORD")
    sys.exit(1)

# Protobuf schema (RAW string, not JSON)
proto_schema = """
syntax = "proto3";

message SensorUpdate {
    string id = 1;
    float value = 2;
    repeated int32 tags = 3;
}
"""

payload = {
    "schema": proto_schema,
    "schemaType": "PROTOBUF"
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
    print("✅ Protobuf schema registered successfully!")
    print("Schema ID:", response.json()["id"])
else:
    print("❌ Failed to register schema")
    print("Status:", response.status_code)
    print("Response:", response.text)