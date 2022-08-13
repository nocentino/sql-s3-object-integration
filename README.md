# sql-s3-object-integration

In this repo, you'll find two example environments for using SQL Server 2022's s3 object integration.  one for [backup and restore](#backup-and-restore-test-environment) to s3 compatible object storage and the other for [data virtualization](#polybase-and-s3-data-virtualiation-enviroment) using Polybase connectivity to s3 compatible object storage.  This work aims to get you up and running as quickly as possible to work with these new features.  I implemented this in Docker Compose since that handles all the implementation and configuration steps for you.

Let's walk through what you'll get in each environment. 

## Backup and Restore Test Environment

First, in this repo's `backup` directory, there's a script `demo.sh`.  In this script, you will find the commands needed to start the environment and do a basic connectivity test using a SQL Server backup.  To start everything up, you'll change into the `backup` directory and run `docker-compose up --detach`.  This docker-compose manifest will do a few things...let's walk through that.

```
docker-compose up --detach
```

1.  First, since SQL Server's s3 object integration requires a valid and trusted certificate, a service named `config` runs a container that creates the required certificate needed for this environment and stores them in the current working directory in a subdirectory named `certs`.

```
  config:
    build:
      context: .
      dockerfile: dockerfile.ssl
    volumes:
      - ./openssl.cnf:/tmp/certs/openssl.cnf
      - ./certs:/certs
    command: openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /certs/private.key -out /certs/public.crt -config /tmp/certs/openssl.cnf
```

2.  Second, we start a service named `minio1` that starts a MinIO container on a static IP address of `172.18.0.2` and exposes the data and admin ports on `9000` and `9001`.  There are also two volumes defined a data volume `s3-data` for the object data stored in MinIO, and the other, `certs` is a bind mount exposing the certificates into the MinIO container for use TLS connections.  MinIO automatically configures itself for TLS connectivity when it finds certificates in this location.  The final configurations are the root username and password environment variables and the `command` starting up the container. 

```
  minio1:
    image: quay.io/minio/minio
    depends_on: 
      - config
    hostname: minio1
    networks:
      s3-data:
        ipv4_address: 172.18.0.20
    extra_hosts:
      - "s3.example.com:172.18.0.20"
    ports:
      - 9000:9000
      - 9001:9001
    volumes:
      - s3-data:/data
      - ./certs:/root/.minio/certs/
    environment:
      - MINIO_ROOT_USER=MYROOTUSER
      - MINIO_ROOT_PASSWORD=MYROOTPASSWORD
    command: server /data --console-address ":9001" 
```

3.  Next, the `createbucket` service creates a user in MinIO that we will use inside SQL Server to access MinIO and also creates a bucket named `sqlbackups` for our backup and restore testing.

```
  createbucket:
    image: minio/mc
    networks:
      s3-data:
    extra_hosts:
      - "s3.example.com:172.18.0.20"
    depends_on:
      - minio1
    entrypoint: /bin/sh -c "/usr/bin/mc alias set s3admin https://s3.example.com:9000 MYROOTUSER MYROOTPASSWORD --api S3v4 --insecure;
                            /usr/bin/mc admin user add s3admin anthony nocentino --insecure;
                            /usr/bin/mc admin policy set s3admin readwrite user=anthony --insecure;
                            /usr/bin/mc alias set anthony https://s3.example.com:9000 anthony nocentino --insecure;
                            /usr/bin/mc mb anthony/sqlbackups  --insecure;"
```

1.  Finally, we start a service named `sql1`, which runs the latest published container image for SQL Server 2022 `mcr.microsoft.com/mssql/server:2022-latest`.  In this service, we add an `extra_host` so that the SQL Server container can resolve the DNS name of our MinIO container so that it can make the proper TLS connection.  There is a data volume for our SQL Server data `sql-data`, and we're using a bind mount to expose the MinIO container's public certificate into SQL Server to that it's trusted using the code `./certs/public.crt:/usr/local/share/ca-certificates/mssql-ca-certificates/public.crt:ro`.  This location has changed in CTP 2.1, and I will update this post once the container is released.

```
  sql1:
    image: mcr.microsoft.com/mssql/server:2022-latest
    depends_on: 
      - config
      - createbucket
      - minio1
    hostname: sql1
    networks:
      - s3-data
    extra_hosts:
      - "s3.example.com:172.18.0.20"
    ports:
      - 1433:1433
    volumes:
      - sql-data:/var/opt/mssql
      - ./certs/public.crt:/usr/local/share/ca-certificates/mssql-ca-certificates/public.crt:ro
    environment:
      - ACCEPT_EULA=Y
      - MSSQL_SA_PASSWORD=S0methingS@Str0ng!
```

Once the containers are up and running, you'll want to create a database, create a credential for access to your s3 bucket in MinIO, then run a backup.  Here's some example code for that using `sqlcmd`.

```
#Create a database in SQL Server
CREATE DATABASE TESTDB1


#Create the S3 credential in SQL Server
CREATE CREDENTIAL [s3://s3.example.com:9000/sqlbackups] WITH IDENTITY = 'S3 Access Key', SECRET = 'anthony:nocentino'


#Run the backup to the s3 target
BACKUP DATABASE TestDB1 TO URL = 's3://s3.example.com:9000/sqlbackups/TestDB1.bak' WITH COMPRESSION, STATS = 10, FORMAT, INIT
```

When you're all finished, you can use `docker-compose down --rmi local --volumes` to stop all the containers and destroy all the images and volumes associated with this environment.


## Polybase and s3 Data Virtualization Environment

Second, in this repo's `polybase` directory, there's a script `demo.sh`.  This script has the commands you'll need to start up the environment and do a basic connectivity test using Polybase-based access to s3-compatible object storage.  To start everything up, you'll change into the `polybase` directory and run `docker-compose up --build --detach`.  This docker-compose manifest will do a few things...let's walk through that.

This docker-compose manifest starts the same as the backup one above.  It creates the certificate needed, starts a configured MinIO container, and then creates the required user and bucket in MinIO.  It also copies a simple CSV file into the MinIO container.  This is the data we'll access from SQL Server via Polybase over s3. 

Since Polybase isn't enabled in the published container image `mcr.microsoft.com/mssql/server:2022-latest`, we have to build a container image for SQL Server with Polybase installed.  And that's what we're doing in the `sql1` service in the dockerfile named `dockerfile.sql`.

### Start up the environment

Once you're ready to go, start up the environment with `docker-compose up --build --detach` and follow the steps in `demo.sh`

With the SQL Server container up and running, let's walk through the steps to access data on s3 compatible object storage. All this code is in `demo.sql` in the repo. But I want to walk you through it here too. 

### Configure Polybase in SQL Server instance 

Confirm if the Polybase feature is installed, 1 = installed

```
SELECT SERVERPROPERTY ('IsPolyBaseInstalled') AS IsPolyBaseInstalled;
```

Next, enable Polybase in your instance's configuration
```
exec sp_configure @configname = 'polybase enabled', @configvalue = 1;
```

Confirm if Polybase is in your running config, run_value should be 1
```
exec sp_configure @configname = 'polybase enabled'
```

### Configure access to external data using Polybase over S3

Create a database to hold objects for the demo
CREATE DATABASE [PolybaseDemo];


Switch into the database context for the PolybaseDemo database
```
USE PolybaseDemo
```

Create a database master key, this is use to protect the credentials you're about to create
```
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'S0methingS@Str0ng!';  
```

Create a database scoped credential, this should have at minimum ReadOnly and ListBucket access to the s3 bucket
```
CREATE DATABASE SCOPED CREDENTIAL s3_dc WITH IDENTITY = 'S3 Access Key', SECRET = 'anthony:nocentino' ;
```

Before you create the external data source, you need to restart the sql server container. 

If you don't you'll get this error:
```
Msg 46530, Level 16, State 11, Line 1
External data sources are not supported with type GENERIC.
```
To restart your SQL Server container started by docker-compose you can use this:
```
docker-compose restart sql1
```

Create your external datasource on your s3 compatible object storage, referencing where it is on the network (LOCATION), and the credential you just defined

```
CREATE EXTERNAL DATA SOURCE s3_ds
WITH
(   LOCATION = 's3://s3.example.com:9000/'
,   CREDENTIAL = s3_dc
)
```

First, we can access data in the s3 bucket and for a simple test, let's start with CSV.  During the docker compose up, the build copied a CSV into the bucket it created.  This should output `Hello World!`
```
SELECT  * 
FROM    OPENROWSET
        (   BULK '/sqldatavirt/helloworld.csv'
        ,   FORMAT       = 'CSV'
        ,   DATA_SOURCE  = 's3_ds'
        ) 
WITH    ( c1 varchar(50) )             
AS [Test1]
```

`OPENROWSET` is cool for infrequent access, but if you want to layer on sql server security or use statistics on the data in the external data source,
 let's create an external table.  This first requires defining an external file format.  In this example, its CSV

```
CREATE EXTERNAL FILE FORMAT CSVFileFormat
WITH
(   FORMAT_TYPE = DELIMITEDTEXT
,   FORMAT_OPTIONS  (    FIELD_TERMINATOR = ','
                    ,    STRING_DELIMITER = '"'
                    ,    FIRST_ROW = 1 )
);
```

Next, we define the table's structure.  The CSV here is mega simple, just a single row with a single column When defining the external table where the data lives on our network with `DATA_SOURCE`, the `LOCATION` within that `DATA_SOURCE` and the `FILE_FORMAT`
```
CREATE EXTERNAL TABLE HelloWorld ( c1 varchar(50) )
WITH (DATA_SOURCE = s3_ds, LOCATION = '/sqldatavirt/helloworld.csv',  FILE_FORMAT = CSVFileFormat);
```

Now we can access the data just like any other table in SQL server. 
```
SELECT * FROM [HelloWorld];
```

## A note about Polybase using containers with default settings

```
2022-08-13 13:09:43.22 spid41s     There is insufficient system memory in resource pool 'internal' to run this query.
```

Changed default memory resources from 2GB to 4GB

When you're done, you can use `docker-compose down --volumes  --rmi local` to clean up all the resources, images, network, and the volumes holding the database in the databases and MinIO.