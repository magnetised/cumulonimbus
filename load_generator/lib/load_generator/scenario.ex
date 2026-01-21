defmodule LoadGenerator.Scenario do
  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    {scenario, opts} = Keyword.pop!(args, :scenario)

    children = [
      {scenario, opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
