defmodule Hoverscript.BuildError do
  @moduledoc """
  Raised when `Hoverscript.build!/2` fails during expansion or parsing.
  """

  defexception [:message, :reason, :errors]

  @impl true
  def exception(opts) do
    reason = Keyword.fetch!(opts, :reason)
    errors = Keyword.get(opts, :errors)

    message =
      case reason do
        :expand -> "failed to expand Hoverscript project"
        :parse -> "failed to parse expanded Hoverscript document"
        other -> "failed to build Hoverscript project (#{inspect(other)})"
      end

    %__MODULE__{message: message, reason: reason, errors: errors}
  end
end
