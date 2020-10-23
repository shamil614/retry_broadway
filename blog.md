# Rabbitmq Retries Made Easy with Delayed Message Exchange Plugin and Elixir's Broadway

## Introduction
If you ever needed to distrubute work to multiple nodes then you probably used or considered using RabbitMQ.
RabbitMQ is easily one the most versatile and reliable message brokers available. 
As many know it's so reliable because it's built with Erlang and OTP.
While RabbitMQ has many features, handling and retrying failed messages is not one of them.
Recently I developed a solution that leverages core RabbitMQ features 
along with a plugin to develop a clear and concise retry pattern for failed or rejected messages.
While this blog post uses Elixir's Broadway for processing messages, 
the overall retry pattern can easily be applied for any other language or implmentation.
You can find the [RetryBroadway code](https://github.com/shamil614/retry_broadway) on Github.

## Core Components
The first and most important component for handling failed or rejected messages is what RabbitMQ calls the 
[Dead Letter Exchange](https://www.rabbitmq.com/dlx.html) (dlx). Please read the documentation for details.
In short, a message can be republished to a dlx (an exchange) for several failure reasons like: 
AMQP reject, nack, or TTL reached because the message did not get acknowledged. 

The second component is a RabbitMQ plugin called Delayed Message Exchange Plugin (dm).
The dm plugin add additional functionality to a standard RabbitMQ exchange to delay the delivery to a queue.
Essentially the plugin provides a mechanism to delay the retrying of a failed message.
Delaying the reprocessing of a message is important because it allows for implementing backoff when retrying 
failed messages.

The third component is a retry pipeline (processor). 
The retry pipeline checks a queue for failed messages then republishes the message to the original exchange.
Before republishing, the retry pipeline sets a `x-delay` delay header so the dm exchange knows how long to delay
the message. Most importantly, the retry pipeline is in charge of deciding when to stop republishing the message. 
At some point retrying a failed message must stop and this pipeline provides a programatic mechanism for deciding 
when to give up. Overall the pipeline provides a single location for the retry logic. 

## Workflow
In an effort to clarify the components described above, here's a diagram that illustrates a happy path and a retry path.

<img src="./generic_broadway_pipeline_with_retry.svg">

## Topology
This section covers the `setup.ex` mix task that builds out the topology for the demo.

```elixir
# setup.ex
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
```
The start of the script is pretty much just plumbing. 
`RetryBroadway.rabbitmq_config()` is a helper to provide connection configuration for RabbitMQ.
Then a connection and channel are opened. 
The channel is then passed to `setup_rabbitmq` where all the real setup work happens. 
At the end of it all the connection is closed which also closes the channel.
Keep in mind this is a naive approach to connection management and is only intended for demonstration purposes.

```elixir
# setup.ex continued

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
```

At the start of the function the two exchanges are declared. The main exchange is a topic exchange that handles
the routing of messages for work pipelines (processors). It also is a delayed message exchange (dm) which 
comes into play when the retry pipeline republishes a message with a `x-delay` header.
The retry exchange is a simple topic exchange that serves as the dead letter exchange (dlx) and routes failed
messages to the retry queue. Lastly, both exchanges are marked as `durable` so they will survive restarts or crashes.

```elixir
# setup.ex continued
# setup_rabbitmq/1 continued

queues_topics = [
  {users_queue(), users_topic()},
  {jobs_queue(), jobs_topic()}
]
```
This data structure is just a convenient way to iterate through the setup of the queues and topics.
The functions evaluate to this:

```elixir
[
  {"users", "users.*"},
  {"jobs", "jobs.*"}
]
```

```elixir
# setup.ex continued
# setup_rabbitmq/1 continued

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
```
Now this code creates the `jobs` and `users` queue but also delcares (creates) the dlx by setting the header
`x-dead-letter-exchange` to `retry` by calling `retry_exchange()`. This important. Here at the queue level
the dlx is specified so any failing message is routed by RabbitMQ to the dlx. Which is really nice because it's
hard to mess up. Of course, it's marked as `durable`.

```elixir
# setup.ex continued
# setup_rabbitmq/1 continued

{:ok, _response} = AMQP.Queue.declare(chan, retry_queue(), durable: true)
```
Simple enough here. Create the `retry` queue and like everything else it's marked as `durable`.

```elixir
# setup.ex continued
# setup_rabbitmq/1 continued

    # bind the queues to the exchanges by a topic (routing key)
    queues_topics
    |> Enum.each(fn {queue, topic} ->
      :ok = AMQP.Queue.bind(chan, queue, main_exchange(), routing_key: topic)
    end)

    # match any routing key of any length and route an message on the retry_exchange (dlx) to the retry queue
    :ok = AMQP.Queue.bind(chan, retry_queue(), retry_exchange(), routing_key: "#")
  end
end
```

Lastly, the queues are bound to the topics. The work queues are bound by `jobs.*` and `users.*` routing keys which 
means a message of `jobs.created` or `jobs.whatever` is routed to the jobs queue. Same applies for users.
Now the `retry` queue is bound by `#` which pretty well matches topic. 
Read more on [routing keys](https://www.rabbitmq.com/tutorials/tutorial-four-elixir.html).

## Handling Retries
Leading up to this section, we established that failed messages end up in a queue designated by the dlx.
Once the messages are in the `retry` queue there needs to be a processor (pipeline) to republish the messages.
Most importantly, the `RetryProcessor` checks determines when to stop retrying and determining the backoff between
retries.

```elixir
# retry_processor.ex
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
```
The first part of the module basic setup. The `use Broadway` provides the tooling for processing messages from RabbitMQ.
The module attribute `@delay_header_name "x-delay"` is the header that the dm exchange uses for delaying
the routing of the retried message to the work queue. The other module attribute `@retry_header "x-retries"` track the
number of times the message got retried. Only the `RetryProcessor` uses the `x-retries` to determine when to stop
retrying the failed message. Thus encapsulating the retry logic into a single place `RetryProcessor`.

```elixir
# retry_processor.ex continued
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
```
The `start_link/1` function handle the connection to RabbitMQ and configuring the specifics of the Broadway pipeline.
Using the helper function `{:ok, config} = RetryBroadway.rabbitmq_config()`, it's easy to pass connection information
(host, port, etc) to Broadway to connect to RabbitMQ. Similarly `queue = Topology.retry_queue()` is a conventient way
to use the same names for queues, exchanges, etc across the application.
For the most part `Broadway.start_link/2` is fairly standard boilerplate configuration. See the [Broadway
docs](https://hexdocs.pm/broadway/Broadway.html#start_link/2) for more detail. Though there's one part of the
configuration that requires some depth: the `on_failure:` option.

Notice the `on_failure:` setting is configured to `reject` a failed message. 
Effectively, Broadway is adhering to AMQP protocol and rejecting the failed message. 
Rejecting is essential to enable the dlx and retry workflow (on work processors), and aborting the workflow
in the `RetryProcessor`.
If the default setting `:reject_and_requeue` were to be used, the message could get stuck in an endless loop!
Any failure with `:reject_and_requeue` configured results in **immediate** requeueing of messages without backoff
(delay), or abilitiy to track retries in order to abort!
I can't stress this point enough. While `:reject_and_requeue` is a sensible default for Broadway in general,
in practice `:reject_and_requeue` could result in your application overloading and crashing in the very bad way.
Not the good OTP way :) Make sure to consider the `on_failure:` configuration carefully. 

```elixir
# retry_processor.ex continued
 @impl true
  def handle_message(
        _,
        %Message{data: data, metadata: %{headers: headers, routing_key: routing_key}} = message,
        _
      ) do
```
The `handle_message/3` function is required by Broadway to implement how to process messages. The function header
serves to deconstruct the `%Message{}` into the various components. Soon you'll see that the components are used to 
republish the message to the original exchange with the same routing keys and data.

```elixir
# retry_processor.ex continued
    retry_data = %{retry_count: retry_count, index: _index} = get_retry_count(headers)

    if (retry_count || 0) < max_retries() do
      {:ok, exchange} = find_exchange(headers)
```
As we'll cover the `RetryProcessor` module has various function that extract and update header data.
For example `get_retry_count/1` is a simple function that looks in the headers for `x-retries` and returns the
number of retries attempted and position of the header in the list. See `@type retry_header_data()` at the top
of the module. With the `retry_count` extracted, there's a condition to determine if the message should be retried.
Next, another helper function `find_exchange/1` finds the original exchange which is necessary to republish the message.

Note that the result is matched with a tagged tuple `{:ok, exchange} = find_exchange(headers)`. If for some reason
the exchange can't be found, then the message can't be republished. 
The resulting `MatchError` will crash the process and Broadway will `reject` the message (`on_failure: :reject`) 
preventing a retry on a message that will never succeed. This is a good thing. No sense in retrying
a failed message if it can't be republished.

```elixir
# retry_processor.ex continued
      updated_headers =
        headers
        |> update_retry_count(retry_data)
        |> update_retry_delay()
```
Here the `headers` extrated from `%Message{}` has the `x-retries` and the `x-delay` header values set or increased.
The `updated_headers` is used when republishing.

```elixir
# retry_processor.ex continued
  data = fake_retry_behaviour(data, retry_count)
```
The only purpose of this function is to fake some sort of behavior for demonstration purposes. It has no purpose
in a real world scenario.

```elixir
# retry_processor.ex continued

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
```
This the end of the path where the message is retried. Here the same config is used to connect to RabbitMQ via the
`AMQP` hex library. Then the message is republished with the `updated_headers` so the `retry_count` is maintained,
and a delay is made by the dm exchange. The callback rquires a `message` be returned.

```elixir
# retry_processor.ex continued

    else
      Logger.error("Max retries reached! \n #{inspect(message)}")
      # message is marked as failed. must return failed message.
      Message.failed(message, "Message reached max retries of #{max_retries()}")
    end
  end
```
This is the end of the `handle_message/3` function where the `if` condition fails and retries are aborted.
Using the `Message.failed/2` is just good practice. It doesn't serve much purpose in our usage other than documentation.
I won't go into great depth with the other functions. The function are pretty small and should be understandable
with the information provided.


## Demonstrating Retries
In this section I will walk through the basic pipelines (processors). Keep in mind the code is modified to demonstrate
failures for retries. In this case, I'll cover the `JobsProcessor` since the `UsersProcessor` is basically the same.

```elixir
# jobs_processor.ex
defmodule RetryBroadway.Processors.JobsProcessor do
  # code removed for brevity

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
```
This is almost identical to `RetryProcessor`. The only substantive difference is the `queue` being `jobs`.
Again, `on_failure: :reject` enables usage of the dlx such that any failures route the message to the `retry_exchange`
and processed by the `RetryProcessor`.

```elixir
# jobs_processor.ex continued
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
        IO.puts("Passing Jobs data with a value of #{data} ")
        message
    end
  end
end
```
In this case `handle_message/3` is implemented to demonstrate failures and retries. In the first condition,
`Message.failed/2` is used to retry messages with a data payload of `"9"`. Note as `UserProcessor` demonstrates, an
exception results the same retry workflow. See the
[demo code](https://github.com/shamil614/retry_broadway/blob/master/lib/retry_broadway/processors/users_processor.ex#L52).
The second condition fakes a scenario where the message passes on a second try.
See the [`fake_retry_behaviour/2`](https://github.com/shamil614/retry_broadway/blob/master/lib/retry_broadway/processors/retry_processor.ex#L83-L94).
Again, this a contrived example that allows for demonstration of the retry workflow.

Ok that's enough explaining. Now it's time to give it a try yourself and see the retry workflow in action.
Take a look at the [README](https://github.com/shamil614/retry_broadway/blob/master/README.md) for directions
on how to start RabbitMQ and run the demos.