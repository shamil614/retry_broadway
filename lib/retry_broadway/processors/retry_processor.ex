defmodule RetryBroadway.Processors.RetryProcessor do
  @moduledoc """
    Pipeline that checks the `retry` queue for messages to republish.
    The pipeline tries to republish until the `max_retries()` is reached.
    Also when republishing the message is sent to the main exchange (direct & delayed exchange) with a `x-delay` header.
    When the `x-delay` header (value is milliseconds) present the `delayed exchange` will wait to publish the message.
  """
  use Broadway
  require Logger

  @type message_headers() :: list({name :: String.t(), type :: atom, value :: term})
  @type retry_header_data() :: %{retry_count: non_neg_integer | nil, index: integer}

  @delay_header_name "x-delay"
  @retry_header "x-retries"

  alias Broadway.Message
  alias RetryBroadway.Topology

  def start_link(_opts) do
    {:ok, config} = RetryBroadway.rabbitmq_config()
    queue = Topology.retry_queue()

    {:ok, _pid} =
      Broadway.start_link(__MODULE__,
        name: RetryProcessor,
        producer: [
          module:
            {BroadwayRabbitMQ.Producer,
             on_failure: :reject,
             metadata: [:routing_key, :headers],
             queue: queue,
             connection: config,
             qos: [
               prefetch_count: 50
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
  def handle_message(
        _,
        %Message{data: data, metadata: %{headers: headers, routing_key: routing_key}} = message,
        _
      ) do
    retry_data = %{retry_count: retry_count, index: _index} = get_retry_count(headers)

    if (retry_count || 0) < max_retries() do
      {:ok, exchange} = find_exchange(headers)

      updated_headers =
        headers
        |> update_retry_count(retry_data)
        |> update_retry_delay()

      data = fake_retry_behaviour(data, retry_count)

      # note this is a basic means of connecting to Rabbitmq.
      # for production, it's best to pool and manage connections / channels
      with {:ok, config} <- RetryBroadway.rabbitmq_config(),
           {:ok, conn} <- AMQP.Connection.open(config),
           {:ok, chan} <- AMQP.Channel.open(conn) do
        # don't try to decode data. just republish as if the message was new
        AMQP.Basic.publish(chan, exchange, routing_key, data, headers: updated_headers)
        AMQP.Connection.close(conn)
      end

      message
    else
      Logger.error("Max retries reached! \n #{inspect(message)}")
      # message is marked as failed. must return failed message.
      Message.failed(message, "Message reached max retries of #{max_retries()}")
    end
  end

  @doc """
    Fake some behavior for demonstration purposes
  """
  @spec fake_retry_behaviour(data :: String.t(), retry_count :: non_neg_integer) :: String.t()
  def fake_retry_behaviour(data, retry_count) do
    cond do
      # fake that after 3 retries the message eventually passes
      # in this case the payload is modified so the JobProcessor won't fail the message
      data == "9" && retry_count == 3 -> "100"
      true -> data
    end
  end

  # Functions below are public for easy unit testing.

  @doc false
  @spec find_exchange(message_headers()) :: {:ok, String.t()} | {:error, :exchange_not_found}
  def find_exchange(headers) do
    # header set by rabbitmq when the message is rejected and routed to the dlx
    exchange = "x-first-death-exchange"

    Enum.find_value(headers, fn {name, _, value} ->
      if name == exchange do
        {:ok, value}
      end
    end)
  end

  @doc false
  @spec get_retry_count(message_headers()) :: retry_header_data()
  def get_retry_count(headers) do
    Enum.reduce_while(headers, %{retry_count: nil, index: -1}, fn {name, _type, value},
                                                                  %{index: index} = acc ->
      if name == @retry_header do
        acc =
          acc
          |> Map.put(:retry_count, value)
          |> Map.put(:index, index + 1)

        {:halt, acc}
      else
        acc = Map.put(acc, :index, index + 1)

        {:cont, acc}
      end
    end)
  end

  @doc false
  def initial_delay_interval do
    :retry_broadway
    |> Application.fetch_env!(__MODULE__)
    |> Keyword.fetch!(:initial_delay_interval)
  end

  @doc false
  @spec max_retries() :: non_neg_integer()
  def max_retries do
    :retry_broadway
    |> Application.fetch_env!(__MODULE__)
    |> Keyword.fetch!(:max_retries)
  end

  # missing retry header. headers needs retry to be set for the first time
  @doc false
  @spec update_retry_count(message_headers(), retry_header_data()) :: message_headers()
  def update_retry_count(headers, %{retry_count: nil, index: _}) do
    [{@retry_header, :long, 1} | headers]
  end

  def update_retry_count(headers, %{retry_count: retry_count, index: index}) do
    List.update_at(headers, index, fn {@retry_header, :long, ^retry_count} ->
      {@retry_header, :long, retry_count + 1}
    end)
  end

  @doc false
  @spec update_retry_delay(message_headers()) :: message_headers()
  def update_retry_delay(headers) do
    delay_index =
      Enum.find_index(headers, fn {name, _, _} ->
        name == @delay_header_name
      end)

    if delay_index == nil do
      IO.puts("First delay set to #{initial_delay_interval()} ms")
      [{@delay_header_name, :signedint, initial_delay_interval()} | headers]
    else
      List.update_at(headers, delay_index, fn {@delay_header_name, type, value} ->
        # after the delayed exchange processes the delayed message, the exchange negates the delayed value
        # the negation is how you can determine the message had been delayed before
        # must get absolute value then increase the delay by a multiple of 3.
        # Ex delay: 100 ms, 300 ms, 900 ms, 2.7 seconds, 8.1 seconds, etc.

        delay = abs(value) * 3
        IO.puts("Delay set to #{delay} ms")
        {@delay_header_name, type, delay}
      end)
    end
  end
end
