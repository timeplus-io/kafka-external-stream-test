# **Technical Framework for Validating Apache Kafka Integrations within the Timeplus Streaming Ecosystem**

The integration of high-performance message brokers like Apache Kafka with real-time analytical engines is a cornerstone of modern event-driven architectures. Within this domain, Timeplus, and its open-source core Proton, provides a sophisticated SQL-centric interface for interacting with Kafka clusters, offering native support for diverse serialization formats and complex security protocols. To ensure the reliability of data pipelines, engineers must implement a rigorous verification framework that exercises the full lifecycle of an event—from generation and egress to ingestion and validation. The following report details a comprehensive test suite designed to verify Kafka-related features in Timeplus, specifically tailored for environments utilizing SASL Plain authentication and Confluent-compatible Schema Registries.

## **Architectural Foundations of the Verification Loop**

The verification strategy is built upon a four-stage closed-loop process. This methodology leverages the internal capabilities of the Timeplus engine to simulate controlled workloads and validate the integrity of the data as it traverses the network boundary between the processing engine and the Kafka broker.

1. **Synthetic Data Generation**: Utilizing the CREATE RANDOM STREAM DDL to define a baseline of expected values, data types, and ingestion rates.  
2. **Egress via Materialized View**: Establishing an outbound pipeline where a Materialized View acts as a continuous producer, writing data from the random stream into a Kafka topic via a specialized External Stream sink.  
3. **Ingestion via External Stream**: Creating a corresponding inbound External Stream that acts as a consumer, subscribing to the target Kafka topic using the specified security and format parameters.  
4. **Analytical Validation**: Executing streaming SQL queries to compare the ingested data against the original generated set, verifying serialization fidelity, metadata preservation, and authentication success.

### **Configuration of Authentication and Security Parameters**

In enterprise environments, security is often implemented via the Simple Authentication and Security Layer (SASL) using the PLAIN mechanism. This requires the processing engine to pass cleartext credentials over a secure (SASL\_SSL) or non-secure (SASL\_PLAINTEXT) transport. Furthermore, when a Schema Registry is involved, the credentials must often be shared across both the broker and the registry endpoints to simplify identity management.

| Component | Setting Key | Value Description |
| :---- | :---- | :---- |
| **Kafka Broker** | security\_protocol | SASL\_PLAINTEXT or SASL\_SSL |
| **Kafka Broker** | sasl\_mechanism | PLAIN |
| **Kafka Broker** | username | Shared Username |
| **Kafka Broker** | password | Shared Password |
| **Schema Registry** | kafka\_schema\_registry\_url | Full HTTP/S URL of the Registry |
| **Schema Registry** | kafka\_schema\_registry\_credentials | username:password |

The alignment of these credentials within the SETTINGS clause of the External Stream definition is the first critical point of verification. Failure to match the username:password format for the registry credentials will result in an inability to fetch or register schemas, halting the data pipeline.

## **Advanced Synthetic Data Generation with Random Streams**

Before testing the Kafka interface, a robust data source must be established. Timeplus random streams are memory-resident generators that do not persist data but provide a high-fidelity stream of events for testing. These streams allow for precise control over the volume and structure of data, which is essential for performance benchmarking and schema validation.

### **Controlled Generation and EPS Tuning**

The eps (events per second) setting allows testers to simulate various traffic patterns. For sub-second testing, values less than 1 are supported (e.g., eps=0.5 generates one event every two seconds), while high-throughput testing can exceed tens of thousands of events per second.

| Function | Type | Description |
| :---- | :---- | :---- |
| rand() | uint32 | Standard random number generation. |
| rand64() | uint64 | Large integer generation. |
| random\_printable\_ascii(n) | string | Generates a readable string of length n. |
| random\_in\_type(t, max, lambda) | Custom | Highly flexible generation with custom logic. |
| rand\_normal(mean, var) | float64 | Generates values following a normal distribution. |

By using random\_in\_type with lambda expressions, testers can create complex, realistic data, such as incrementing sequences or date ranges, ensuring the Kafka sink is tested against realistic edge cases.

## **Test Case Suite I: JSON Serialization and Schema-on-Read**

