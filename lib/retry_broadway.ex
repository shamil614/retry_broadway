defmodule RetryBroadway do
  @moduledoc """
  Demo application on how to do retries with Rabbitmq and Broadway.
  """

  @spec rabbitmq_config() :: {:ok, Application.value()} | :error
  def rabbitmq_config do
    Application.fetch_env(:retry_broadway, :rabbit_config)
  end
end
