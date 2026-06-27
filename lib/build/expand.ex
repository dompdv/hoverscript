defmodule Hoverscript.Build.Expand do
  @moduledoc false

  alias Hoverscript.Build.SourceMap
  alias Hoverscript.Parser.Options

  @ctx_key {__MODULE__, :ctx}

  @import_short ~r/^\s*:import[\s\t]+(\S+)\s*$/
  @import_long_path ~r/^\s*:import:([^:\/]+)\/\s*$/
  @import_long_params ~r/^\s*:import:([^:\/]+):([^\/]*)\/\s*$/
  @verbatim_open ~r/^\s*:verbatim(?::([^\/]*)\/)?\s*(.*)?\s*$/
  @verbatim_close ~r/^\s*:verbatim(?::([^\/]*)\/)?\s*$/

  defmodule State do
    @moduledoc false
    defstruct [
      :project_dir,
      :base_assigns,
      import_stack: [],
      source_map: SourceMap.new(),
      errors: []
    ]
  end

  @doc """
  Expands a project entry file into Hoverscript text and a source map.
  """
  def run(project_dir, entry_path, base_assigns) do
    state = %State{
      project_dir: Path.expand(project_dir),
      base_assigns: base_assigns,
      import_stack: [],
      source_map: SourceMap.new(),
      errors: []
    }

    canonical_entry = canonical_path(state, entry_path)

    case put_ctx(%{state | base_assigns: base_assigns}, fn ->
           expand_file(state, canonical_entry, base_assigns, canonical_entry)
         end) do
      {:ok, state} ->
        if state.errors == [] do
          {:ok, SourceMap.to_text(state.source_map), state.source_map}
        else
          {:error, Enum.reverse(state.errors)}
        end

      {:error, state} ->
        {:error, Enum.reverse(state.errors)}
    end
  end

  @doc false
  def import_hvt(path, params \\ []) when is_binary(path) do
    ctx = Process.get(@ctx_key)

    if is_nil(ctx) do
      raise "import_hvt/2 called outside of a Hoverscript build expansion"
    end

    params_map = normalize_params(params)
    lines_before = length(ctx.source_map.lines)

    case expand_import(ctx, path, params_map, ctx.base_assigns) do
      {:ok, state, _text} ->
        new_lines = Enum.drop(state.source_map.lines, lines_before)

        reverted_source_map = %{
          state.source_map
          | lines: Enum.take(state.source_map.lines, lines_before)
        }

        reverted = %{state | source_map: reverted_source_map}
        Process.put(@ctx_key, reverted)
        Enum.join(new_lines, "\n")

      {:error, state} ->
        Process.put(@ctx_key, state)
        ""
    end
  end

  defp put_ctx(%State{} = state, fun) do
    Process.put(@ctx_key, state)

    try do
      fun.()
    after
      Process.delete(@ctx_key)
    end
  end

  defp expand_file(state, canonical_path, assigns, source_file) do
    if canonical_path in state.import_stack do
      error =
        {:import_cycle,
         %{
           file: source_file,
           import: canonical_path,
           stack: Enum.reverse(state.import_stack)
         }}

      {:error, %{state | errors: [error | state.errors]}}
    else
      case File.read(canonical_path) do
        {:ok, content} ->
          state = %{state | import_stack: [canonical_path | state.import_stack]}

          case expand_content(state, content, assigns, canonical_path) do
            {:ok, state} ->
              {:ok, pop_import_stack(state)}

            {:error, state} ->
              {:error, pop_import_stack(state)}
          end

        {:error, reason} ->
          error = {:file_not_found, %{file: source_file, path: canonical_path, reason: reason}}
          {:error, %{state | errors: [error | state.errors]}}
      end
    end
  end

  defp pop_import_stack(%{import_stack: [_ | rest]} = state), do: %{state | import_stack: rest}
  defp pop_import_stack(state), do: state

  defp expand_content(state, content, assigns, source_file) do
    segments = split_segments(content)

    Enum.reduce_while(segments, {:ok, state}, fn segment, {:ok, state} ->
      case expand_segment(state, segment, assigns, source_file) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, state} -> {:halt, {:error, state}}
      end
    end)
  end

  defp expand_segment(state, {:verbatim, text, start_line}, _assigns, source_file) do
    lines = split_lines(text)
    source_map = SourceMap.append_lines(state.source_map, lines, source_file, start_line)
    {:ok, %{state | source_map: source_map}}
  end

  defp expand_segment(state, {:text, text, start_line}, assigns, source_file) do
    case eval_eex(text, assigns, source_file, start_line) do
      {:ok, expanded} ->
        expand_text_lines(state, expanded, assigns, source_file, start_line)

      {:error, reason} ->
        error = {:eex_error, %{file: source_file, line: start_line, reason: reason}}
        {:error, %{state | errors: [error | state.errors]}}
    end
  end

  defp eval_eex(text, assigns, source_file, start_line) do
    try do
      result =
        EEx.eval_string(
          text,
          [assigns: assigns],
          file: source_file,
          line: start_line + 1,
          trim: false
        )

      {:ok, result}
    rescue
      exception ->
        {:error, Exception.message(exception)}
    end
  end

  defp expand_text_lines(state, text, assigns, source_file, start_line) do
    lines = split_lines(text)
    do_expand_text_lines(lines, 0, state, assigns, source_file, start_line)
  end

  defp do_expand_text_lines(lines, index, state, _assigns, _source_file, _start_line)
       when index >= length(lines),
       do: {:ok, state}

  defp do_expand_text_lines(lines, index, state, assigns, source_file, start_line) do
    cond do
      option_import = parse_option_import_at(lines, index) ->
        case expand_import(state, option_import.path, option_import.params, assigns) do
          {:ok, state, _text} ->
            do_expand_text_lines(lines, index + 2, state, assigns, source_file, start_line)

          {:error, state} ->
            {:error, state}
        end

      true ->
        line = Enum.at(lines, index)
        source_line = start_line + index

        case parse_import(line) do
          {:import, path, params} ->
            case expand_import(state, path, params, assigns) do
              {:ok, state, _text} ->
                do_expand_text_lines(lines, index + 1, state, assigns, source_file, start_line)

              {:error, state} ->
                {:error, state}
            end

          :not_import ->
            source_map = SourceMap.append_line(state.source_map, line, source_file, source_line)

            do_expand_text_lines(
              lines,
              index + 1,
              %{state | source_map: source_map},
              assigns,
              source_file,
              start_line
            )
        end
    end
  end

  defp expand_import(state, path, params, base_assigns) do
    canonical = canonical_path(state, path)
    local_assigns = merge_assigns(base_assigns, params)
    lines_before = length(state.source_map.lines)

    case expand_file(state, canonical, local_assigns, canonical) do
      {:ok, state} ->
        new_lines = Enum.drop(state.source_map.lines, lines_before)
        {:ok, state, Enum.join(new_lines, "\n")}

      {:error, state} ->
        {:error, state}
    end
  end

  defp parse_option_import_at(lines, index) do
    with current when not is_nil(current) <- Enum.at(lines, index),
         true <- Regex.match?(~r/^\s*\[.*\]\s*$/, current),
         import_line when not is_nil(import_line) <- Enum.at(lines, index + 1),
         {:import, path, params0} <- parse_import(import_line) do
      option_params = parse_option_line(current)
      %{path: path, params: Map.merge(params0, option_params)}
    else
      _ -> nil
    end
  end

  defp parse_import(line) do
    cond do
      Regex.match?(@import_long_params, line) ->
        case Regex.run(@import_long_params, line) do
          [_, path, options_str] ->
            params = parse_import_options(options_str)
            {:import, normalize_import_path(path), params}

          _ ->
            :not_import
        end

      Regex.match?(@import_long_path, line) ->
        case Regex.run(@import_long_path, line) do
          [_, path] -> {:import, normalize_import_path(path), %{}}
          _ -> :not_import
        end

      Regex.match?(@import_short, line) ->
        case Regex.run(@import_short, line) do
          [_, path] -> {:import, normalize_import_path(path), %{}}
          _ -> :not_import
        end

      true ->
        :not_import
    end
  end

  defp parse_import_options(""), do: %{}

  defp parse_import_options(options_str) do
    options_str
    |> String.trim()
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce(%{}, fn option, acc ->
      case String.split(option, "=", parts: 2) do
        [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
        [key] -> Map.put(acc, String.trim(key), "true")
      end
    end)
  end

  defp parse_option_line(line) do
    line
    |> Options.parse_options_line()
    |> Enum.reduce(%{}, fn
      {key, value}, acc when is_binary(key) -> Map.put(acc, key, value)
      {:no_value, key}, acc -> Map.put(acc, key, "true")
    end)
  end

  defp normalize_import_path(path) when is_binary(path) do
    path
    |> String.trim()
    |> then(fn p ->
      if String.ends_with?(p, ".hvt"), do: p, else: p <> ".hvt"
    end)
  end

  defp normalize_params(params) when is_list(params) do
    params
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), to_string(v)}
      {k, v} when is_binary(k) -> {k, to_string(v)}
    end)
    |> Map.new()
  end

  defp merge_assigns(base, params) when is_map(params) do
    params_atoms =
      params
      |> Enum.map(fn
        {k, v} when is_binary(k) -> {String.to_atom(k), coerce_param(v)}
        {k, v} -> {k, coerce_param(v)}
      end)
      |> Map.new()

    Map.merge(base, params_atoms)
  end

  defp coerce_param(value) when is_binary(value), do: value
  defp coerce_param(value), do: value

  defp canonical_path(%State{project_dir: dir}, path) do
    path
    |> Path.expand(dir)
    |> Path.expand()
  end

  defp split_segments(content) do
    content
    |> split_lines()
    |> split_segments([], :normal, 0, [])
    |> Enum.reverse()
  end

  defp split_segments([], acc, _mode, line_no, segments) do
    case acc do
      [] -> segments
      _ -> flush_text(acc, line_no, segments)
    end
  end

  defp split_segments([line | rest], acc, :normal, line_no, segments) do
    if verbatim_open?(line) do
      segments = flush_text(acc, line_no, segments)
      collect_verbatim(rest, line, line_no + 1, [], segments)
    else
      split_segments(rest, [line | acc], :normal, line_no + 1, segments)
    end
  end

  defp collect_verbatim([line | rest], open_line, line_no, acc, segments) do
    if verbatim_close?(line, open_line) do
      text = Enum.reverse(acc) |> Enum.join("\n")
      split_segments(rest, [], :normal, line_no + 1, [{:verbatim, text, line_no} | segments])
    else
      collect_verbatim(rest, open_line, line_no + 1, [line | acc], segments)
    end
  end

  defp collect_verbatim([], _open_line, _line_no, acc, segments) do
    text = Enum.reverse(acc) |> Enum.join("\n")
    [{:verbatim, text, 0} | segments]
  end

  defp flush_text([], _line_no, segments), do: segments

  defp flush_text(acc, line_no, segments) do
    start_line = line_no - length(acc)
    text = acc |> Enum.reverse() |> Enum.join("\n")
    [{:text, text, start_line} | segments]
  end

  defp verbatim_open?(line), do: Regex.match?(@verbatim_open, line)

  defp verbatim_close?(line, open_line) do
    case {Regex.run(@verbatim_open, open_line), Regex.run(@verbatim_close, line)} do
      {[_, open_name, _], [_, close_name]} ->
        open_name == close_name

      _ ->
        Regex.match?(@verbatim_close, line)
    end
  end

  defp split_lines(text) when text == "", do: []

  defp split_lines(text) do
    String.split(text, "\n", parts: :infinity)
  end
end
