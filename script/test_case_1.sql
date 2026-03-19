CREATE DATABASE IF NOT EXISTS case1;

-- simulated data
CREATE RANDOM STREAM case1.json_verification_gen (
    device_id string default 'sensor-' || to_string(rand() % 100),
    reading_value float64 default rand_uniform(0, 100),
    is_active bool default to_bool(rand() % 2),
    status string default ['ok', 'warn', 'error'][rand() % 3 + 1],
    event_timestamp datetime64(3) default now64(3)
) SETTINGS eps=10;

-- write to kafka
CREATE EXTERNAL STREAM case1.json_kafka_sink (
    device_id string,
    reading_value float64,
    is_active bool,
    status string,
    event_timestamp datetime64(3)
) SETTINGS 
    type='kafka',
    topic='verify_json_v1',
    config_file='/etc/timeplus/config.yaml',
    data_format='JSONEachRow',
    one_message_per_row=true;

CREATE MATERIALIZED VIEW case1.mv_json_verify
INTO case1.json_kafka_sink
AS 
SELECT * FROM case1.json_verification_gen;

-- this source is duplicated from sink, which is optiona
-- timeplus support external stream as bi-directional
CREATE EXTERNAL STREAM case1.json_kafka_source (
    device_id string,
    reading_value float64,
    is_active bool,
    status string,
    event_timestamp datetime64(3)
) SETTINGS 
    type='kafka',
    topic='verify_json_v1',
    config_file='/etc/timeplus/config.yaml',
    data_format='JSONEachRow',
    one_message_per_row=true;

SELECT
  date_diff('millisecond', event_timestamp, now64()) AS latency
FROM
  case1.json_kafka_source