JSON remains a primary format for web-scale event streams due to its flexibility and human-readable nature. Timeplus handles JSON through the JSONEachRow format, which maps top-level keys to stream columns while allowing the engine to handle data mutations and schema variations effectively.

### **Step 1: Data Generation for JSON**

The goal here is to create a stream with multiple data types to verify the conversion of Timeplus internal types to JSON strings.

SQL

```

CREATE RANDOM STREAM json_verification_gen (
    device_id string default 'sensor-' || to_string(rand() % 100),
    reading_value float64 default rand_uniform(0, 100),
    is_active bool default to_bool(rand() % 2),
    status string default ['ok', 'warn', 'error'][rand() % 3 + 1],
    event_timestamp datetime64(3) default now64(3)
) SETTINGS eps=10;

```

### **Step 2: Egress via Materialized View**

For the sink, we configure an External Stream with data\_format='JSONEachRow' and one\_message\_per\_row=true to ensure each Kafka message is a discrete, valid JSON object.

SQL

```

CREATE EXTERNAL STREAM json_kafka_sink (
    device_id string,
    reading_value float64,
    is_active bool,
    status string,
    event_timestamp datetime64(3)
) SETTINGS 
    type='kafka',
    brokers='<Kafka_Broker_URL>',
    topic='verify_json_v1',
    security_protocol='SASL_PLAINTEXT',
    sasl_mechanism='PLAIN',
    username='<Username>',
    password='<Password>',
    data_format='JSONEachRow',
    one_message_per_row=true;

CREATE MATERIALIZED VIEW mv_json_verify INTO json_kafka_sink AS 
SELECT * FROM json_verification_gen;

```

### **Step 3: Ingress and Source Configuration**

The inbound stream must be configured with identical credentials and format settings. A key feature to verify here is the automatic mapping of the JSON payload to the defined columns.

SQL

```

CREATE EXTERNAL STREAM json_kafka_source (
    device_id string,
    reading_value float64,
    is_active bool,
    status string,
    event_timestamp datetime64(3)
) SETTINGS 
    type='kafka',
    brokers='<Kafka_Broker_URL>',
    topic='verify_json_v1',
    security_protocol='SASL_PLAINTEXT',
    sasl_mechanism='PLAIN',
    username='<Username>',
    password='<Password>',
    data_format='JSONEachRow';

```

### **Step 4: Analytical Validation Query**

Validation involves checking the consistency of the data and extracting Kafka-specific metadata to ensure the transport layer is functioning correctly.

SQL

```

SELECT 
    device_id, 
    reading_value, 
    _tp_shard, 
    _tp_sn, 
    _tp_time 
FROM json_kafka_source 
LIMIT 10;

```

This query confirms that the device\_id string and the reading\_value float survived the serialization process. Furthermore, the presence of \_tp\_shard and \_tp\_sn proves that Timeplus is correctly communicating with the Kafka broker's partition leaders and offset management system.

## **Test Case Suite II: Raw Text and Log Stream Verification**

In many legacy or high-throughput log-aggregation scenarios, data is transmitted as unparsed text. The RawBLOB format in Timeplus is designed for these scenarios, treating the message payload as an opaque string. This allows for the highest possible ingestion speed while deferring parsing to the query layer.

### **Step 1: Raw Data Generation**

This random stream simulates a combined log line that includes a timestamp, a log level, and a message body.

SQL

```

CREATE RANDOM STREAM raw_verification_gen (
    raw_log string default to_string(now()) || ' [INFO] user_activity: ' || random_printable_ascii(15)
) SETTINGS eps=5;

```

### **Step 2: Sink with RawBLOB Configuration**

The sink should contain a single column, typically named raw, to hold the entire message.

SQL

```

CREATE EXTERNAL STREAM raw_kafka_sink (
    raw string
) SETTINGS 
    type='kafka',
    brokers='<Kafka_Broker_URL>',
    topic='verify_raw_v1',
    security_protocol='SASL_PLAINTEXT',
    sasl_mechanism='PLAIN',
    username='<Username>',
    password='<Password>',
    data_format='RawBLOB';

CREATE MATERIALIZED VIEW mv_raw_verify INTO raw_kafka_sink AS 
SELECT raw_log AS raw FROM raw_verification_gen;

```

