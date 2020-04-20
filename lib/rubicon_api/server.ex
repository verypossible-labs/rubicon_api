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
      timer_ref: nil,
      host_address: nil,
      host_node: nil,
      ifname: ifname,
      mod: mod,
      steps: []
    }, {:continue, VintageNet.get(["interface", ifname, "lower_up"])}}
  end

  def handle_continue(true, s), do: {:noreply, connect(s)}
  def handle_continue(false, s), do: {:noreply, s}

  def handle_call({:prompt_yn?, _message}, _from, %{host_node: nil} = s) do
    {:reply, {:error, :no_connection}, s}
  end

  def handle_call({:prompt_yn?, message}, _from, %{host_node: node} = s) do
    reply = :rpc.block_call(node, Rubicon, :prompt_yn?, [message])
    {:reply, reply, s}
  end

  def handle_info({VintageNet, ["interface", ifname, "lower_up"], false, true, %{}}, %{ifname: ifname} = s) do
    {:noreply, connect(s)}
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
      {:noreply, %{s | host_node: host_node, status: :connected}}
    else
      _ -> {:noreply, s}
    end
  end

  def handle_info(:connect, %{status: :connected, host_node: host_node} = s) do
    Logger.debug "Connecting to #{inspect host_node}"
    s =
      if Node.connect(host_node) do
          :timer.cancel(s.timer_ref)
          :timer.sleep(100)
          steps = s.mod.__rubicon_steps__()
          handshake(host_node, steps)
          run_steps(%{s | host_node: host_node, steps: steps})
      else
        s
      end
    {:noreply, s}
  end

  def handle_info(message, status) do
    Logger.debug "Unhandled message: #{inspect message}"
    {:noreply, status}
  end

  defp connect(s) do
    {:ok, timer_ref} = :timer.send_interval(1000, :connect)
    %{s | timer_ref: timer_ref}
  end

  defp disconnect(%{timer_ref: nil} = s) do
    Node.stop()
    %{s | status: :disconnected, host_address: nil, host_node: nil}
  end

  defp disconnect(%{timer_ref: timer_ref} = s) do
    :timer.cancel(timer_ref)
    disconnect(%{s | timer_ref: nil})
  end

  defp run_steps(%{host_node: node, mod: mod, steps: steps} = s) do
    Enum.each(steps, fn(step) ->
      result = apply(mod, :"#{step}", [])
      step_result(node, step, result)
    end)
    s
  end

  defp ip_to_string(ip) do
    ip
    |> :inet.ntoa()
    |> List.to_string()
  end

  defp subtract_one({a, b, c, d}), do: {a, b, c, d - 1}

  defp handshake(node, handshake) do
    :rpc.block_call(node, Rubicon, :handshake, [handshake])
  end

  defp step_result(node, step, result) do
    :rpc.block_call(node, Rubicon, :step_result, [step, result])
  end
end
