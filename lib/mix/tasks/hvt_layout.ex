defmodule Mix.Tasks.HvtLayout do
  @moduledoc """
  Formats `.hvt` files in a directory using the Hoverscript layout engine.

  Each file is parsed first. Files with parse errors are skipped and reported.
  Files that parse successfully are formatted and written back in place when
  the output differs from the source.

  ## Usage

      mix hvt_layout
      mix hvt_layout examples
      mix hvt_layout doc --width 80 --column 8 --step 2

  ## Options

    * `--width` - maximum line width (default: 100)
    * `--column` - tag column width (default: 10)
    * `--step` - indentation spaces per level (default: 3)
  """

  use Mix.Task

  @shortdoc "Format .hvt files in a directory"

  @switches [
    width: :integer,
    column: :integer,
    step: :integer
  ]

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] do
      Mix.raise("invalid arguments: #{inspect(invalid)}")
    end

    dir = positional |> List.first() |> default_dir() |> Path.expand()
    format_opts = build_format_opts(opts)

    unless File.dir?(dir) do
      Mix.raise("not a directory: #{dir}")
    end

    files = dir |> Path.join("**/*.hvt") |> Path.wildcard() |> Enum.sort()

    if files == [] do
      Mix.shell().info("No .hvt files found in #{dir}")
    else
      results = Enum.map(files, &process_file(&1, format_opts))
      print_summary(results, dir)
      report_exit_status(results)
    end
  end

  defp default_dir(nil), do: "."
  defp default_dir(path), do: path

  defp build_format_opts(opts) do
    for key <- [:width, :column, :step], value <- [opts[key]], not is_nil(value) do
      {key, value}
    end
  end

  defp process_file(path, format_opts) do
    try do
      case Hoverscript.parse_file(path) do
        {:ok, ast} ->
          formatted = Hoverscript.format_ast(ast, format_opts)

          case write_if_changed(path, formatted) do
            :written -> {:ok, path, :written}
            :unchanged -> {:ok, path, :unchanged}
            {:error, reason} -> {:write_error, path, reason}
          end

        {:error, %{file: reason}, _} ->
          {:read_error, path, reason}

        {:error, errors, _ast} ->
          {:parse_error, path, errors}
      end
    rescue
      exception ->
        {:crash, path, Exception.format(:error, exception, __STACKTRACE__)}
    end
  end

  defp write_if_changed(path, content) do
    case File.read(path) do
      {:ok, existing} ->
        if existing == content do
          :unchanged
        else
          case File.write(path, content) do
            :ok -> :written
            {:error, reason} -> {:error, reason}
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp print_summary(results, dir) do
    shell = Mix.shell()

    shell.info("Scanned #{length(results)} .hvt file(s) in #{dir}\n")

    Enum.each(results, fn
      {:ok, path, :written} ->
        shell.info("[ok] #{path} (formatted)")

      {:ok, path, :unchanged} ->
        shell.info("[ok] #{path} (unchanged)")

      {:parse_error, path, errors} ->
        shell.error("[error] #{path} (parse errors)")

        for line <- format_parse_errors(errors) do
          shell.error("  #{line}")
        end

      {:read_error, path, reason} ->
        shell.error("[error] #{path} (read failed: #{inspect(reason)})")

      {:write_error, path, reason} ->
        shell.error("[error] #{path} (write failed: #{inspect(reason)})")

      {:crash, path, message} ->
        shell.error("[error] #{path} (unexpected error)")

        for line <- String.split(message, "\n", trim: true) do
          shell.error("  #{line}")
        end
    end)

    counts = Enum.frequencies_by(results, &result_kind/1)

    shell.info("")

    shell.info(
      "Summary: #{Map.get(counts, :ok, 0)} succeeded, " <>
        "#{Map.get(counts, :parse_error, 0)} parse error(s), " <>
        "#{Map.get(counts, :read_error, 0)} read error(s), " <>
        "#{Map.get(counts, :write_error, 0)} write error(s), " <>
        "#{Map.get(counts, :crash, 0)} unexpected error(s)"
    )
  end

  defp result_kind({:ok, _, _}), do: :ok

  defp result_kind({kind, _, _})
       when kind in [:parse_error, :read_error, :write_error, :crash],
       do: kind

  defp report_exit_status(results) do
    if Enum.any?(results, fn result -> result_kind(result) != :ok end) do
      System.halt(1)
    end
  end

  defp format_parse_errors(errors) when is_map(errors) do
    for {category, records} <- errors,
        record <- List.wrap(records),
        line <- [format_error_record(category, record)] do
      line
    end
  end

  defp format_error_record(category, record) do
    "#{category}: #{inspect(record)}"
  end
end
