# Your GenServer is harbouring old memories. Help it let them go.

I was recently working on a project that might feel familiar to some:

- Some data needed to be pulled from an external source.
- The pulled data needed to be processed.
- The processed data needed to be dumped into a database.
- This entire processes needed to be done periodically.

For those familiar with Erlang/Elixir, you'll know that either language can do this in its sleep.

The application I created to perform this task was a simple Elixir app that ran as a worker on a Heroku Hobby Dyno, which has a ~0.5GB memory limit.

Upon initially creating and deploying the application, everything seemed fine. However, after a few hours of running, the Heroku dashboard indicated that the application was using progressivly
more and more memory, and eventually it started choking as it passed the 0.5GB mark.

Now I am not here to describe how to write memory-effecient code, or to solve the problem stated above in the absolute best way possible. I am here to tell you about the method(s)
I chose, the strange memory issue I was having, how I diganosed the issue, and how I solved the issue.

Let's start w/ some code that roughly simulates the implementation I went with:

NOTE: If you are not familiar with GenServer's, you may want to take a look at the [elixir-lang intro to them](https://elixir-lang.org/getting-started/mix-otp/genserver.html).


```elixir
defmodule Worker do
  use GenServer
  
  @one_hour_in_milliseconds 1000 * 60 * 60

  def start_link do
    GenServer.start_link(__MODULE__, nil, name: :my_worker)
  end

  def init(nil) do
    Process.send_after(self(), :fetch_process_and_dump_data, 1000)
    {:ok, nil}
  end

  def handle_info(:fetch_process_and_dump_data, nil) do
    :ok = fetch_process_and_dump_data()
    Process.send_after(self(), :fetch_process_and_dump_data, @one_hour_in_milliseconds)
    {:noreply, nil}
  end

  defp fetch_process_and_dump_data do
    fetch_data()
    |> process_data()
    |> dump_data()
  end

  defp fetch_data do
    0..3_000_000
    |> Enum.map(fn _ ->
      1000
      |> :rand.uniform()
      |> to_string()
    end)
    |> Enum.join("_")
  end

  defp process_data(data) do
    data
    |> String.split("_")
    |> Enum.map(fn value ->
      {int, ""} = Integer.parse(value)
      int
    end)
    |> Enum.sum()
  end

  defp dump_data(processed_data) do
    IO.puts("Processed data: #{processed_data}")
  end
end
```

Here we are defining a simple GenServer module. When an instance of this GenServer is started, it will eventually run a function called `fetch_process_and_dump_data/0` that is simulating fetching some data, processing that data, and dumping it somewhere. After completing this work, the GenServer will schedule itself to do the same work in ~1 hour.

To simulate fetching some data, we're just creating a large string that is made up of random numbers seperated by `_`. To simulate processing this data, we simply parse out all the numbers and sum them up. To simulate dumping this data, we simply print the result to stdout.

Notice how, beyond matching on the `:ok` response, we do not care about any of the data the function was dealing with. In theory, all of the memory allocated for this data should be garbage collected upon the function finishing. However, if we run this code, we can see that this is not exactly the case.

You can run code this simply by starting an `iex>` session and copy and pasting the code into the shell. Once the code is compiled in the shell, you can start a worker via:

```elixir
iex(2)> Worker.start_link()
{:ok, #PID<0.157.0>}
```

About a second after starting, the worker will call `fetch_process_and_dump_data/0`, and begin its work. Once it's complete, you'll see output like `"Processed data: 423423543"`, though your number will most likely differ. If you wait ~1 hour, the worker will do this same work again.

So you might be thinking, that worked fine, what's the problem? We can see the problem if we observe what's going on at the memory level. Let's do that.

Let's kill the current `iex>` session and start a new one. Again, copy and paste the code into the shell. Before starting the worker again, let's start the erlang observer via:

```elixir
iex(2)> :observer.start()
:ok
```

If installed correctly, a GUI should open that basically serves as a System/Activty Monitor, but for the running Elixir process.

You can see the current memory usage in the top-right corner. I personally see a value that's roughly ~25MB, but yours may differ. 

