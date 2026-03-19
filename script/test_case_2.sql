CREATE DATABASE IF NOT EXISTS case2;

CREATE RANDOM STREAM case2.raw_verification_gen (
    raw_log string default to_string(now()) || ' [INFO] user_activity: ' || random_printable_ascii(15)
) SETTINGS eps=10;

CREATE EXTERNAL STREAM case2.raw_kafka_sink (
    raw string
) SETTINGS 
    type='kafka',
    topic='verify_raw_v1',
    config_file='/etc/timeplus/config.yaml',
    data_format='RawBLOB';

CREATE MATERIALIZED VIEW case2.mv_raw_verify
INTO case2.raw_kafka_sink
AS 
SELECT raw_log as raw FROM case2.raw_verification_gen;

CREATE EXTERNAL STREAM case2.raw_kafka_source (
    raw string
) SETTINGS 
    type='kafka',
    topic='verify_raw_v1',
    config_file='/etc/timeplus/config.yaml',
    data_format='RawBLOB';

SELECT 
    raw,
    extract(raw, '\[(.*?)\]') as log_level,
    substring(raw, length(raw)-14) as content
FROM case2.raw_kafka_source 