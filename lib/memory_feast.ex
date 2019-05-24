defmodule MemoryFeast do
  @moduledoc """
  A sample app that demos some interesting GenServer garbage collection behavior.
  """

  alias MemoryFeast.Worker

  def start_normal_worker() do
    Worker.start_link(:normal)
  end

  def start_task_worker() do
    Worker.start_link(:task)
  end
end
