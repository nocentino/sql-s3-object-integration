# sql-s3-object-integration

This repository provides two example environments for using SQL Server's S3 object integration: one for [backup and restore](#backup-and-restore-test-environment) to S3-compatible object storage, and another for [data virtualization](#polybase-and-s3-data-virtualization-environment) using PolyBase connectivity to S3-compatible object storage. Both environments are implemented using Docker Compose for easy setup and teardown.

## What's New

- **Updated for SQL Server 2025 RC1 and Ubuntu 24.04**: The data virtualization environment now uses the latest SQL Server container image, upgraded from the previous example using SQL Server 2022.
- **No PolyBase Installation Required for Parquet/S3**: New to SQL Server 2025, you no longer need to install the PolyBase service to interact with Parquet files in S3. Previously, with SQL Server 2022, you had to build a custom container or manually install the PolyBase service to enable this functionality.
- **Improved Certificate Handling**: The `config` service now generates SSL certificates before other services start, ensuring proper sequencing and avoiding mount errors.
- **PolyBase Configuration**: The demo SQL script now enables PolyBase and advanced options at the start, following best practices.
- **Consistent Naming**: Service and file names have been updated for clarity and consistency.

---

## Backup and Restore Test Environment

In the [`backup`](./backup) directory, you'll find a script [`demo.sh`](./backup/demo.sh) to start the environment and perform a basic connectivity test using SQL Server backup. To start everything up, change into the [`backup`](./backup) directory and run:

```
docker compose up --detach
```

### How it Works

1. **Certificate Generation**:  
   The `config` service builds a container that generates the required SSL certificate and stores it in `./certs` on the host.

2. **MinIO Service**:  
   The `minio1` service starts a MinIO container, exposing ports 9000 (data) and 9001 (admin). It mounts the generated certificates for TLS.

3. **Bucket Creation**:  
   The `createbucket` service uses the MinIO client (`mc`) to create a user and a bucket (`sqlbackups`) for backup/restore testing.

4. **SQL Server Service**:  
   The `sql1` service runs SQL Server, mounting the MinIO public certificate for trusted TLS connections.

### Example Usage

Create a database:
```
CREATE DATABASE TESTDB1;
```

Create the S3 credential:
```
CREATE CREDENTIAL [s3://s3.example.com:9000/sqlbackups] WITH IDENTITY = 'S3 Access Key', SECRET = 'anthony:nocentino';
```

Backup to S3:
```
BACKUP DATABASE TestDB1 TO URL = 's3://s3.example.com:9000/sqlbackups/TestDB1.bak' WITH COMPRESSION, STATS = 10, FORMAT, INIT;
```

Cleanup:
```
docker compose down --rmi local --volumes
```

---

## PolyBase and S3 Data Virtualization Environment

In the [`datavirtualization`](./datavirtualization) directory, you'll find a script [`demo.sh`](./datavirtualization/demo.sh) and a demo SQL script [`demo.sql`](./datavirtualization/demo.sql) for PolyBase-based access to S3-compatible object storage.

### How it Works

1. **Certificate Generation**:  
   The `config` service generates SSL certificates and places them in `./certs`.

2. **MinIO Service**:  
   The `s3.example.com` service starts MinIO with the generated certificates.

3. **Bucket and Data Setup**:  
   The `createbucket` service creates a user, a bucket (`sqldatavirt`), and uploads a sample CSV file.

4. **SQL Server Service**:  
   The `sql1` service runs SQL Server 2025 RC1, mounting the MinIO public certificate for TLS.

### PolyBase Configuration

Before creating external data sources, PolyBase must be enabled. The [`demo.sql`](./datavirtualization/demo.sql) script now includes:

```sql
USE master;
GO
sp_configure 'show advanced options', 1;
RECONFIGURE;
sp_configure 'polybase enabled', 1;
RECONFIGURE;
GO
```

> **Note:**  
> **SQL Server 2025 makes PolyBase easier than ever:**  
> You no longer need to install the PolyBase service to interact with Parquet files in S3. This is a major improvement over SQL Server 2022, where you had to build a custom container or manually install PolyBase to enable this functionality.

### Example Usage

- Create a database and master key
- Create a database scoped credential for S3 access
- Create an external data source referencing your S3 bucket
- Use `OPENROWSET` or create external tables to query data in S3

See [`demo.sql`](./datavirtualization/demo.sql) for the full workflow.

### Memory Requirements

If you encounter memory errors with PolyBase, increase Docker's memory allocation to at least 4GB.

---

## Cleanup

To stop and remove all containers, images, and volumes:

```
docker compose down --rmi local --volumes
```

---

## References

- [Setting up MinIO for SQL Server S3 Object Storage Integration](https://www.nocentino.com/posts/2022-06-10-setting-up-minio-for-sqlserver-object-storage/)
- [PolyBase and S3 Data Virtualization Example](https://github.com/nocentino/sql-s3-object-integration/tree/main/datavirtualization)
