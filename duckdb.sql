CREATE OR REPLACE SECRET secret (
    TYPE s3,
    PROVIDER config,
    KEY_ID 'anthony',
    URL_STYLE 'path',
    SECRET 'nocentino',
    ENDPOINT 'localhost:9000' 
);

SELECT *
FROM 's3://sqldatavirt/ParquetHelloWorld.parquet/*.parquet';
