defmodule Mix.Tasks.Setup do
  @moduledoc false

  use Mix.Task

  import RetryBroadway.Topology

  @shortdoc "Setup queues and exchanges"
  def run(_) do
    IO.puts("Creating exchanges and queues!")

    # note this is a basic means of connecting to Rabbitmq.
    # for production, it's best to pool and manage connections / channels
    with {:ok, config} <- RetryBroadway.rabbitmq_config(),
         {:ok, conn} <- AMQP.Connection.open(config),
         {:ok, chan} <- AMQP.Channel.open(conn) do
      setup_rabbitmq(chan)

      # close connection and the channel
      AMQP.Connection.close(conn)

      IO.puts("Done!")
    end
  end

  defp setup_rabbitmq(chan) do
    # messages are delayed after being retried / republished
    :ok =
      AMQP.Exchange.declare(chan, main_exchange(), :"x-delayed-message",
        arguments: [{"x-delayed-type", :longstr, "topic"}],
        durable: true
      )

    # useful to split out the retry exchange from the main exchange
    # allows for setting the dlx (dead letter exchange) for any rejected messages
    :ok = AMQP.Exchange.declare(chan, retry_exchange(), :topic, durable: true)

    queues_topics = [
      {users_queue(), users_topic()},
      {jobs_queue(), jobs_topic()}
    ]

    # declare queues and explicitly set a dlx (dead letter exchange)
    queues_topics
    |> Enum.each(fn {queue, _topic} ->
      {:ok, _queue} =
        {:ok, _response} =
        AMQP.Queue.declare(chan, queue,
          arguments: [{"x-dead-letter-exchange", :longstr, retry_exchange()}],
          durable: true
        )
    end)

    {:ok, _response} = AMQP.Queue.declare(chan, retry_queue(), durable: true)

    # bind the queues to the exchanges by a topic (routing key)
    queues_topics
    |> Enum.each(fn {queue, topic} ->
      :ok = AMQP.Queue.bind(chan, queue, main_exchange(), routing_key: topic)
    end)

    # match any routing key of any length and route an message on the retry_exchange (dlx) to the retry queue
    :ok = AMQP.Queue.bind(chan, retry_queue(), retry_exchange(), routing_key: "#")
  end
end
