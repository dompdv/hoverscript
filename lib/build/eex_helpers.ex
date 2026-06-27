defmodule Hoverscript.Build.EExHelpers do
  @moduledoc false

  @doc """
  Expands a Hoverscript file and returns its text for inline insertion during EEx evaluation.

  ## Examples

      <%= import_hvt("partials/item.hvt", title: "Intro") %>
  """
  def import_hvt(path, params \\ []) when is_binary(path) do
    Hoverscript.Build.Expand.import_hvt(path, params)
  end
end
