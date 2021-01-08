defmodule RetryBroadway.Processors.JobsProcessor do
  @moduledoc """
  Demo pipeline for processing job data.
  """
  use Broadway

  require Logger

  alias Broadway.Message
  alias RetryBroadway.Topology

  def start_link(_opts) do
    {:ok, config} = RetryBroadway.rabbitmq_config()
    queue = Topology.jobs_queue()

    {:ok, _pid} =
      Broadway.start_link(__MODULE__,
        name: JobsProcessor,
        producer: [
          module:
            {BroadwayRabbitMQ.Producer,
             on_failure: :reject,
             metadata: [:routing_key, :headers],
             queue: queue,
             connection: config,
             qos: [
               prefetch_count: 1
             ]},
          concurrency: 2
        ],
        processors: [
          default: [
            concurrency: 1
          ]
        ]
      )
  end

  @impl true
  def handle_message(_, %Message{data: data} = message, _) do
    cond do
      data == "9" ->
        Logger.warn("Failing Jobs data with a value of 9")
        # fake a failure where the message is routed to the dlx (retry queue)
        # message is marked as failed. must return failed message.
        # this Broadway pipeline is configured to use AMQP.Basic.reject() for a failed message.
        # https://github.com/dashbitco/broadway_rabbitmq/blob/abeee81bbfdd7b562dbd5846cc1e63c9632c5180/lib/broadway_rabbitmq/producer.ex#L442
        # See `:on_failure` above
        Message.failed(message, "Faking a failure. Effectively AMQP.Basic.reject()")

      data == "100" ->
        IO.puts("Passing retry of Jobs data with a value of #{data} ")
        # retry pipeline process message but on retry changes the data to fake a passing retry
        message

      true ->
        # message processed successfully
        # this is where the message is processed more, or batched, or published to a
        # results / completed queue
        IO.puts("Passing Jobs data with a value of #{data} ")
        message
    end
  end
end
