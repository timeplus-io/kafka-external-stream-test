CREATE DATABASE IF NOT EXISTS case5;

CREATE RANDOM STREAM case5.proto_verification_gen (
    id string default 'dev-' || to_string(rand() % 100),
    value float32 default rand_uniform(20.0, 40.0),
    tags array(int32) default [rand() % 10, rand() % 100]
) SETTINGS eps=10;

CREATE EXTERNAL STREAM case5.proto_kafka_sink (
    id string,
    value float32,
    tags array(int32)
) SETTINGS 
    type='kafka',
    topic='verify_proto_v1',
    config_file='/etc/timeplus/config.yaml',
    schema_subject_name='case5.sensor-update',
    ;

-- write with protobuf with schema registry is not supported by timeplus now, will return error
-- CREATE MATERIALIZED VIEW case5.mv_proto_verify
-- INTO case5.proto_kafka_sink
-- AS 
-- SELECT * FROM case5.proto_verification_gen;
