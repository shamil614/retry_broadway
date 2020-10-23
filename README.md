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
6. Start rabbitmq with the [delayed message exchange](https://github.com/rabbitmq/rabbitmq-delayed-message-exchange) 
plugin via `docker-compose up`.
7. Setup the rabbitmq topology (exchanges and queues) with `mix setup`
8. Run the demo code with `mix users_demo` or `mix jobs_demo`

