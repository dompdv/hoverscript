defmodule Hoverscript.ParseError do
  @moduledoc """
  Raised when `Hoverscript.parse!/1`, `Hoverscript.format!/2`, or similar functions
  encounter parsing errors.
  """

  defexception [:message, :errors]

  @impl true
  def exception(errors: errors) do
    %__MODULE__{
      message: "failed to parse Hoverscript document",
      errors: errors
    }
  end
end
