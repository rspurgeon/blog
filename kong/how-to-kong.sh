#!/bin/sh

KONG_VERSION="${KONG_VERSION:-2.8.1}"
KONG_EE_VERSION="$KONG_VERSION.1"
LOG_FILE="${LOG_FILE:-how-to-kong.log}"

destroy_kong() {
	echo ">destroy_kong" >> $LOG_FILE
	echo destroying previous how-to-kong containers
	docker rm -f how-to-kong-gateway >> $LOG_FILE 2>&1
	docker rm -f how-to-kong-database >> $LOG_FILE 2>&1
	docker network rm how-to-kong-net >> $LOG_FILE 2>&1
	echo "<destroy_kong" >> $LOG_FILE
}

init_kong() {
	echo ">init_kong" >> $LOG_FILE
	docker network create how-to-kong-net >> $LOG_FILE 2>&1 
	echo "<init_kong" >> $LOG_FILE
}

wait_for_db() {
	echo ">wait_for_db" >> $LOG_FILE 
	while ! docker exec how-to-kong-database pg_isready >> $LOG_FILE 2>&1; do echo waiting for database; sleep 1; done
	echo database is ready
	echo "<wait_for_db" >> $LOG_FILE 
}

wait_for_kong() {
	echo ">wait_for_kong" >> $LOG_FILE
	while ! docker exec how-to-kong-gateway kong health >> $LOG_FILE 2>&1; do echo waiting for kong; sleep 2; done
	echo kong is ready
	echo "<wait_for_kong" >> $LOG_FILE
}

db() {
	echo ">db" >> $LOG_FILE
	echo starting database
	docker run -d --name how-to-kong-database --network=how-to-kong-net -p 5432:5432 -e "POSTGRES_USER=kong" -e "POSTGRES_DB=kong" -e "POSTGRES_PASSWORD=kong" postgres:9.6 >> $LOG_FILE 2>&1
	wait_for_db
	sleep 1 # not certain why, but this 1 second seems required to allow the socket to fully open and db to be ready
	echo "<db" >> $LOG_FILE
}
init_db() {
	echo ">init_db" >> $LOG_FILE
	docker run --rm --network=how-to-kong-net -e "KONG_DATABASE=postgres" -e "KONG_PG_HOST=how-to-kong-database" -e "KONG_PG_USER=kong" -e "KONG_PG_PASSWORD=kong" -e "KONG_CASSANDRA_CONTACT_POINTS=how-to-kong-database" kong:latest kong migrations bootstrap >> $LOG_FILE 2>&1
	echo "<init_db" >> $LOG_FILE
}
kong() {
	echo ">kong" >> $LOG_FILE
	docker run -d --name how-to-kong-gateway --network=how-to-kong-net -e "KONG_DATABASE=postgres" -e "KONG_PG_HOST=how-to-kong-database" -e "KONG_PG_USER=kong" -e "KONG_PG_PASSWORD=kong" -e "KONG_CASSANDRA_CONTACT_POINTS=how-to-kong-database" -e "KONG_PROXY_ACCESS_LOG=/dev/stdout" -e "KONG_ADMIN_ACCESS_LOG=/dev/stdout" -e "KONG_PROXY_ERROR_LOG=/dev/stderr" -e "KONG_ADMIN_ERROR_LOG=/dev/stderr" -e "KONG_ADMIN_LISTEN=0.0.0.0:8001, 0.0.0.0:8444 ssl" -p 8000:8000 -p 8443:8443 -p 127.0.0.1:8001:8001 -p 127.0.0.1:8444:8444 kong:${KONG_VERSION} >> $LOG_FILE 2>&1
	echo "<kong" >> $LOG_FILE
}

mock_service() {
	echo ">mock_service" >> $LOG_FILE
	echo 'adding mock service at path /mock'
	curl -i -X POST http://localhost:8001/services --data name=mock --data url='http://mockbin.org' >> $LOG_FILE 2>&1
	curl -i -X POST http://localhost:8001/services/mock/routes --data 'paths[]=/mock' --data name=mocking > $LOG_FILE 2>&1
	echo "<mock_service" >> $LOG_FILE
}

validate_kong() {
	echo ">validate_kong" >> $LOG_FILE
	curl -i http://localhost:8001 >> /dev/null 2>&1 && echo "kong is up" || echo "issues starting kong"
	echo "<validate_kong" >> $LOG_FILE
}

main() {
	echo ">main" >> $LOG_FILE
	echo "Info logged to '$LOG_FILE'"
	destroy_kong
	init_kong
	db
	init_db
	kong
	wait_for_kong
	mock_service
	validate_kong
	echo "<main" >> $LOG_FILE
}

main "$@"
