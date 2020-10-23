defmodule RetryBroadway.Processors.RetryProcessorTest do
  use ExUnit.Case

  alias RetryBroadway.Processors.RetryProcessor

  describe "find_exchange/1" do
    test "finds the first exchange the message was published to" do
      headers = base_headers() |> add_first_exchange()
      assert RetryProcessor.find_exchange(headers) == {:ok, "main_exchange"}
    end

    test "returns nil if first exchange isn't present in the headers" do
      assert RetryProcessor.find_exchange(base_headers()) == nil
    end
  end

  describe "max_retries/0" do
    test "returns the max number of retries to perform on the dead message" do
      assert RetryProcessor.max_retries() == 10
    end
  end

  describe "get_retry_count/1" do
    test "returns nil if retry header is not set" do
      assert %{retry_count: nil, index: 2} = RetryProcessor.get_retry_count(base_headers())
    end

    test "returns retry attempts made if retry header is set" do
      headers = base_headers() |> add_retries(1)
      assert %{retry_count: 1, index: 0} = RetryProcessor.get_retry_count(headers)

      headers = base_headers() |> add_retries(100, 1)
      assert %{retry_count: 100, index: 1} = RetryProcessor.get_retry_count(headers)
    end
  end

  describe "update_retry_delay/1" do
    test "sets delay header to 100 ms if delay header is not set" do
      updated_headers = base_headers() |> add_delay(100)
      assert RetryProcessor.update_retry_delay(base_headers()) == updated_headers
    end

    test "sets retry header to +1 of previous value if retry header is set" do
      headers = base_headers() |> add_delay(100)
      updated_headers = base_headers() |> add_delay(300)

      assert RetryProcessor.update_retry_delay(headers) == updated_headers
    end
  end

  describe "set_or_update_retry_count/1" do
    test "sets retry header to 1 if retry header is not set" do
      headers = base_headers()
      updated_headers = headers |> add_retries(1)

      retry_data = RetryProcessor.get_retry_count(headers)
      assert RetryProcessor.update_retry_count(headers, retry_data) == updated_headers
    end

    test "sets retry header to +1 of previous value if retry header is set" do
      headers = base_headers() |> add_retries(1)
      updated_headers = base_headers() |> add_retries(2)

      retry_data = RetryProcessor.get_retry_count(headers)
      assert RetryProcessor.update_retry_count(headers, retry_data) == updated_headers
    end
  end

  defp base_headers do
    [
      {"x-death", :array,
       [
         table: [
           {"count", :long, 3},
           {"exchange", :longstr, "main_exchange"},
           {"queue", :longstr, "users"},
           {"reason", :longstr, "rejected"},
           {"routing-keys", :array, [longstr: "users.created"]},
           {"time", :timestamp, 1_602_579_900}
         ]
       ]},
      {"x-first-death-queue", :longstr, "users"},
      {"x-first-death-reason", :longstr, "rejected"}
    ]
  end

  defp add_delay(headers, delay) do
    [{"x-delay", :signedint, delay} | headers]
  end

  defp add_retries(headers, retries) do
    [{"x-retries", :long, retries} | headers]
  end

  defp add_retries(headers, retries, index) do
    List.insert_at(headers, index, {"x-retries", :long, retries})
  end

  defp add_first_exchange(headers, name \\ "main_exchange") do
    # purposely adding to back of list to make sure correct value is found
    headers ++ [{"x-first-death-exchange", :longstr, name}]
  end
end
