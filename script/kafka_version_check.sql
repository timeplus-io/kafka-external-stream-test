CREATE OR REPLACE FUNCTION check_kafka_version(x string)
RETURNS string
LANGUAGE python
AS $$
import confluent_kafka

def check_kafka_version(input_batch):
    # Get the versions
    py_ver = confluent_kafka.__version__
    librd_ver_str, _ = confluent_kafka.libversion()
    
    result_str = f"Package: {py_ver} | librdkafka: {librd_ver_str}"
    
    # Return the result for each row in the input batch
    return [result_str] * len(input_batch)
$$;