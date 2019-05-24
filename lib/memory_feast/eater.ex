defmodule MemoryFeast.Worker do
  @moduledoc """
  Simulates a worker that:

  - fetches some data
  - processes the data
  - outputs the processed data
  - repeats this procedure on an interval
  """

  use GenServer

  @type execution_type :: :normal | :task

  @doc """
  Starts the worker with the given type.
  """
  @spec start_link(execution_type()) :: {:ok, pid()}
  def start_link(:normal) do
    GenServer.start_link(__MODULE__, :normal, name: :i_am_the_normal_worker)
  end

  def start_link(:task) do
    GenServer.start_link(__MODULE__, :task, name: :i_am_the_task_worker)
  end

  @doc """
  Inits the worker.

  The worker will be told to fetch_process_and_dump_data ~1 second after being started.
  """
  @spec init(execution_type()) :: {:ok, execution_type()}
  def init(execution_type) do
    Process.send_after(self(), :fetch_process_and_dump_data, 1000)
    {:ok, execution_type}
  end

  @doc """
  Tells the worker to fetch_process_and_dump_data.

  If the worker is of :normal type, it will simply call the `fetch_process_and_dump_data/0` function.

  If the worker is of :task type, it will execute the function within a Task (i.e. another process).

  Matching on :ok is simulating having to block to get a response from the function call versus just
  firing and forgetting.
  """
  @spec handle_info(:fetch_process_and_dump_data, execution_type()) :: {:noreply, :normal}
  def handle_info(:fetch_process_and_dump_data, :normal) do
    :ok = fetch_process_and_dump_data()
    {:noreply, :normal}
  end

  def handle_info(:fetch_process_and_dump_data, :task) do
    :ok =
      fn -> fetch_process_and_dump_data() end
      |> Task.async()
      |> Task.await(10_000)

    {:noreply, :task}
  end

  # this function is simulating a task that uses up a considerable amount of memory (in this case, binary data) and
  # outputs it somewhere (in this case, stdout).
  #
  # notice how it does not return any of the data it is producing/consuming. it simply creates it, uses it, and then returns
  # :ok.
  #
  # in theory, the memory used for the data should get garbage collected once this function is done executing.
  @spec fetch_process_and_dump_data :: :ok
  defp fetch_process_and_dump_data do
    fetch_data()
    |> process_data()
    |> dump_data()

    :ok

    :ok
  end

  @spec fetch_data :: String.t()
  defp fetch_data do
    0..3_000_000
    |> Enum.map(fn _ ->
      1000
      |> :rand.uniform()
      |> to_string()
    end)
    |> Enum.join("_")
  end

  @spec process_data(String.t()) :: integer()
  defp process_data(data) do
    data
    |> String.split("_")
    |> Enum.map(fn value ->
      {int, ""} = Integer.parse(value)
      int
    end)
    |> Enum.sum()
  end

  @spec dump_data(integer()) :: :ok
  defp dump_data(processed_data) do
    IO.puts("Processed data: #{processed_data}")
  end
end
