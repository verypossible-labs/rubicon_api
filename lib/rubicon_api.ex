defmodule RubiconAPI do
  defmacro __using__(_opts) do
    quote do
      Module.register_attribute __MODULE__, :steps, accumulate: true
      import RubiconAPI
      @before_compile unquote(__MODULE__)

      def child_spec(opts) do
        %{
          id: RubiconAPI.Server,
          start: {RubiconAPI.Server, :start_link, [{__MODULE__, opts}]},
          type: :worker,
          restart: :permanent,
          shutdown: 500
        }
      end
    end
  end

  defmacro __before_compile__(env) do
    steps = Module.get_attribute(env.module, :steps, []) |> Enum.reverse()
    quote do
      def __rubicon_steps__() do
        unquote(steps)
      end
    end
  end

  defmacro step(name, contents) do
    contents =
      case contents do
        [do: block] ->
          quote do
            unquote(block)
          end

        _ ->
          quote do
            try(unquote(contents))
          end
      end

    contents = Macro.escape(contents, unquote: true)

    quote bind_quoted: [name: name, contents: contents] do
      @steps name
      name = :"#{name}"
      def unquote(name)(), do: unquote(contents)
    end
  end

  def prompt_yn?(message) do
    GenServer.call({:global, Rubicon.UI}, {:prompt_yn?, message}, 60_000)
  end

  def firmware_path() do
    path = "/root/install.fw"
    if File.exists?("/root/install.fw") do
      {:ok, path}
    else
      with {:ok, data} <- GenServer.call({:global, Rubicon}, :firmware, 15_000),
      :ok <- File.write(path, data, [:write, :sync]) do
        {:ok, path}

      end
    end
  end

  def ssl_signer() do
    GenServer.call({:global, Rubicon}, :ssl_signer)
  end

  def step_status(status) do
    GenServer.call({:global, Rubicon.UI}, {:set_status, :right, status})
  end

  def prompt(prompt) do
    GenServer.call({:global, Rubicon.UI}, {:prompt, prompt})
  end

  def prompt_clear() do
    GenServer.call({:global, Rubicon.UI}, :prompt_clear)
  end

end
