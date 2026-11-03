# sg-ms-api-gateway

API Gateway microservice for School Guardian. Runs Kong in DB-less mode to route requests between frontend clients and backend microservices, applying CORS policies and JWT validation through the `sg-jwt` plugin.

## Getting Started

These instructions will give you a copy of the project up and running on your local machine for development and testing purposes. See deployment for notes on deploying the project on a live system.

### Prerequisites

Requirements for the software and other tools to build, test and push:

- Docker
- Docker Compose
- The `sg-services-network` Docker network (external, shared across services)

### Installing

A step by step series of examples that tell you how to get a development environment running.

Create the external network if it does not exist:

    docker network create sg-services-network

Start the gateway:

    docker compose up -d

Kong exposes the proxy on `127.0.0.1:8000` (loopback only for local debugging). The Admin API listens on `127.0.0.1:8001` inside the container. The declarative configuration is mounted from `./kong/kong.yml` and custom plugins from `./kong/plugins`.

## Running the tests

Explain how to run the automated tests for this system.

### Sample Tests

Tests are executed against the test service that runs in Docker Compose for each service.

### Style test

Checks if the best practices and the right coding style has been used, validated through the test service in Docker Compose.

## Deployment

Deployment is performed via GitHub Actions to an AWS EC2 instance.

## Built With

- Kong 3.9 — API Gateway (DB-less mode)
- Docker Compose — Local development stack

## Contributing

Please read [CONTRIBUTING.md](https://github.com/school-guardian-project/.github/blob/main/CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## License

This project is licensed under the SCHOOL GUARDIAN PROPRIETARY SOFTWARE LICENSE Version 1.0 — 2026. See the [LICENSE](LICENSE) file for details.
