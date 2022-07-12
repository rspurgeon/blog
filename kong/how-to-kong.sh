#!/bin/sh

KONG_IMAGE_NAME="kong"
KONG_IMAGE_TAG="${KONG_IMAGE_TAG:-2.8.1}"
POSTGRES_IMAGE_NAME="postgres"
POSTGRES_IMAGE_TAG="9.6"

LOG_FILE="${LOG_FILE:-how-to-kong.log}"

echo_fail() {
	printf "\e[31m✘ \033\e[0m$@\n"
}

echo_pass() {
	printf "\e[32m✔ \033\e[0m$@\n"
}

retry() {
    local -r -i max_wait="$1"; shift
    local -r cmd="$@"

    local -i sleep_interval=2
    local -i curr_wait=0

    until $cmd
    do
        if (( curr_wait >= max_wait ))
        then
            echo "ERROR: Command '${cmd}' failed after $curr_wait seconds."
            return 1
        else
            curr_wait=$((curr_wait+sleep_interval))
            sleep $sleep_interval
        fi
    done
}

ensure_docker() {
  {
    docker ps -q > /dev/null 2>&1
  } || {
    return 1
  }
}
docker_pull_images() {
  echo ">docker_pull_images" >> $LOG_FILE
  echo Downloading Docker images
  docker pull ${POSTGRES_IMAGE_NAME}:${POSTGRES_IMAGE_TAG} >> $LOG_FILE 2>&1 && docker pull ${KONG_IMAGE_NAME}:${KONG_IMAGE_TAG} >> $LOG_FILE 2>&1 && echo_pass "Images ready"
  local rv=$?
  echo "<docker_pull_images" >> $LOG_FILE
  return $rv
}

destroy_kong() {
  echo ">destroy_kong" >> $LOG_FILE
  echo Destroying previous how-to-kong containers
  docker rm -f how-to-kong-gateway >> $LOG_FILE 2>&1
  docker rm -f how-to-kong-database >> $LOG_FILE 2>&1
  docker network rm how-to-kong-net >> $LOG_FILE 2>&1
  echo "<destroy_kong" >> $LOG_FILE
}

init() {
  echo ">init" >> $LOG_FILE
  docker network create how-to-kong-net >> $LOG_FILE 2>&1 
  local rv=$?
  echo "<init" >> $LOG_FILE
  return $rv
}

wait_for_db() {
  echo ">wait_for_db" >> $LOG_FILE 
  local rv=0
  retry 30 docker exec how-to-kong-database pg_isready >> $LOG_FILE 2>&1 && echo_pass "Database is ready" || rv=$? 
  echo "<wait_for_db" >> $LOG_FILE 
  return $rv
}

wait_for_kong() {
  echo ">wait_for_kong" >> $LOG_FILE
  local rv=0
  retry 30 docker exec how-to-kong-gateway kong health >> $LOG_FILE 2>&1 && echo_pass "Kong is healthy" || rv=$? 
  echo "<wait_for_kong" >> $LOG_FILE
}

init_db() {
  echo ">init_db" >> $LOG_FILE
  local rv=0
  docker run --rm --network=how-to-kong-net -e "KONG_DATABASE=postgres" -e "KONG_PG_HOST=how-to-kong-database" -e "KONG_PG_USER=kong" -e "KONG_PG_PASSWORD=kong" -e "KONG_CASSANDRA_CONTACT_POINTS=how-to-kong-database" ${KONG_IMAGE_NAME}:${KONG_IMAGE_TAG} kong migrations bootstrap >> $LOG_FILE 2>&1
  rv=$?
  echo "<init_db" >> $LOG_FILE
  return $rv
}

db() {
  echo ">db" >> $LOG_FILE
  echo Starting database
  # not certain why, but the 1 second sleep seems required to allow the socket to fully open and db to be ready
  docker run -d --name how-to-kong-database --network=how-to-kong-net -p 5432:5432 -e "POSTGRES_USER=kong" -e "POSTGRES_DB=kong" -e "POSTGRES_PASSWORD=kong" ${POSTGRES_IMAGE_NAME}:${POSTGRES_IMAGE_TAG} >> $LOG_FILE 2>&1 && wait_for_db && sleep 1 && init_db
  local rv=$?
  echo "<db" >> $LOG_FILE
  return $rv
}

