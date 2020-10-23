defmodule RetryBroadway.Processors.JobsProcessorTest do
  use ExUnit.Case
  #
  #  alias RetryBroadway.Topology
  #  alias AMQP.Queue
  #
  #  setup_all do
  #    Mix.Tasks.Setup.run()
  #  end
  #
  #  setup _ do
  #    with {:ok, config} <- RetryBroadway.rabbitmq_config(),
  #         {:ok, conn} <- AMQP.Connection.open(config),
  #         {:ok, chan} <- AMQP.Channel.open(conn) do
  #      Queue.purge(chan, Topology.retry_queue())
  #      Queue.purge(chan, Topology.jobs_queue())
  #
  #      on_exit(fn ->
  #        # close connection and the channel
  #        AMQP.Connection.close(conn)
  #      end)
  #    end
  #
  #    {:ok, %{chan: chan}}
  #  end
  #
  #  describe "handle_message/1" do
  #    test "messages with 9 in the data are retried and processed successfully", %{chan: chan} do
  #      start_supervised!(
  #        {RetryBroadway.Processors.JobsProcessor, [context: [callback: callback, send_to: self()]]}
  #      )
  #    end
  #  end
end