### **Step 3: Source and Query-Time Transformation**

The validation of RawBLOB data often involves using Timeplus’s built-in string manipulation and JSON parsing functions to extract information at search time.

SQL

```

CREATE EXTERNAL STREAM raw_kafka_source (
    raw string
) SETTINGS 
    type='kafka',
    brokers='<Kafka_Broker_URL>',
    topic='verify_raw_v1',
    security_protocol='SASL_PLAINTEXT',
    sasl_mechanism='PLAIN',
    username='<Username>',
    password='<Password>',
    data_format='RawBLOB';

-- Validation Query using string splitting
SELECT 
    raw,
    extract(raw, '\[(.*?)\]') as log_level,
    substring(raw, length(raw)-14) as content
FROM raw_kafka_source 
LIMIT 10;

```

This test case verifies that Timeplus preserves the exact byte sequence of the original string, including spaces and special characters, without performing any unwanted escaping.

## **Test Case Suite III: Protobuf Serialization with Local Schema Management**

Protocol Buffers (Protobuf) provide a compact, binary serialization format that is highly efficient for high-volume telemetry. Unlike JSON, Protobuf requires a predefined schema. In Timeplus, this is managed via the CREATE FORMAT SCHEMA statement, which registers the .proto definition within the engine.

### **Step 1: Format Schema Registration**

Registration is required before the External Stream can be defined. This allows the engine to compile the necessary serialization logic.

SQL

```

CREATE OR REPLACE FORMAT SCHEMA proto_verify_v1 AS '
syntax = "proto3";

message SensorUpdate {
    string id = 1;
    float value = 2;
    repeated int32 tags = 3;
}
' TYPE Protobuf;

```

### **Step 2: Data Generation for Binary Verification**

Testing Protobuf requires validating the handling of repeated fields (mapped to array) and nested messages.

SQL

```

CREATE RANDOM STREAM proto_verification_gen (
    id string default 'dev-' || to_string(rand() % 100),
    value float32 default rand_uniform(20.0, 40.0),
    tags array(int32) default [rand() % 10, rand() % 100]
) SETTINGS eps=5;

```

### **Step 3: Sink with ProtobufSingle Setting**

The ProtobufSingle data format is used when each Kafka message contains exactly one Protobuf record.

SQL

```

CREATE EXTERNAL STREAM proto_kafka_sink (
    id string,
    value float32,
    tags array(int32)
) SETTINGS 
    type='kafka',
    brokers='<Kafka_Broker_URL>',
    topic='verify_proto_v1',
    security_protocol='SASL_PLAINTEXT',
    sasl_mechanism='PLAIN',
    username='<Username>',
    password='<Password>',
    data_format='ProtobufSingle',
    format_schema='proto_verify_v1:SensorUpdate';

CREATE MATERIALIZED VIEW mv_proto_verify INTO proto_kafka_sink AS 
SELECT * FROM proto_verification_gen;

```

The format\_schema parameter must reference both the registered schema name and the message type within that schema, separated by a colon.

### **Step 4: Binary Deserialization and Validation**

The source stream uses the same registered schema to decode the binary payload back into a structured format for querying.

SQL

```

CREATE EXTERNAL STREAM proto_kafka_source (
    id string,
    value float32,
    tags array(int32)
) SETTINGS 
    type='kafka',
    brokers='<Kafka_Broker_URL>',
    topic='verify_proto_v1',
    security_protocol='SASL_PLAINTEXT',
    sasl_mechanism='PLAIN',
    username='<Username>',
    password='<Password>',
    data_format='ProtobufSingle',
    format_schema='proto_verify_v1:SensorUpdate';

-- Validation Query checking array handling
SELECT 
    id, 
    value, 
    tags as primary_tag 
FROM proto_kafka_source 
WHERE value > 30 
LIMIT 10;

```

A successful result demonstrates the engine’s ability to correctly map Timeplus arrays to Protobuf repeated fields and perform binary-to-vectorized conversions without data loss.

