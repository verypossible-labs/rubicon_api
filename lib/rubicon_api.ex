defmodule RubiconAPI do
  defmacro __using__(_opts) do
    quote do
      Module.register_attribute __MODULE__, :steps, accumulate: true
      import RubiconAPI, only: [step: 2, prompt_yn?: 1]
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
            :ok
          end

        _ ->
          quote do
            try(unquote(contents))
            :ok
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
    GenServer.call(RubiconAPI.Server, {:prompt_yn?, message})
  end
end
