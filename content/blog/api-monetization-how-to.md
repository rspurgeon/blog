---
title: "API Monetization with Kong"
description: "A how-to guide for enabling monetization with Kong Gateway"
date: "2022-06-21"
author: Rick Spurgeon (rick.spurgeon@konghq.com)
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
action on API utilization by your clients. These actions are often financial 
in nature, however they can be useful for a variety of other use cases. 

Commonly, you may see the following desired business outcomes:

* You aim to capture revenue from a public API. Monetization is the process of 
productizing, metering, and billing for public API usage. 
* You support a set of APIs supporting internal clients and desire to allocate 
budget and cost appropriately based on usage.
* You want to understand your clients API usage trends with data analysis 

Regardless of the desired action, monetization starts with the process of 
capturing actionable data on client API usage, this is referred to as 
'Metering'. 

API usage metering can be enabled with the 
[Kong Billable Plugin](https://github.com/Kong/kong-plugin-billable) which 
aggregates client API requests and response statuses across your Kong
cluster for a variety of time frames. This will function as the source data
used to further develop your monetization needs. 

The remainder of the document provides a how-to guide for enabling the 
Kong Billable Plugin and pulling metering data from it.

### How-to

Create a local empty folder to work in.
```
mkdir monetization
```

Clone the Kong Billable Plugin source code repository locally. This contains 
code which you will install as a Kong plugin to enble the metering of 
API usage on your Kong Gateway.
```
git clone https://github.com/Kong/kong-plugin-billable.git
```

Create an isolated Docker network for Kong Gateway and it's database
```
docker network create kong-net
```

Run a Postgres database for Kong 
```
docker run -d --name kong-database \
  --network=kong-net \
  -p 5432:5432 \
  -e "POSTGRES_USER=kong" \
  -e "POSTGRES_DB=kong" \
  -e "POSTGRES_PASSWORD=kong" \
  postgres:9.6
``` 

Run the initial database migrations for this version of Kong 
```
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
This command loads a Kong license into the environment variable 
`KONG_LICENSE_DATA` which expects the license file path to be present in the 
`KONG_LICENSE_FILE` variable. 
```
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

Copy the billable plugin code files into the running container.
```
docker cp kong-plugin-billable/kong/plugins/billable \
  kong-gateway:/usr/local/share/lua/5.1/kong/plugins/
```

The billable plugin has persistence which requires database setup. This 
command instructs Kong to run migrations including those defined in the 
billable plugin `migrations` source folder.
```
docker exec --user kong -e KONG_PLUGINS="bundled,billable" \
  kong-gateway kong migrations up -vv
```

Reload the gateway instructing it to load the custom billable plugin along 
with all it's bundled plugins.
```
docker exec --user kong -e KONG_PLUGINS="bundled,billable" \
  kong-gateway kong reload -vv
```

Enable the billable plugin on the running gateway.
```
curl http://localhost:8001/plugins -d name=billable
```

Create an example service, which routes traffic to the 
[MockBin](https://mockbin.org/) site which will assist in testing. 
```
curl -i -X POST \
  --url http://localhost:8001/services/ \
  --data 'name=mock' \
  --data 'url=http://mockbin.org'
```

Create a route to the new service, specifying that the `/mock` path will 
be routed to the to the `mock` service
```
curl -i -X POST --url http://localhost:8001/services/mock/routes \
  --data 'paths[]=/mock' --data 'name=mock'
```

Secure the new route with the 
[Key Authentication](https://docs.konghq.com/hub/kong-inc/key-auth/) plugin.
```
curl -X POST http://localhost:8001/routes/mock/plugins \
  --data "name=key-auth"
```

The billable plugin requires consumers to aggregate API usage. Create few 
different consumers that you can use to generate sample traffic for.
```
curl -i -X POST --url http://localhost:8001/consumers/ --data "username=digit" 
curl -i -X POST --url http://localhost:8001/consumers/ --data "username=poppy" 
```

Create an authentication key for each Consumer:
```
curl -i -X POST --url http://localhost:8001/consumers/poppy/key-auth/ \ 
  --data 'key=poppy-secret'
curl -i -X POST --url http://localhost:8001/consumers/digit/key-auth/ \
  --data 'key=digit-secret'
```

Generate example traffic for each consumer. Repeat these commands multiple 
times and randomly to simulate realistic API usage.
```
curl http://localhost:8000/mock/requests -H "apikey: poppy-secret"
curl http://localhost:8000/mock/requests -H "apikey: digit-secret"
```

View the metered usage 
```
curl http://localhost:8001/billable | jq
```

Generate a report.
```
curl -s "http://localhost:8001/billable?period=month&csv=true" \
  > mock-billing-data-$(date +"%m_%d_%Y").csv
```

## Summary

With the data generated from the Billable Plugin, futher business actions 
and insights can be developed. 


