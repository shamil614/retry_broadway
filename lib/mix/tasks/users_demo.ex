defmodule Mix.Tasks.UsersDemo do
  @moduledoc false

  use Mix.Task

  alias RetryBroadway.Topology
  alias AMQP.{Basic, Connection, Queue}

  @shortdoc "Demo jobs retry"
  def run(_) do
    Application.ensure_all_started(:retry_broadway)

    with {:ok, config} <- RetryBroadway.rabbitmq_config(),
         {:ok, conn} <- AMQP.Connection.open(config),
         {:ok, chan} <- AMQP.Channel.open(conn) do
      Queue.purge(chan, Topology.retry_queue())
      Queue.purge(chan, Topology.users_queue())

      main_exchange = Topology.main_exchange()
      routing_key = Topology.users_routing_key("updated")

      names = ~w(John Mark Allen Luke David Nathan Drew Sally Amy Sue Frank)

      Enum.each(names, fn int ->
        payload = to_string(int)
        :ok = Basic.publish(chan, main_exchange, routing_key, payload, mandatory: true)
      end)

      Process.sleep(10_000)
      # close connection and the channel
      Connection.close(conn)
    end
  end
end
