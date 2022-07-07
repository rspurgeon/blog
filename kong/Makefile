CURRENT_WORKING_DIR=$(shell pwd)

KONG_VERSION ?= 2.8.1
KONG_EE_VERSION ?= ${KONG_VERSION}.1
SYNC ?= false

destroy-kong: kong-destroy
kong-destroy:
	@-docker rm -f kong-gateway > /dev/null 2>&1
	@-docker rm -f kong-database > /dev/null 2>&1
	@-docker network rm kong-net > /dev/null 2>&1

kong-init:
	@-docker network create kong-net > /dev/null 2>&1

wait-for-db:
	@while ! docker exec kong-database pg_isready 2>/dev/null; do echo waiting for db; sleep 1; done

wait-for-kong:
	@while ! docker exec kong-gateway kong health 2>/dev/null; do echo waiting for kong; sleep 2; done

kong-db: kong-init
	@-docker run -d --name kong-database --network=kong-net -p 5432:5432 -e "POSTGRES_USER=kong" -e "POSTGRES_DB=kong" -e "POSTGRES_PASSWORD=kong" postgres:9.6
	@-make wait-for-db
	@-sleep 1 # not sure why but this 1 second seems required to allow the socket to fully open and db to be ready

kong: kong-oss
kong-ce: kong-oss
kong-oss: kong-destroy kong-db
	@docker run --rm --network=kong-net -e "KONG_DATABASE=postgres" -e "KONG_PG_HOST=kong-database" -e "KONG_PG_USER=kong" -e "KONG_PG_PASSWORD=kong" -e "KONG_CASSANDRA_CONTACT_POINTS=kong-database" kong:latest kong migrations bootstrap
	@docker run -d --name kong-gateway --network=kong-net -e "KONG_DATABASE=postgres" -e "KONG_PG_HOST=kong-database" -e "KONG_PG_USER=kong" -e "KONG_PG_PASSWORD=kong" -e "KONG_CASSANDRA_CONTACT_POINTS=kong-database" -e "KONG_PROXY_ACCESS_LOG=/dev/stdout" -e "KONG_ADMIN_ACCESS_LOG=/dev/stdout" -e "KONG_PROXY_ERROR_LOG=/dev/stderr" -e "KONG_ADMIN_ERROR_LOG=/dev/stderr" -e "KONG_ADMIN_LISTEN=0.0.0.0:8001, 0.0.0.0:8444 ssl" -p 8000:8000 -p 8443:8443 -p 127.0.0.1:8001:8001 -p 127.0.0.1:8444:8444 kong:${KONG_VERSION}
	@make wait-for-kong

kong-free: kong-destroy kong-db
	@docker run --rm --network=kong-net -e "KONG_DATABASE=postgres" -e "KONG_PG_HOST=kong-database" -e "KONG_PG_PASSWORD=kong" -e "KONG_PASSWORD=test" kong/kong-gateway:2.8.1.1-alpine kong migrations bootstrap
	@docker run -d --name kong-gateway --network=kong-net -e "KONG_DATABASE=postgres" -e "KONG_PG_HOST=kong-database" -e "KONG_PG_USER=kong" -e "KONG_PG_PASSWORD=kong" -e "KONG_PROXY_ACCESS_LOG=/dev/stdout" -e "KONG_ADMIN_ACCESS_LOG=/dev/stdout" -e "KONG_PROXY_ERROR_LOG=/dev/stderr" -e "KONG_ADMIN_ERROR_LOG=/dev/stderr" -e "KONG_ADMIN_LISTEN=0.0.0.0:8001" -e "KONG_ADMIN_GUI_URL=http://localhost:8002" -p 8000:8000 -p 8443:8443 -p 8001:8001 -p 8444:8444 -p 8002:8002 -p 8445:8445 -p 8003:8003 -p 8004:8004 kong/kong-gateway:${KONG_EE_VERSION}-alpine
	@make wait-for-kong

kong-ee: kong-destroy kong-db
ifndef KONG_LICENSE_FILE
$(error KONG_LICENSE_FILE is not set)
endif
	@docker run --rm --network=kong-net -e "KONG_DATABASE=postgres" -e "KONG_PG_HOST=kong-database" -e "KONG_PG_PASSWORD=kong" -e "KONG_PASSWORD=test" kong/kong-gateway:2.8.1.1-alpine kong migrations bootstrap
	@KONG_LICENSE_DATA='$(shell cat ${KONG_LICENSE_FILE})' docker run -d --name kong-gateway --network=kong-net -e "KONG_DATABASE=postgres" -e "KONG_PG_HOST=kong-database" -e "KONG_PG_USER=kong" -e "KONG_PG_PASSWORD=kong" -e "KONG_PROXY_ACCESS_LOG=/dev/stdout" -e "KONG_ADMIN_ACCESS_LOG=/dev/stdout" -e "KONG_PROXY_ERROR_LOG=/dev/stderr" -e "KONG_ADMIN_ERROR_LOG=/dev/stderr" -e "KONG_ADMIN_LISTEN=0.0.0.0:8001" -e "KONG_ADMIN_GUI_URL=http://localhost:8002" -e KONG_LICENSE_DATA -p 8000:8000 -p 8443:8443 -p 8001:8001 -p 8444:8444 -p 8002:8002 -p 8445:8445 -p 8003:8003 -p 8004:8004 kong/kong-gateway:${KONG_EE_VERSION}-alpine 
	@make wait-for-kong

