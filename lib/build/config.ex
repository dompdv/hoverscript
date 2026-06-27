defmodule Hoverscript.Build.Config do
  @moduledoc false

  @doc """
  Loads all `*.toml` files from a project directory.

  Each file `name.toml` becomes assign key `:name` (atom).
  """
  def load(project_dir) do
    project_dir
    |> Path.join("*.toml")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.reduce({%{}, %{}}, fn path, {assigns, errors} ->
      stem = path |> Path.basename() |> Path.rootname(".toml")
      key = String.to_atom(stem)

      if Map.has_key?(assigns, key) do
        errors =
          Map.update(errors, :toml_duplicate, [path], fn existing -> [path | existing] end)

        {assigns, errors}
      else
        case File.read(path) do
          {:ok, content} ->
            case Toml.decode(content) do
              {:ok, data} ->
                {Map.put(assigns, key, normalize_toml_data(stem, data)), errors}

              {:error, reason} ->
                errors =
                  Map.update(errors, :toml_parse, [{path, reason}], fn existing ->
                    [{path, reason} | existing]
                  end)

                {assigns, errors}
            end

          {:error, reason} ->
            errors =
              Map.update(errors, :toml_read, [{path, reason}], fn existing ->
                [{path, reason} | existing]
              end)

            {assigns, errors}
        end
      end
    end)
    |> case do
      {assigns, errors} when map_size(errors) == 0 -> {:ok, assigns}
      {_assigns, errors} -> {:error, errors}
    end
  end

  defp normalize_toml_data(stem, data) when is_map(data) do
    if map_size(data) == 1 and Map.has_key?(data, stem) do
      Map.get(data, stem)
    else
      data
    end
  end
end
