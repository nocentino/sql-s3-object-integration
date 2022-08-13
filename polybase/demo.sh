#Start up our environment with docker compose. This can take a second for SQL Server to come online.
cd ./polybase
docker-compose up --build 


##Jump over to demo.sql and run the code there. 


##Remove the images we built and also the volumes we created. 
docker-compose down --rmi local --volumes
rm -rf ./certs
