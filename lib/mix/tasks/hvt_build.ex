defmodule Mix.Tasks.HvtBuild do
  @moduledoc """
  Builds a Hoverscript project directory (TOML + imports + EEx → parse).

  ## Usage

      mix hvt_build examples/build_project
      mix hvt_build examples/build_project --entry index.hvt
      mix hvt_build examples/build_project --dump-expanded /tmp/out.hvt
      mix hvt_build examples/build_project --html

  ## Options

    * `--entry` - entry file relative to the project directory (default: `main.hvt`)
    * `--dump-expanded` - write the expanded HVT text to this path
    * `--html` - print HTML to stdout after a successful build
  """

  use Mix.Task

  @shortdoc "Build a Hoverscript project directory"

  @switches [
    entry: :string,
    dump_expanded: :string,
    html: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] do
      Mix.raise("invalid arguments: #{inspect(invalid)}")
    end

    dir = positional |> List.first() |> default_dir() |> Path.expand()

    unless File.dir?(dir) do
      Mix.raise("not a directory: #{dir}")
    end

    build_opts =
      [
        entry: opts[:entry],
        dump_expanded: opts[:dump_expanded]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    Mix.shell().info("Building #{dir}...")

    case Hoverscript.build(dir, build_opts) do
      {:ok, ast, meta} ->
        Mix.shell().info("Build succeeded (#{line_count(meta.expanded)} expanded lines).")

        if opts[:html] do
          Mix.shell().info(Hoverscript.ast_to_html(ast))
        end

      {:error, :expand, errors} ->
        Mix.shell().error("Expansion failed:")
        print_errors(errors)
        System.halt(1)

      {:error, :parse, errors, _ast} ->
        Mix.shell().error("Parse failed:")
        print_parse_errors(errors)
        System.halt(1)
    end
  end

  defp default_dir(nil), do: "."
  defp default_dir(path), do: path

  defp line_count(text), do: text |> String.split("\n") |> length()

  defp print_errors(errors) do
    for error <- List.wrap(errors) do
      Mix.shell().error("  #{format_error(error)}")
    end
  end

  defp print_parse_errors(errors) when is_map(errors) do
    for {category, records} <- errors,
        record <- List.wrap(records) do
      Mix.shell().error("  #{category}: #{inspect(record)}")
    end
  end

  defp format_error({:entry_not_found, path}), do: "entry file not found: #{path}"

  defp format_error({:file_not_found, details}) do
    "file not found: #{details.path} (#{inspect(details.reason)})"
  end

  defp format_error({:import_cycle, details}) do
    "import cycle at #{details.file} importing #{details.import}"
  end

  defp format_error({:eex_error, details}) do
    "EEx error in #{details.file}:#{details.line}: #{details.reason}"
  end

  defp format_error({:toml_parse_error, details}) do
    "TOML parse error in #{details.file}: #{inspect(details.reason)}"
  end

  defp format_error({:toml_read_error, details}) do
    "TOML read error in #{details.file}: #{inspect(details.reason)}"
  end

  defp format_error({:dump_failed, details}) do
    "failed to write expanded file #{details.path}: #{inspect(details.reason)}"
  end

  defp format_error(other), do: inspect(other)
end
