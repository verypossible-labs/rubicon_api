defmodule RubiconAPI.Server do
  use GenServer
  require Logger

  def start_link({mod, opts}) do
    GenServer.start_link(RubiconAPI.Server, {mod, opts}, name: RubiconAPI.Server)
  end

  def init({mod, opts}) do
    System.cmd("epmd", ["-daemon"])
    ifname = opts[:network_interface]
    VintageNet.subscribe(["interface", ifname])

    {:ok, %{
      status: :disconnected,
      host_address: nil,
      host_node: nil,
      ifname: ifname,
      mod: mod,
      steps: []
    }, {:continue, VintageNet.get(["interface", ifname, "lower_up"])}}
  end

  def handle_continue(true, s) do
    Process.send_after(self(), :connect, 1_000)
    {:noreply, s}
  end
  def handle_continue(false, s), do: {:noreply, s}

  def handle_info({VintageNet, ["interface", ifname, "lower_up"], false, true, %{}}, %{ifname: ifname} = s) do
    Process.send_after(self(), :connect, 1_000)
    {:noreply, s}
  end

  def handle_info({VintageNet, ["interface", ifname, "lower_up"], true, false, %{}}, %{ifname: ifname} = s) do
    {:noreply, disconnect(s)}
  end

  def handle_info(:connect, %{status: :disconnected, ifname: ifname} = s) do
    with [_ | _] = addresses <- VintageNet.get(["interface", ifname, "addresses"]),
    %{address: my_address} <- Enum.find(addresses, & &1.family == :inet) do

      host_address = my_address |> subtract_one() |> ip_to_string()
      my_address = ip_to_string(my_address)
      my_node = :"rubicon-target@#{my_address}"
      host_node = :"rubicon@#{host_address}"
      {:ok, _pid} = Node.start(my_node)
      Logger.debug "Node started #{inspect my_node}"
      Process.send_after(self(), :connect, 1_000)
      {:noreply, %{s | host_node: host_node, status: :connected}}
    else
      _ ->
        Process.send_after(self(), :connect, 1_000)
        {:noreply, s}
    end
  end

  def handle_info(:connect, %{status: :connected, host_node: host_node} = s) do
    Logger.debug "Connecting to #{inspect host_node}"
    s =
      if Node.connect(host_node) do
          steps = s.mod.__rubicon_steps__()
          wait_for_rubicon(%{s | host_node: host_node, steps: steps})
      else
        Process.send_after(self(), :connect, 1_000)
        s
      end
    {:noreply, s}
  end

  def handle_info(:wait_for_rubicon, s) do
    {:noreply, wait_for_rubicon(s)}
  end

  def handle_info(message, status) do
    Logger.debug "Unhandled message: #{inspect message}"
    {:noreply, status}
  end

  def terminate(_reason, s) do
    Node.stop()
    {:stop, s}
  end

  defp disconnect(s) do
    Node.stop()
    %{s | status: :disconnected, host_address: nil, host_node: nil}
  end

  defp run_steps(%{mod: mod, steps: steps} = s) do
    {status, results} =
      Enum.reduce_while(steps, {:pass, []}, fn(step, {status, results}) ->
        result = apply(mod, :"#{step}", [])
        step_result(step, result)
        case result do
          :ok ->
            {:cont, {status, [{step, :ok} | results]}}
          {:ok, info} ->
            {:cont, {status, [{step, {:ok, info}} | results]}}
          {:error, error} ->
            {:halt, {:fail, [{step, {:error, error}} | results]}}
        end
      end)
    Logger.debug "Device status #{inspect status}"
    GenServer.call({:global, Rubicon}, {:finished, status, results})
    s
  end

  defp ip_to_string(ip) do
    ip
    |> :inet.ntoa()
    |> List.to_string()
  end

  defp subtract_one({a, b, c, d}), do: {a, b, c, d - 1}

  defp handshake(handshake) do
    GenServer.call({:global, Rubicon}, {:handshake, handshake}, :infinity)
  end

  defp step_result(step, result) do
    GenServer.call({:global, Rubicon}, {:step_result, step, result})
  end

  defp wait_for_rubicon(%{steps: steps} = s) do
    case :global.whereis_name(Rubicon) do
      pid when is_pid(pid) ->
        handshake(steps)
        run_steps(s)

      _ ->
        Process.send_after(self(), :wait_for_rubicon, 1_000)
        s
    end
  end
end
