#Start up our environment with docker compose. This can take a second for SQL Server to come online.
cd ./backup
docker-compose up --detach

#Create a database in SQL Server
QUERY=$(echo "CREATE DATABASE TESTDB1;")
sqlcmd -S localhost,1433 -U sa -Q $QUERY -P 'S0methingS@Str0ng!'


#Create the S3 credential in SQL Server
QUERY=$(echo "CREATE CREDENTIAL [s3://s3.example.com:9000/sqlbackups] WITH IDENTITY = 'S3 Access Key', SECRET = 'anthony:nocentino';")
sqlcmd -S localhost,1433 -U sa -Q $QUERY -P 'S0methingS@Str0ng!'


#Run the backup to the s3 target
QUERY=$(echo "BACKUP DATABASE TestDB1 TO URL = 's3://s3.example.com:9000/sqlbackups/TestDB1.bak' WITH COMPRESSION, STATS = 10, FORMAT, INIT")
sqlcmd -S localhost,1433 -U sa -Q $QUERY -P 'S0methingS@Str0ng!'

##Remove the images we built and also the volumes we created. 
docker-compose down --rmi local --volumes
rm -rf ./certs