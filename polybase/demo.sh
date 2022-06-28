#Start up our environment with docker compose. This can take a second for SQL Server to come online.
docker-compose up --build 

#Create the S3 credential in SQL Server
QUERY=$(echo "CREATE CREDENTIAL [s3://s3.example.com:9000/sqldatavirt] WITH IDENTITY = 'S3 Access Key', SECRET = 'anthony:nocentino';")
sqlcmd -S localhost,1433 -U sa -Q $QUERY -P 'S0methingS@Str0ng!'




##Remove the images we built and also the volumes we created. 
docker-compose down --rmi local --volumes
rm -rf ./certs
