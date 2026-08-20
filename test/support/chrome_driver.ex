defmodule ChatWeb.ChromeDriver do
  @moduledoc """
  Gerenciador de ciclo de vida do ChromeDriver para testes E2E.

  Inicia o binário do ChromeDriver como um processo supervisionado,
  mantém o port e garante o fechamento do processo ao terminar.
  """

  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    executable = Keyword.fetch!(opts, :executable)
    port_number = Keyword.fetch!(opts, :port)

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        args: ["--port=#{port_number}", "--allowed-ips=127.0.0.1"]
      ])

    {:ok, %{port: port}}
  end

  @impl true
  def handle_info({_port, {:data, _output}}, state), do: {:noreply, state}

  def handle_info({_port, {:exit_status, status}}, state),
    do: {:stop, {:chrome_driver_exit, status}, state}

  @impl true
  def terminate(_reason, %{port: port}) do
    if Port.info(port), do: Port.close(port)
    :ok
  end
end