## **Test Case Suite IV: Avro and Schema Registry Integration**

For enterprise-grade streaming, Apache Avro combined with a Schema Registry is the standard for ensuring schema evolution and backward compatibility. Verification in this context involves not just the data transport, but the authentication to the registry and the correct handling of schema IDs prepended to the binary payload.

### **Step 0: Pre-requisite - Register Avro Schema**

Before creating the external streams, the Avro schema must be registered with the Schema Registry. This can be done using the provided Python script.

```bash
# Set environment variables in schema/case4/.env first
python schema/case4/register.py
```

### **Step 1: Data Generation with Nullable Types**

Avro is particularly adept at handling optional fields using unions. Verification should include nullable types to test this functionality.

SQL

```

CREATE RANDOM STREAM avro_verification_gen (
    customer_id string default 'cust_' || to_string(rand() % 500),
    transaction_amount float64 default rand_uniform(10.0, 1000.0),
    promotion_code nullable(string) default (rand() % 2 = 0? 'SUMMER' : null)
) SETTINGS eps=10;

```

### **Step 2: Sink with Schema Registry Credentials**

The sink configuration is the most complex, requiring both Kafka and Registry settings. The shared credentials must be correctly mapped as per the original requirement.

SQL

```

CREATE EXTERNAL STREAM avro_kafka_sink (
    customer_id string,
    transaction_amount float64,
    promotion_code nullable(string)
) SETTINGS 
    type='kafka',
    brokers='<Kafka_Broker_URL>',
    topic='verify_avro_v1',
    security_protocol='SASL_PLAINTEXT',
    sasl_mechanism='PLAIN',
    username='<Username>',
    password='<Password>',
    data_format='Avro',
    kafka_schema_registry_url='<Schema_Registry_URL>',
    kafka_schema_registry_credentials='<Username>:<Password>',
    schema_subject_name='case4.avro_verification';

CREATE MATERIALIZED VIEW mv_avro_verify INTO avro_kafka_sink AS 
SELECT * FROM avro_verification_gen;

```

### **Step 3: Implicit Schema Inference in Source**

A powerful feature of the Timeplus-Avro integration is that if the Schema Registry is properly configured, the source stream can often infer the schema directly, though explicitly defining columns provides stronger typing during validation.

SQL

```

CREATE EXTERNAL STREAM avro_kafka_source (
    customer_id string,
    transaction_amount float64,
    promotion_code nullable(string)
) SETTINGS 
    type='kafka',
    brokers='<Kafka_Broker_URL>',
    topic='verify_avro_v1',
    security_protocol='SASL_PLAINTEXT',
    sasl_mechanism='PLAIN',
    username='<Username>',
    password='<Password>',
    data_format='Avro',
    kafka_schema_registry_url='<Schema_Registry_URL>',
    kafka_schema_registry_credentials='<Username>:<Password>',
    schema_subject_name='case4.avro_verification';

```

### **Step 4: Aggregation-Based Validation**

Validation for Avro often involves complex aggregations to ensure that the data types were correctly mapped to their high-precision Timeplus equivalents.

SQL

```

SELECT 
    customer_id, 
    sum(transaction_amount) as total_spent, 
    count(*) as trans_count 
FROM avro_kafka_source 
GROUP BY customer_id 
HAVING trans_count > 1 
LIMIT 10;

```

This test case verifies the connectivity to the Schema Registry, the successful retrieval of the Avro schema, and the accurate decoding of the binary data based on that schema.

## **Comparative Analysis of Kafka Features and Data Formats**

The choice of data format has significant implications for both system performance and data governance. The following table summarizes the observed behaviors and technical requirements for each format during the verification process.

| Feature | JSONEachRow | RawBLOB | Protobuf | Avro |
| :---- | :---- | :---- | :---- | :---- |
| **Schema Source** | Inferred (Read) | None | Local SQL DDL | Registry |
| **Binary Output** | No | Optional | Yes | Yes |
| **Auth Complexity** | Low | Low | Medium | High |
| **Performance** | Medium | Highest | High | High |
| **Metadata Support** | Full | Full | Full | Full |
| **Null Handling** | Dynamic | Manual | Default Values | Unions |