kong() {
  echo ">kong" >> $LOG_FILE
  echo Starting Kong
  docker run -d --name how-to-kong-gateway --network=how-to-kong-net -e "KONG_DATABASE=postgres" -e "KONG_PG_HOST=how-to-kong-database" -e "KONG_PG_USER=kong" -e "KONG_PG_PASSWORD=kong" -e "KONG_CASSANDRA_CONTACT_POINTS=how-to-kong-database" -e "KONG_PROXY_ACCESS_LOG=/dev/stdout" -e "KONG_ADMIN_ACCESS_LOG=/dev/stdout" -e "KONG_PROXY_ERROR_LOG=/dev/stderr" -e "KONG_ADMIN_ERROR_LOG=/dev/stderr" -e "KONG_ADMIN_LISTEN=0.0.0.0:8001, 0.0.0.0:8444 ssl" -P ${KONG_IMAGE_NAME}:${KONG_IMAGE_TAG} >> $LOG_FILE 2>&1 && wait_for_kong && sleep 2
  local rv=$?
  echo "<kong" >> $LOG_FILE
  return $rv
}

get_kong_dataplane_port() {
  local endpoint=$(docker port how-to-kong-gateway 8000/tcp)
  local arrIN=(${endpoint//:/ })
  echo ${arrIN[1]}           
}
get_kong_controlplane_port() {
  local endpoint=$(docker port how-to-kong-gateway 8001/tcp)
  local arrIN=(${endpoint//:/ })
  echo ${arrIN[1]}           
}

mock_service() {
  echo ">mock_service" >> $LOG_FILE
  echo "Adding mock service at path /mock"
  curl -i -X POST $CTRL_PLANE_ENDPOINT/services --data name=mock --data url='http://mockbin.org' >> $LOG_FILE 2>&1
  curl -i -X POST $CTRL_PLANE_ENDPOINT/services/mock/routes --data 'paths[]=/mock' --data name=mocking > $LOG_FILE 2>&1
  echo "<mock_service" >> $LOG_FILE
}

validate_kong() {
  echo ">validate_kong" >> $LOG_FILE
  curl -i $CTRL_PLANE_ENDPOINT >> /dev/null 2>&1 && echo_pass "Kong admin API is up" || echo "Issues connecting to Kong, check $LOG_FILE"
  echo "<validate_kong" >> $LOG_FILE
}

main() {

  echo ">main" >> $LOG_FILE
  echo "Prepare to Kong"
  echo "Debugging info logged to '$LOG_FILE'"

  ensure_docker || { 
    echo "Docker is not available, check $LOG_FILE"; exit 1 
  }

  docker_pull_images || { 
    echo "Download failed, check $LOG_FILE"; exit 1 
  }
  
  destroy_kong

  init || {
    echo "Initalization steps failed, check $LOG_FILE"; exit 1
  }

  db || {
    echo "DB initialization failure, check $LOG_FILE"; exit 1
  }

  kong || {
    echo "Kong initialization failure, check $LOG_FILE"; exit 1
  }

	DATA_PLANE_ENDPOINT=localhost:$(get_kong_dataplane_port)
	CTRL_PLANE_ENDPOINT=localhost:$(get_kong_controlplane_port)

  validate_kong

  mock_service

	echo
	echo_pass "Kong is ready!"
	echo
	echo "Kong Data Plane endpoint    : $DATA_PLANE_ENDPOINT"
	echo "Kong Control Plane endpoint : $CTRL_PLANE_ENDPOINT"
	echo
	echo "Try using curl to interact with your new Kong Gateway, for example:"
  echo "    curl -s http://$DATA_PLANE_ENDPOINT/mock/requests"
  echo
	echo "To administer the gateway, use the Admin API:"
	echo "    curl -s http://$CTRL_PLANE_ENDPOINT/"
  echo
  echo "To stop the gateway and database, run:"
  echo "    docker rm -f how-to-kong-gateway && docker rm -f how-to-kong-database && docker network rm how-to-kong-net"
  echo "<main" >> $LOG_FILE
}

main "$@"
