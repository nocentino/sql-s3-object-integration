# Start up our environment with docker compose. This can take a second for SQL Server to come online.
cd ./polybase
docker compose build
docker compose up --detach 

##Jump over to demo.sql and run the code there on your SQL Server instance.


# Remove the images we built and also the volumes we created. 
# docker compose down --rmi local --volumes
