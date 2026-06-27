defmodule Hoverscript.Build.SourceMap do
  @moduledoc false

  def new do
    %{lines: [], mapping: %{}}
  end

  def to_text(%{lines: lines}), do: Enum.join(lines, "\n")

  def append_line(source_map, line, source_file, source_line) do
    index = length(source_map.lines)

    %{
      source_map
      | lines: source_map.lines ++ [line],
        mapping:
          Map.put(source_map.mapping, index, %{
            file: source_file,
            line: source_line
          })
    }
  end

  def append_lines(source_map, lines, source_file, source_line_start) do
    Enum.reduce(Enum.with_index(lines), source_map, fn {line, offset}, acc ->
      append_line(acc, line, source_file, source_line_start + offset)
    end)
  end

  def append_mapped(source_map, other) do
    base = length(source_map.lines)

    appended_lines = source_map.lines ++ other.lines

    appended_mapping =
      Enum.reduce(other.mapping, source_map.mapping, fn {index, location}, mapping ->
        Map.put(mapping, base + index, location)
      end)

    %{source_map | lines: appended_lines, mapping: appended_mapping}
  end

  def remap_errors(errors, source_map) when is_map(errors) do
    Map.new(errors, fn {category, records} ->
      {category, Enum.map(List.wrap(records), &remap_error_record(&1, source_map))}
    end)
  end

  def remap_errors(errors, _source_map), do: errors

  defp remap_error_record({error, {line, col_start, line_end, col_end}}, source_map) do
    {
      error,
      %{
        merged: {line, col_start, line_end, col_end},
        source: %{
          start: lookup(source_map, line),
          end: lookup(source_map, line_end)
        }
      }
    }
  end

  defp remap_error_record(other, _source_map), do: other

  defp lookup(source_map, line) do
    Map.get(source_map.mapping, line, %{file: nil, line: line})
  end
end
