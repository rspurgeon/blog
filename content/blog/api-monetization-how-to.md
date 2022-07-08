---
title: "API Monetization with Kong"
description: "A how-to guide for enabling monetization with Kong Gateway"
date: "2022-06-21"
author: Rick Spurgeon (rick.spurgeon@konghq.com)
tags:
- Kong
- How-to
notes:
- Some steps pulled from the Kong GW 
  Quickstart(https://docs.konghq.com/gateway/latest/get-started/quickstart/)
  but I've modified some of them slightly 
- The [kong-plugin-billable](https://github.com/Kong/kong-plugin-billable) 
  currently requires access as it's private repo.
- I'm not certain if a Kong license is required, but it's a step 
  I took that helped make it work.  I haven't isolated it's specific 
  requirement.
---

"API Monetization" can be viewed as an umbrella term for enabling business 
actions on your client's API utilization. These actions are often financial 
in nature, however, there are other possible benefits when building towards a 
monetization solution.

Common goals include: 

* Aim to capture revenue from a public API, where monetization is the 
process of productizing and metering APIs and billing customers for 
their usage.
* Supporting internal API clients, allocating 
budget or assigning costs appropriately based on usage.
* Develop a deeper understanding of your client's API usage trends 
using data analysis in order to better allocate future investments.

Regardless of the desired goal, monetization starts with the process of 
capturing actionable data on client API usage. This is referred to as 
'metering'. 

API usage metering can be enabled with the 
[Kong Billable Plugin](https://github.com/Kong/kong-plugin-billable), which 
aggregates client API requests and response statuses from your Kong
cluster across a variety of time frames. This data will serve as the 
API utilization source of truth to support monetization outcomes.

This document provides a how-to guide for enabling the Kong Billable Plugin 
and sourcing metering data from it.

## How-to

This guide walks through the following steps to setup and experiment 
with the Kong Billable Plugin:
* Run a new Kong GW locally using Docker
* Install, configure, and enable the Kong Billable Plugin
* Create mock services, clients, and secure routes for testing
* Extract metering data from the Gateway which can be used for monetization 
needs 

Let's get started.

### Run a new Kong GW locally using Docker

Create a local empty folder to work in.
```sh
mkdir -p monetization && cd monetization
```

Create an isolated Docker network for Kong Gateway and it's database
```sh
docker network create kong-net
```

Run a Postgres database for Kong 
```sh
docker run -d --name kong-database \
  --network=kong-net \
  -p 5432:5432 \
  -e "POSTGRES_USER=kong" \
  -e "POSTGRES_DB=kong" \
  -e "POSTGRES_PASSWORD=kong" \
  postgres:9.6
``` 

Run the initial database migrations for this version of Kong 
```sh
docker run --rm \
  --network=kong-net \
  -e "KONG_DATABASE=postgres" \
  -e "KONG_PG_HOST=kong-database" \
  -e "KONG_PG_USER=kong" \
  -e "KONG_PG_PASSWORD=kong" \
  -e "KONG_CASSANDRA_CONTACT_POINTS=kong-database" \
  kong/kong-gateway:2.8.1.1-alpine kong migrations bootstrap
```

Run the Kong gateway exposing various ports for usage on the host machine. 

> Note: The following command expects the environment variable 
> `KONG_LICENSE_FILE` to contain a valid path to a Kong license file. 
> This file is loaded into the environment variable `KONG_LICENSE_DATA` 
> prior to running the gateway and passed to it via environment variable.
```sh
KONG_LICENSE_DATA=$(cat $KONG_LICENSE_FILE) docker run -d --name kong-gateway \
  --network=kong-net -e "KONG_DATABASE=postgres" \
  -e "KONG_PG_HOST=kong-database" \
  -e "KONG_PG_USER=kong" \
  -e "KONG_PG_PASSWORD=kong"  \
  -e "KONG_PROXY_ACCESS_LOG=/dev/stdout" \
  -e "KONG_ADMIN_ACCESS_LOG=/dev/stdout" \
  -e "KONG_PROXY_ERROR_LOG=/dev/stderr" \
  -e "KONG_ADMIN_ERROR_LOG=/dev/stderr" \
  -e "KONG_ADMIN_LISTEN=0.0.0.0:8001" \
  -e "KONG_ADMIN_GUI_URL=http://localhost:8002" \
  -e KONG_LICENSE_DATA \
  -p 8000:8000 \
  -p 8443:8443 \
  -p 8001:8001 \
  -p 8444:8444 \
  -p 8002:8002 \
  -p 8445:8445 \
  -p 8003:8003 \
  -p 8004:8004 \
  kong/kong-gateway:2.8.1.1-alpine
```

Once Kong GW is initialized, you are able to query the Admin API.
```sh
curl localhost:8001
```

### Install, configure and enable the Kong Billable Plugin

Clone the Kong Billable Plugin source code repository locally. This 
repository contains Kong plugin code which enbles the metering of 
API usage on your Kong Gateway.
```sh
git clone https://github.com/Kong/kong-plugin-billable.git
```

Copy the billable plugin code files into the running gateway container.
```sh
docker cp kong-plugin-billable/kong/plugins/billable \
  kong-gateway:/usr/local/share/lua/5.1/kong/plugins/
```

The billable plugin uses persistence, which requires a database setup step. 
This command instructs Kong to run migrations including those defined in the 
billable plugin `migrations` source folder.
```sh
docker exec --user kong -e KONG_PLUGINS="bundled,billable" \
  kong-gateway kong migrations up -vv
```

You may notice log output similar to the following when the migrations 
run properly.
```sh
billable: 000_init
2022/06/22 14:02:47 [info] migrating billable on database 'kong'...
2022/06/22 14:02:47 [debug] running migration: 000_init
2022/06/22 14:02:47 [info] billable migrated up to: 000_init (executed)
2022/06/22 14:02:47 [info] 1 migration processed
2022/06/22 14:02:47 [info] 1 executed
```

Reload the gateway instructing it to load the `billable` plugin along 
with all it's `bundled` plugins.
```sh
docker exec --user kong -e KONG_PLUGINS="bundled,billable" \
  kong-gateway kong reload -vv
```

Enable the billable plugin on the running gateway.
```sh
curl http://localhost:8001/plugins -d name=billable
```

### Create mock services, clients, and secure routes

Create a service which routes traffic to the 
[MockBin](https://mockbin.org/) site which will assist in testing. 
```sh
curl -i -X POST \
  --url http://localhost:8001/services/ \
  --data 'name=mock' \
  --data 'url=http://mockbin.org'
```

Create a new route instructing Kong to route requests for the `/mock` path 
to the `mock` service
```sh
curl -i -X POST --url http://localhost:8001/services/mock/routes \
  --data 'paths[]=/mock' --data 'name=mock'
```

Secure the new route with the 
[Key Authentication](https://docs.konghq.com/hub/kong-inc/key-auth/) plugin.
Having authentication on the route enables the billable plugin to aggregate 
usage data by the identifer of the client.
```sh
curl -X POST http://localhost:8001/routes/mock/plugins \
  --data "name=key-auth"
```

The billable plugin requires 
[Consumers](https://docs.konghq.com/gateway/latest/admin-api/#consumer-object) 
to aggregate API usage. Create few different Consumers that you can use to 
generate sample traffic for.
```sh
curl -i -X POST --url http://localhost:8001/consumers/ --data "username=digit" 
curl -i -X POST --url http://localhost:8001/consumers/ --data "username=poppy" 
```

Create an authentication key for each Consumer (`key=<secret-value>`).
```sh
curl -i -X POST --url http://localhost:8001/consumers/poppy/key-auth/ \
  --data 'key=poppy-secret'
curl -i -X POST --url http://localhost:8001/consumers/digit/key-auth/ \
  --data 'key=digit-secret'
```

Generate some example traffic for each consumer. 
Repeat these commands randomly multiple times to simulate 
realistic API usage.
```sh
curl http://localhost:8000/mock/requests -H "apikey: poppy-secret"
curl http://localhost:8000/mock/requests -H "apikey: digit-secret"
```

### Extract metering data from the Gateay

View the metered usage.
```sh
curl -s http://localhost:8001/billable
```

> Tip: Use the [jq](https://stedolan.github.io/jq/) JSON command line 
> processor to work with responses from the gateway

Finally, generate a report from the billable plugin. This example shows
extracing montly usage in `csv` format and writing the data to a file
with the current date. This reporting feature can integratd with billing
providers, internal budgeting systems, or data analysis tools. For more
options see the 
[plugin API documentation](https://github.com/Kong/kong-plugin-billable#plugin-api).
```sh
curl -s "http://localhost:8001/billable?period=month&csv=true" \
  > mock-billing-data-$(date +"%m_%d_%Y").csv
```

## Summary

With the metering data in hand, futher business actions and insights can be 
developed. For more advanced out of the box solutions, seek out a 
[Kong Partner](https://konghq.com/partners/find-a-partner) that may provide
full featured monetization solutions.


