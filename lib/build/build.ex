defmodule Hoverscript.Build do
  @moduledoc """
  Builds a Hoverscript project directory into a parsed AST.

  A project directory contains:

    * `main.hvt` (or a custom entry file) — the root Hoverscript document
    * `*.toml` — data files merged into EEx assigns (`site.toml` → `@site`)
    * `.hvt` partials referenced via `:import` directives or `import_hvt/2`

  ## Pipeline

  1. Load all TOML files into assigns
  2. Expand the entry file (EEx evaluation + recursive imports)
  3. Parse the expanded document
  4. Remap parse errors to original source files/lines

  ## Examples

      {:ok, ast, meta} = Hoverscript.build("examples/build_project")
      html = Hoverscript.ast_to_html(ast)

  ## Options

    * `:entry` — entry file relative to the project directory (default: `"main.hvt"`)
    * `:assigns` — extra EEx assigns merged on top of TOML data
    * `:dump_expanded` — when set to a file path, write the expanded HVT text there
  """

  alias Hoverscript.Build.Config
  alias Hoverscript.Build.Expand
  alias Hoverscript.Build.SourceMap
  alias Hoverscript.Parser.Parse

  @default_entry "main.hvt"

  @doc """
  Builds a Hoverscript project directory.

  Returns `{:ok, ast, meta}` on success where `meta` contains `:source_map`,
  `:expanded`, and `:assigns`.

  Returns `{:error, :expand, errors}` when expansion fails, or
  `{:error, :parse, errors, ast}` when parsing fails (partial AST included).
  """
  def run(project_dir, opts \\ []) do
    project_dir = Path.expand(project_dir)
    entry = Keyword.get(opts, :entry, @default_entry)
    extra_assigns = Keyword.get(opts, :assigns, %{})
    dump_path = Keyword.get(opts, :dump_expanded)

    with {:ok, toml_assigns} <- Config.load(project_dir),
         assigns <- Map.merge(toml_assigns, normalize_assigns(extra_assigns)),
         entry_path <- Path.join(project_dir, entry),
         :ok <- ensure_entry(entry_path),
         {:ok, expanded, source_map} <- Expand.run(project_dir, entry, assigns),
         :ok <- maybe_dump(dump_path, expanded),
         parse_result <- Parse.parse(expanded) do
      meta = %{
        source_map: source_map,
        expanded: expanded,
        assigns: assigns,
        project_dir: project_dir,
        entry: entry
      }

      case parse_result do
        {:ok, ast} ->
          {:ok, ast, meta}

        {:error, errors, ast} ->
          remapped = SourceMap.remap_errors(errors, source_map)
          {:error, :parse, remapped, ast}
      end
    else
      {:error, errors} when is_list(errors) ->
        {:error, :expand, errors}

      {:error, errors} when is_map(errors) ->
        {:error, :expand, format_config_errors(errors)}

      {:error, :expand, _} = error ->
        error
    end
  end

  defp ensure_entry(path) do
    if File.exists?(path), do: :ok, else: {:error, :expand, [{:entry_not_found, path}]}
  end

  @doc """
  Builds a project directory, raising `Hoverscript.BuildError` on failure.
  """
  def run!(project_dir, opts \\ []) do
    case run(project_dir, opts) do
      {:ok, ast, _meta} ->
        ast

      {:error, :expand, errors} ->
        raise Hoverscript.BuildError, reason: :expand, errors: errors

      {:error, :parse, errors, _ast} ->
        raise Hoverscript.BuildError, reason: :parse, errors: errors
    end
  end

  defp normalize_assigns(assigns) when is_map(assigns) do
    Map.new(assigns, fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
    end)
  end

  defp maybe_dump(nil, _expanded), do: :ok

  defp maybe_dump(path, expanded) do
    case File.write(path, expanded) do
      :ok -> :ok
      {:error, reason} -> {:error, :expand, [{:dump_failed, %{path: path, reason: reason}}]}
    end
  end

  defp format_config_errors(errors) do
    Enum.flat_map(errors, fn
      {:toml_parse, entries} ->
        for {path, reason} <- entries do
          {:toml_parse_error, %{file: path, reason: reason}}
        end

      {:toml_read, entries} ->
        for {path, reason} <- entries do
          {:toml_read_error, %{file: path, reason: reason}}
        end

      {:toml_duplicate, paths} ->
        for path <- paths do
          {:toml_duplicate, %{file: path}}
        end
    end)
  end
end
