CREATE DATABASE IF NOT EXISTS case5;

-- Step 1: Install Python dependencies
-- confluent-kafka==2.1.1 is the latest version that works with Timeplus's internal libkafka
SYSTEM INSTALL PYTHON PACKAGE 'confluent-kafka==2.1.1'; 
SYSTEM INSTALL PYTHON PACKAGE 'authlib';
SYSTEM INSTALL PYTHON PACKAGE 'cachetools';
SYSTEM INSTALL PYTHON PACKAGE 'googleapis-common-protos';
-- need restart timeplus after dependencies installation

-- Step 2: Create the external stream
CREATE EXTERNAL STREAM case5.sensor_update_datagen(id string, value float64, tags string, kafka_topic string, generated_at datetime64(3))
AS $$
import os
import time
import random
import json
from datetime import datetime

import sys
import pkg_resources
# Force refresh of the 'google' namespace
pkg_resources.declare_namespace('google')

import google.type  # Test if it works now

from confluent_kafka import SerializingProducer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.protobuf import ProtobufSerializer

from google.protobuf import descriptor_pb2, descriptor_pool, message_factory
from google.protobuf.message_factory import GetMessageClass

BOOTSTRAP_SERVERS = os.getenv("KAFKA_BOOTSTRAP_SERVERS")
KAFKA_USERNAME = os.getenv("KAFKA_USERNAME")
KAFKA_PASSWORD = os.getenv("KAFKA_PASSWORD")

SCHEMA_REGISTRY_URL = os.getenv("KAFKA_SCHEMA_REGISTRY_URL")
SR_USERNAME = os.getenv("KAFKA_SCHEMA_REGISTRY_USERNAME")
SR_PASSWORD = os.getenv("KAFKA_SCHEMA_REGISTRY_PASSWORD")

TOPIC = "sensor-update"

# ---- Define proto schema inline ----
file_desc_proto = descriptor_pb2.FileDescriptorProto()
file_desc_proto.name = "sensor.proto"
file_desc_proto.syntax = "proto3"

msg = file_desc_proto.message_type.add()
msg.name = "SensorUpdate"

field1 = msg.field.add()
field1.name = "id"
field1.number = 1
field1.label = descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL
field1.type = descriptor_pb2.FieldDescriptorProto.TYPE_STRING

field2 = msg.field.add()
field2.name = "value"
field2.number = 2
field2.label = descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL
field2.type = descriptor_pb2.FieldDescriptorProto.TYPE_FLOAT

field3 = msg.field.add()
field3.name = "tags"
field3.number = 3
field3.label = descriptor_pb2.FieldDescriptorProto.LABEL_REPEATED
field3.type = descriptor_pb2.FieldDescriptorProto.TYPE_INT32

# ---- Build dynamic Protobuf class ----
pool = descriptor_pool.Default()
file_desc = pool.Add(file_desc_proto)
message_desc = file_desc.message_types_by_name["SensorUpdate"]
SensorUpdate = GetMessageClass(message_desc)

# ---- Schema Registry ----
schema_registry_conf = {
    "url": SCHEMA_REGISTRY_URL,
    "basic.auth.user.info": f"{SR_USERNAME}:{SR_PASSWORD}"
}
schema_registry_client = SchemaRegistryClient(schema_registry_conf)

protobuf_serializer = ProtobufSerializer(
    SensorUpdate,
    schema_registry_client,
    {"use.deprecated.format": False}
)

# ---- Kafka Producer (SASL/SSL) ----
producer_conf = {
    "bootstrap.servers": BOOTSTRAP_SERVERS,
    "security.protocol": "SASL_SSL",
    "sasl.mechanism": "PLAIN",
    "sasl.username": KAFKA_USERNAME,
    "sasl.password": KAFKA_PASSWORD,
    "value.serializer": protobuf_serializer
}

def read_sensor_updates():
    producer = SerializingProducer(producer_conf)

    def delivery_report(err, msg):
        if err:
            print(f"Delivery failed: {err}")
        else:
            print(f"Sent to {msg.topic()} [{msg.partition()}]")

    try:
        while True:
            sensor_id = f"sensor_{random.randint(1, 100)}"
            sensor_value = random.uniform(0, 100)
            tag_list = [random.randint(1, 10) for _ in range(3)]
            now = datetime.utcnow()

            # Build Protobuf record and produce to Kafka
            record = SensorUpdate(
                id=sensor_id,
                value=sensor_value,
                tags=tag_list
            )

            producer.produce(
                topic=TOPIC,
                value=record,
                on_delivery=delivery_report
            )
            producer.poll(0)

            # Yield the same record to Timeplus
            yield (
                sensor_id,
                float(sensor_value),
                json.dumps(tag_list),
                TOPIC,
                now,
            )

            time.sleep(1)
    finally:
        producer.flush()

$$
SETTINGS type='python', mode='streaming', read_function_name='read_sensor_updates';


-- MV that write data to kafka
CREATE STREAM case5.proto_kafka_sink (
    id string,
    value float32,
    tags array(int32)
);

CREATE MATERIALIZED VIEW case5.mv_write_to_kafka
INTO case5.proto_kafka_sink
AS 
SELECT * FROM case5.sensor_update_datagen;


-- read data from kafka broker with protobuf and schema registry
CREATE EXTERNAL STREAM case5.proto_kafka_source (
    id string,
    value float32,
    tags array(int32)
) SETTINGS 
    type='kafka',
    topic='sensor-update',
    config_file='/etc/timeplus/config.yaml',
    data_format='ProtobufSingle',
    schema_subject_name='sensor-update';

