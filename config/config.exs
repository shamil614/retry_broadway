use Mix.Config

config :retry_broadway, :rabbit_config,
  port: 5672,
  host: "localhost",
  username: "guest",
  password: "guest"

config :retry_broadway, RetryBroadway.Processors.RetryProcessor,
  max_retries: 4,
  initial_delay_interval: 200

# silence noisy AMQP logs
:logger.add_primary_filter(
  :ignore_rabbitmq_progress_reports,
  {&:logger_filters.domain/2, {:stop, :equal, [:progress]}}
)
