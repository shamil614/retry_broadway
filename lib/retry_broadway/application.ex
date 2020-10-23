defmodule RetryBroadway.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      RetryBroadway.Processors.RetryProcessor,
      RetryBroadway.Processors.JobsProcessor,
      RetryBroadway.Processors.UsersProcessor
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RetryBroadway.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