Let's start the worker again via:

```elixir
iex(2)> Worker.start_link()
{:ok, #PID<0.157.0>}
```

As the worker runs, you'll see the memory usage climb. When I've run this, the memory usage gets to be about ~450MB.

Now running into this issue, I would assume that once the worker completed its work, that the memory should
drop back down to nearly what it was before (~25MB), but if you keep watching, it will stay in the hundreds of MBs.

What's going on here? What is referencing that memory and keeping it from being garbage collected? Let's take a closer look via the observer.

If you click on the *Processes* tab, you'll seee a table of all of running processes. Let's look for our worker process. As you might've noticed
in the GenServer code, we named our worker `:my_worker`.

This will allow us to find it by name in the table. You can click on the *Name or Initial Func* column header to sort by name, and scroll
until you find `my_worker`.

If you look under its *Memory* column, you'll see the process is still holding onto a ton of memory, despite the code not explictly referencing or using
the data generated by the work after the work was completed. What's going on here?

To be honest, I am not sure. I've done some Googling, and read some random posts about how GenServer's might be holding onto some of
these references for debugging/error handling purposes, but I came to no conclusion that I feel confident enough about to share. However,
I do have a solution that I feel confident enough about to share!

Let's modify the code just a tiny bit:

```elixir
defmodule Worker do
  use GenServer
  
  @one_hour_in_milliseconds 1000 * 60 * 60

  def start_link do
    GenServer.start_link(__MODULE__, nil, name: :my_worker)
  end

  def init(nil) do
    Process.send_after(self(), :fetch_process_and_dump_data, 1000)
    {:ok, nil}
  end

  def handle_info(:fetch_process_and_dump_data, nil) do
    :ok =
      fn -> fetch_process_and_dump_data() end
      |> Task.async()
      |> Task.await(100_000)
    
    Process.send_after(self(), :fetch_process_and_dump_data, @one_hour_in_milliseconds)
    {:noreply, nil}
  end

  defp fetch_process_and_dump_data do
    fetch_data()
    |> process_data()
    |> dump_data()
  end

  defp fetch_data do
    0..3_000_000
    |> Enum.map(fn _ ->
      1000
      |> :rand.uniform()
      |> to_string()
    end)
    |> Enum.join("_")
  end

  defp process_data(data) do
    data
    |> String.split("_")
    |> Enum.map(fn value ->
      {int, ""} = Integer.parse(value)
      int
    end)
    |> Enum.sum()
  end

  defp dump_data(processed_data) do
    IO.puts("Processed data: #{processed_data}")
  end
end
```

I only changed about 3 lines of code, but posted the whole module to make it easier to copy and paste. The only change made was
in `handle_info/2`. Instead of just calling `fetch_process_and_dump_data/0` directly, we are now executing the function
within a `Task` (read more about `Task.async` and `Task.await` [here](https://hexdocs.pm/elixir/Task.html)).

This should result in the same work being done, and, as you will see, very different memory implications.

Let's start another `iex>` session, copy and paste this modified code in, and run `:observer.start()`. Just like before, take note of the starting memory usage.

Now let's start the new-and-improved worker:

```elixir
iex> Worker.start_link()
{:ok, #PID<0.162.0>}
```

Once the worker begins working, you should see the total memory usage climb. Wait until the worker completes its work, and now watch the memory usage. Unless I am
just crazy or have some strange hardware, you should see the memory usage drop back to roughly the amount it started at. Success!

Now I do not want the emphasis to be on the use of Elixir's `Task` module. Instead, I want to focus on how the code is now executing the memory-intensive work
in a seperate process, where `Task.async/1` was just one way to accomplish this. The idea here is, if all the work is done in a seperate process, that process
will be what allocates the memory, and when it completes its work and is killed off, the memory will be garbage collected.

Though I cannot prove beyond this example that this is in fact what is happening, I can speak from experience that this solution works in a real production system. When
I modified the Heroku worker application to run its work in seperate processes, the memory usage went from climbing upwards of ~0.5GB, to staying at roughly ~0.25GB, which
was more than enough to keep running this application on a Heroku Hobby Dyno.
