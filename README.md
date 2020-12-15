# RetryBroadway

**Demonstrate how to retry messages with Rabbitmq and Elixir Broadway.**

## Setup

1. Clone the repo `git clone git@github.com:shamil614/retry_broadway.git`
2. Change directory to project root `cd retry_broadway`
3. Make sure hex is installed `mix local.hex`
4. Get deps `mix deps.get`
5. Docker is the easiest way to install and run a configured version of Rabbitmq.
Docker Compose makes it even easier. 
[Install docker compose](https://docs.docker.com/compose/install/)
6. Download the `.ez` file for the [delayed message exchange plugin for RabbitMQ](https://github.com/rabbitmq/rabbitmq-delayed-message-exchange/releases/tag/v3.8.0) into this folder
7. Start rabbitmq from this folder with `docker-compose up`.
8. Setup the rabbitmq topology (exchanges and queues) with `mix setup`
9. Run the demo code with `mix users_demo` or `mix jobs_demo`