The use of RawBLOB is ideal for high-speed ingestion of logs where structure is determined later, whereas Avro and Protobuf are preferred for transactional systems where schema enforcement and network efficiency are paramount.

## **Operational Management and Performance Tuning**

Beyond the basic DDL, Timeplus provides several operational commands and settings to manage the Kafka integration. For instance, Materialized Views can be paused and resumed using the SYSTEM command, which is useful when the Kafka cluster is undergoing maintenance.

### **Checkpointing and Fault Tolerance**

Materialized Views that write to Kafka utilize checkpoints to maintain the query state and ensure that no data is lost or duplicated in the event of a system failure.

* **checkpoint\_interval**: Controls the frequency of state persistence. Shorter intervals reduce recovery time but increase I/O overhead.  
* **replication\_type**: Defines how the checkpoint data is stored across the cluster, with nativelog being a standard choice for high-availability deployments.

### **Throughput Optimization with Vectorized Batches**

To maximize the performance of the Kafka sink, the max\_insert\_block\_bytes and max\_insert\_block\_size settings should be adjusted. These parameters control the size of the memory blocks that are flushed to Kafka, allowing the engine to take advantage of Kafka's batching capabilities.

SQL

```

-- Example of a performance-optimized sink
CREATE EXTERNAL STREAM high_perf_sink (
    payload string
) SETTINGS 
    type='kafka',
    topic='load_test',
    max_insert_block_bytes=2097152, -- 2MB batches
    max_insert_block_size=100000;    -- 100k rows per flush

```

## **Test Case Suite V: Protobuf and Schema Registry Integration**

This test case exercises the integration of Protobuf serialization with a Confluent-compatible Schema Registry. Unlike Case III, which uses local schema management, this case relies on the registry to manage versions and provide the schema to the processing engine.

### **Step 0: Pre-requisite - Register Protobuf Schema**

First, register the Protobuf schema with the Schema Registry using the provided script.

```bash
# Set environment variables (SCHEMA_REGISTRY_URL, etc.)
python schema/case5/register.py
```

### **Step 1: Data Generation via Python External Stream**

In this scenario, we use a Python-based External Stream to generate and serialize Protobuf data, producing it directly to Kafka while also yielding it to Timeplus for comparison.

```sql
CREATE DATABASE IF NOT EXISTS case5;

CREATE EXTERNAL STREAM case5.sensor_update_datagen(
    id string, 
    value float64, 
    tags string, 
    kafka_topic string, 
    generated_at datetime64(3)
)
AS $$
# ... (Python producer logic using confluent_kafka.schema_registry.protobuf)
$$
SETTINGS type='python', mode='streaming', read_function_name='read_sensor_updates';
```

### **Step 2: Sink with Protobuf and Registry Settings**

The sink is configured to write data back to Kafka (if needed for further validation) or simply as a reference for the DDL structure.

```sql
CREATE EXTERNAL STREAM case5.proto_kafka_sink (
    id string,
    value float32,
    tags array(int32)
) SETTINGS 
    type='kafka',
    brokers='<Kafka_Broker_URL>',
    topic='sensor-update',
    data_format='ProtobufSingle',
    kafka_schema_registry_url='<Schema_Registry_URL>',
    kafka_schema_registry_credentials='<Username>:<Password>',
    schema_subject_name='sensor-update';
```

### **Step 3: Ingress via Schema Registry**

The source stream leverages the Schema Registry to automatically decode the incoming Protobuf messages.

```sql
CREATE EXTERNAL STREAM case5.proto_kafka_source (
    id string,
    value float32,
    tags array(int32)
) SETTINGS 
    type='kafka',
    brokers='<Kafka_Broker_URL>',
    topic='sensor-update',
    data_format='ProtobufSingle',
    kafka_schema_registry_url='<Schema_Registry_URL>',
    kafka_schema_registry_credentials='<Username>:<Password>',
    schema_subject_name='sensor-update';
```

### **Step 4: Analytical Validation**

```sql
SELECT 
    id, 
    value, 
    tags 
FROM case5.proto_kafka_source 
LIMIT 10;
```

