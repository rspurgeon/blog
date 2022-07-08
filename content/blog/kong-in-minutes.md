---
title: "Kong Gateway in minutes"
description: "A how-to guide for quickly starting a Kong Gateway"
date: "2022-07-7"
weight: 1
author: Rick Spurgeon (rick.spurgeon@konghq.com)
tags:
- Kong
- How-to
notes:
- The purpose of this how-to is to help someone get
  a GW started ASAP, _not_ to help them understand the how or why
---

In order to explore the capabilities of [Kong Gatway](https://docs.konghq.com/gateway/latest/), 
you'll need one to experiment with. This guide helps you quickly deploy Kong 
using [Docker](https://docs.docker.com/get-started/overview/) which is the 
easiest way to get started. This guide's purpose is not to provide a production like deployment
or deep explanation, rather to simply get you a running gateway as fast as possible.

### Prerequisites

These instructions should be compatible on many systems, but have only been tested on the following system and shell:
- macOS 12.4
- zsh 5.8.1

This guide assumes each of the following tools are installed locally. 
* [Docker](https://docs.docker.com/get-docker/) is used to run Kong and the supporting database locally. This guide has been tested with version `20.10.17`.
* [`curl`](https://curl.se/) is used to send requests to the gateway. Most systems come with `curl` pre-installed.
* [`make`](https://www.gnu.org/software/make/) is used to run commands to deploy Kong and the supporting database to Docker. Most systems come with `make` pre-installed.

### Steps 

In order to get started quickly, you'll download a `Makefile` which contains 
commands to run Kong, it's supporting database, and an example service to work with.
Then we'll interact with the gateway to ensure it has been started properly.

Run each of the following commands in order.

Create and change into a folder to work out of:
```sh
mkdir -p kong && cd kong
```

Download the `Makefile`:
```sh
curl -L spurgeon.dev/make-kong --output Makefile
```

Run Kong:
```sh
make kong
```

Docker is now downloading and running the Kong Gateway and supporting database. Additionally,
the `Makefile` bootstraps the database and installs a [mock service](https://mockbin.org/) to experiment with.
Depending on your internet download speeds, this command should complete relatively quickly, and once you have the images cached locally, subsequent usage of this guide will complete much faster.

Once Kong is available, you will see:
```text
kong is up
```

Test the [Kong Admin API](https://docs.konghq.com/gateway/latest/admin-api/) 
on port `8001` with the following:
```sh
curl http://localhost:8001
```

You should see a large JSON reponse from the gateway.

Test that the gateway is proxying data by making a mock request on port `8000`:
```sh
curl http://localhost:8000/mock/requests
```

You should see a JSON response from the mock service with various information.
 
### What's next?

You now have a Kong gateway running locally. Kong has a tremendous amount of capabilities
to help you manage, configure and route requests to your APIs.

* Learn about modifying incoming JSON requests with no code by using the 
[request-transformer plugin](/blog/request-transformations).
* To follow a more detailed step-by-step guide to starting Kong, see the 
[Kong Getting Started guide](https://docs.konghq.com/gateway/latest/get-started/quickstart/).
* The [Admin API documentation](https://docs.konghq.com/gateway/latest/admin-api/) 
provides more details on managing a Kong Gateway.
