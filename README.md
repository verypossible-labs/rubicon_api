# RubiconAPI

This project is part of [Very labs](https://github.com/verypossible-labs/docs/blob/master/README.md).
---

RubiconAPI is an application that lets you create firmware to interface with a
[Rubicon](https://github.com/verypossible-labs/rubicon) host.

## Usage

RubiconAPI executes a list of steps when connecting with a Rubicon host.
Steps are defined in a module in your application,
For example:

```
defmodule ExampleApp do
  use RubiconAPI

  step "Run tests" do
    case ExUnitRelease.run() do
      {:ok, %{failures: 0}} -> :ok
      {_, result} -> {:error, result}
    end
  end

  step "Ask a question" do
    if prompt_yn?("Is the flux capacitor fluxing?") do
      :ok
    else
      {:error, "Flux capacitor is not fluxing"}
    end
  end
end
```

Steps are run in order from top to bottom. They are expected to return
`:ok, {:error, reason :: any}`

If a step returns `{:error, reason :: any}`, execution of subsequent steps is
halted, and the test exits with the status as failed. If all the tests return
`:ok`, the test finished with a status of passed.

The following functions are API calls to the rubicon host and are available
to use in any defined step.

`prompt_yn`: Prompt a message and wait for a reply. The reply will be `:yes/:no`
