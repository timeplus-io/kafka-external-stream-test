# pip install 

import os
import time
import random
from dotenv import load_dotenv

from confluent_kafka import SerializingProducer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.protobuf import ProtobufSerializer

from google.protobuf import descriptor_pb2, descriptor_pool, message_factory
from google.protobuf.message_factory import GetMessageClass

# ---- Load env ----
load_dotenv()

BOOTSTRAP_SERVERS = os.getenv("KAFKA_BOOTSTRAP_SERVERS")
KAFKA_USERNAME = os.getenv("KAFKA_USERNAME")
KAFKA_PASSWORD = os.getenv("KAFKA_PASSWORD")

SCHEMA_REGISTRY_URL = os.getenv("SCHEMA_REGISTRY_URL")
SR_USERNAME = os.getenv("SCHEMA_REGISTRY_USERNAME")
SR_PASSWORD = os.getenv("SCHEMA_REGISTRY_PASSWORD")

TOPIC = "sensor-update"

# ---- Define proto schema inline ----
file_desc_proto = descriptor_pb2.FileDescriptorProto()
file_desc_proto.name = "sensor.proto"
file_desc_proto.syntax = "proto3"

# message SensorUpdate
msg = file_desc_proto.message_type.add()
msg.name = "SensorUpdate"

# string id = 1;
field1 = msg.field.add()
field1.name = "id"
field1.number = 1
field1.label = descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL
field1.type = descriptor_pb2.FieldDescriptorProto.TYPE_STRING

# float value = 2;
field2 = msg.field.add()
field2.name = "value"
field2.number = 2
field2.label = descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL
field2.type = descriptor_pb2.FieldDescriptorProto.TYPE_FLOAT

# repeated int32 tags = 3;
field3 = msg.field.add()
field3.name = "tags"
field3.number = 3
field3.label = descriptor_pb2.FieldDescriptorProto.LABEL_REPEATED
field3.type = descriptor_pb2.FieldDescriptorProto.TYPE_INT32

# ---- Build dynamic class ----
pool = descriptor_pool.Default()
file_desc = pool.Add(file_desc_proto)

message_desc = file_desc.message_types_by_name["SensorUpdate"]
factory = message_factory.MessageFactory()
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

# ---- Kafka Producer (SASL/PLAIN) ----
producer_conf = {
    "bootstrap.servers": BOOTSTRAP_SERVERS,
    "security.protocol": "SASL_SSL",  # or SASL_PLAINTEXT
    "sasl.mechanism": "PLAIN",
    "sasl.username": KAFKA_USERNAME,
    "sasl.password": KAFKA_PASSWORD,
    "value.serializer": protobuf_serializer
}

producer = SerializingProducer(producer_conf)

def delivery_report(err, msg):
    if err:
        print("❌ Delivery failed:", err)
    else:
        print(f"✅ Sent to {msg.topic()} [{msg.partition()}]")

# ---- Produce loop ----
while True:
    record = SensorUpdate(
        id=f"sensor_{random.randint(1,100)}",
        value=random.uniform(0, 100),
        tags=[random.randint(1, 10) for _ in range(3)]
    )

    producer.produce(
        topic=TOPIC,
        value=record,
        on_delivery=delivery_report
    )

    producer.poll(0)
    time.sleep(1)