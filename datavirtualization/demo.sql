/*
     Step 0 - Enable PolyBase and advanced options, this is required to use OPENROWSET and external tables
     New to SQL Server 2025 is the 'allow polybase export' option which is required to use PolyBase with object storage and doesn't require the installation of Polybase
*/
USE master;
GO

sp_configure 'show advanced options', 1;
RECONFIGURE;
GO
sp_configure 'allow polybase export', 1;
RECONFIGURE;
GO


/*
     Step 1 - Create a database to hold objects for the demo and switch to that context
*/ 
CREATE DATABASE [DataVirtualizationDemo];
GO

USE DataVirtualizationDemo;
GO



/*
     Step 2 - Create a database master key, this is use to protect the credentials you're about to create
*/ 
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'S0methingS@Str0ng!';  


/*
     Step 3 - Create a database scoped credential, this should have at minimum ReadOnly and ListBucket access to the s3 bucket
*/
CREATE DATABASE SCOPED CREDENTIAL s3_dc WITH IDENTITY = 'S3 Access Key', SECRET = 'anthony:nocentino' ;


/*
     Step 4 - Create your external datasource on your s3 compatible object storage, referencing where it is on the network (LOCATION) and the credential you just defined
*/
CREATE EXTERNAL DATA SOURCE s3_ds
WITH
(    LOCATION = 's3://s3.example.com:9000/'
,    CREDENTIAL = s3_dc
)


/*
     Step 5 - First we can access data in the s3 bucket and for a simple test, let's start with CSV. During the docker compose up, the build copied a csv into the bucket it created.
     This should output Hello World! several times.
*/

SELECT  * 
FROM OPENROWSET
(    BULK '/sqldatavirt/helloworld.csv'
,    FORMAT       = 'CSV'
,    DATA_SOURCE  = 's3_ds'
) 
WITH ( c1 int, c2 varchar(20) )
AS   [Test1]


/*
     Step 6 - OPENROWSET is cool for infrequent access, but if you want to layer on sql server security or use statistics on the data in the external data source,
     create let's create an external table. This first requires defining an external file format. In this example its CSV
*/
CREATE EXTERNAL FILE FORMAT CSVFileFormat
WITH
(    FORMAT_TYPE = DELIMITEDTEXT
,    FORMAT_OPTIONS  ( FIELD_TERMINATOR = ','
,                      STRING_DELIMITER = '"'
,                      FIRST_ROW = 1 )
);


/*
     Step 7 - Next we define the table's structure. The CSV here is mega simple, just a single row with a single column
     When defining the external table where the data lives on our network with DATA_SOURCE, the LOCATION within that DATA_SOURCE and the FILE_FORMAT
*/
CREATE EXTERNAL TABLE HelloWorld ( c1 int, c2 varchar(20) )
WITH (
     DATA_SOURCE = s3_ds
,    LOCATION = '/sqldatavirt/helloworld.csv'
,    FILE_FORMAT = CSVFileFormat
);

/*
     Step 8 - Now we can access the data just like any other table in sql server. 
*/
SELECT * FROM [HelloWorld];



/*
     Step 9 - Let's try something a bit more complex, Parquet.
*/
CREATE EXTERNAL FILE FORMAT ParquetFileFormat
WITH
(    FORMAT_TYPE = PARQUET
);

/*
     Step 10 - Let's use CETAS to write our data into the s3 bucket as parquet, then read it back with an external table
*/
CREATE EXTERNAL TABLE ParquetHelloWorld 
WITH ( DATA_SOURCE = s3_ds
     , LOCATION = '/sqldatavirt/ParquetHelloWorld.parquet'
     , FILE_FORMAT = ParquetFileFormat
     , REJECT_TYPE = VALUE
     , REJECT_VALUE = 0
     )
AS
SELECT * FROM HelloWorld;

/*
     Step 11 - Now we can query the parquet data via the external table.
*/
SELECT * FROM ParquetHelloWorld;
GO