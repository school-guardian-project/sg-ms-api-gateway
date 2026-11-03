# sg-ms-api-gateway

API Gateway microservice for School Guardian, running Kong in DB-less mode to route and apply CORS policies between frontend clients and backend microservices.

## Getting Started

These instructions will give you a copy of the project up and running on your local machine for development and testing purposes. See deployment for notes on deploying the project on a live system.

### Prerequisites

Requirements for the software and other tools to build, test and push:

- Docker
- Docker Compose

### Installing

A step by step series of examples that tell you how to get a development environment running.

Start the service with Docker Compose:

    docker compose up -d

Kong runs in DB-less mode with `kong.yml` mounted by Docker Compose.

## Running the tests

Explain how to run the automated tests for this system.

### Sample Tests

Tests are executed against the test service that runs in Docker Compose for each service.

### Style test

Checks if the best practices and the right coding style has been used, validated through the test service in Docker Compose.

## Deployment

Deployment is performed via GitHub Actions to an AWS EC2 instance.

## Built With

- Kong — API Gateway
- Docker Compose — Local development stack

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## License

This project is licensed under the SCHOOL GUARDIAN PROPRIETARY SOFTWARE LICENSE Version 1.0 — 2026. See the [LICENSE](LICENSE) file for details.
