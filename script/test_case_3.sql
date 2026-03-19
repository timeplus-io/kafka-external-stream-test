CREATE DATABASE IF NOT EXISTS case3;

CREATE OR REPLACE FORMAT SCHEMA proto_verify_v1 AS '
syntax = "proto3";

message SensorUpdate {
    string id = 1;
    float value = 2;
    repeated int32 tags = 3;
}
' TYPE Protobuf;

CREATE RANDOM STREAM case3.proto_verification_gen (
    id string default 'dev-' || to_string(rand() % 100),
    value float32 default rand_uniform(20.0, 40.0),
    tags array(int32) default [rand() % 10, rand() % 100]
) SETTINGS eps=10;

CREATE EXTERNAL STREAM case3.proto_kafka_sink (
    id string,
    value float32,
    tags array(int32)
) SETTINGS 
    type='kafka',
    topic='verify_proto_v1',
    config_file='/etc/timeplus/config.yaml',
    data_format='ProtobufSingle',
    format_schema='proto_verify_v1:SensorUpdate';

CREATE MATERIALIZED VIEW case3.mv_proto_verify
INTO case3.proto_kafka_sink
AS 
SELECT * FROM case3.proto_verification_gen;

CREATE EXTERNAL STREAM case3.proto_kafka_source (
    id string,
    value float32,
    tags array(int32)
) SETTINGS 
    type='kafka',
    topic='verify_proto_v1',
    config_file='/etc/timeplus/config.yaml',
    data_format='ProtobufSingle',
    format_schema='proto_verify_v1:SensorUpdate';


