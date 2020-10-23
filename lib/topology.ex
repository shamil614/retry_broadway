defmodule RetryBroadway.Topology do
  @moduledoc """
  Source of truth for all the names of the various parts of the Rabbitmq topology.
  """

  @doc """
  Name of the queue the receives all jobs messages.
  """
  def jobs_queue, do: "jobs"

  @doc """
  Build a routing key off the jobs topic so messages are routed to the jobs queue.
  """
  def jobs_routing_key(subtopic) when is_binary(subtopic) do
    jobs_topic() |> String.replace("*", subtopic)
  end

  @doc """
  Jobs queue is bound to the topic.
  Routes messages to the jobs queue by matching on the topic and subtopic.
  For example a topic of `jobs.created` and `jobs.updated` will route to the jobs queue.
  """
  def jobs_topic, do: "jobs.*"

  @doc """
  Name of the default (primary) exchange.
  """
  def main_exchange, do: "main_exchange"

  @doc """
  Name of the exchange that routes messages for retry.
  """
  def retry_exchange, do: "retry_exchange"

  @doc """
  Name of the queue the receives all messages for retrying.
  """
  def retry_queue, do: "retry"

  @doc """
  Name of the queue the receives all user messages.
  """
  def users_queue, do: "users"

  @doc """
  Build a routing key off the users topic so messages are routed to the users queue.
  """
  def users_routing_key(subtopic) when is_binary(subtopic) do
    users_topic() |> String.replace("*", subtopic)
  end

  @doc """
  Users queue is bound to the topic.
  Routes messages to the users queue by matching on the topic and subtopic.
  For example a topic of `users.created` and `users.updated` will route to the users queue.
  """
  def users_topic, do: "users.*"
end
