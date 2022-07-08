# sql-s3-object-integration

In this repo, you'll find two example environments for working with SQL Server 2022's s3 object integration, one for backup and restore to s3 compatible object storage and the other for data virtualization using polybase connectivity to s3 compatible object storage.  Let's walk through what you'll get in each environment. 

## Backup and Restore Test Environment

First, in this repo's `backup` directory, there's a script `demo.sh`.  This has the commands you'll need to start up the environment and do a basic connectivity test using a SQL Server backup.  To start everything up, you'll change into the `backup` directory and run `docker-compose up --detach`.  This docker-compose manifest will do a few things...let's walk through that.

```
docker-compose up --detach
```

1.  First, since SQL Server's s3 object integration requires a valid and trusted certificate, so a service named `config` runs a container that creates the required certificate needed for this environment and stores them in the current working directory in a subdirectory named `certs` 

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

3.  Next, the `createbucket` service creates a user in MinIO that we will use inside SQL Server to access MinOIO and also creates a bucket named `sqlbackups` for our backup and restore testing.

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

1.  Finally, we start a service named `sql1`, which runs the latest published container image for SQL Server 2022 `mcr.microsoft.com/mssql/server:2022-latest`. In this service, we add an `extra_host` so that the SQL Server container can resolve the DNS name of our MinIO container so that it can make the proper TLS connection.  We also have a data volume for our SQL Server data `sql-data`, and we're using a bind mount to expose the MinIO container's public certificate into SQL Server to that it's trusted using the code `./certs/public.crt:/usr/local/share/ca-certificates/mssql-ca-certificates/public.crt:ro` 

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

Once you have the containers up and running, you'll want to create a database, create a credential for access to your s3 bucket in MinIO, then run a backup.  Here's some example code for that using `sqlcmd`.

```
#Create a database in SQL Server
QUERY=$(echo "CREATE DATABASE TESTDB1;")
sqlcmd -S localhost,1433 -U sa -Q $QUERY -P 'S0methingS@Str0ng!'


#Create the S3 credential in SQL Server
QUERY=$(echo "CREATE CREDENTIAL [s3://s3.example.com:9000/sqlbackups] WITH IDENTITY = 'S3 Access Key', SECRET = 'anthony:nocentino';")
sqlcmd -S localhost,1433 -U sa -Q $QUERY -P 'S0methingS@Str0ng!'


#Run the backup to the s3 target
QUERY=$(echo "BACKUP DATABASE TestDB1 TO URL = 's3://s3.example.com:9000/sqlbackups/TestDB1.bak' WITH COMPRESSION, STATS = 10, FORMAT, INIT")
sqlcmd -S localhost,1433 -U sa -Q $QUERY -P 'S0methingS@Str0ng!'
```

When you're all finished you can use `docker-compose down --rmi local --volumes` to stop all the containers and destory all the images and volumes associated with this environemnt.


## Polybase and s3 Data Virtualiation Enviroment

Second, in this repo's `polybase` directory, there's a script `demo.sh`.  This has the commands you'll need to start up the environment and do a basic connectivity test using a Polybase based access to s3-compatible object stroage.  To start everything up, you'll change into the `polybase` directory and run `docker-compose up --build --detach`.  This docker-compose manifest will do a few things...let's walk through that.

This docker-compose manifest starts off the same as the backup one above, it creats the certificate needed, it starts a configured MinIO container, and then creates the required user and bucked in MinIO. Since Polybase isn't enabled in the published container image `mcr.microsoft.com/mssql/server:2022-latest` we have to build a contianer image for SQL Server with Polybase installed. And that's what we're doing in the `sql1` service in the dockerfile named `dockerfile.sql`.



