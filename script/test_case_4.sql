CREATE DATABASE IF NOT EXISTS case4;

CREATE RANDOM STREAM case4.avro_verification_gen (
    customer_id string default 'cust_' || to_string(rand() % 500),
    transaction_amount float64 default rand_uniform(10.0, 1000.0),
    promotion_code nullable(string) default (rand() % 2 = 0? 'SUMMER' : null)
) SETTINGS eps=10;

CREATE EXTERNAL STREAM case4.avro_kafka_sink (
    customer_id string,
    transaction_amount float64,
    promotion_code nullable(string)
) SETTINGS 
    type='kafka',
    topic='verify_avro_v1',
    config_file='/etc/timeplus/config.yaml',
    schema_subject_name='case4.avro_verification',
    data_format='Avro';

CREATE MATERIALIZED VIEW case4.mv_avro_verify
INTO case4.avro_kafka_sink
AS 
SELECT * FROM case4.avro_verification_gen;  