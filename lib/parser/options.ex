defmodule Hoverscript.Parser.Options do
  alias Hoverscript.Parser.Tags

  # Parse option line according to the following tagline
  def check_option_lines_parameter(lines) do
    {lines, errors} = check_option_lines_parameter(lines, [], [])
    if errors != [], do: {:error, :bad_options, errors, lines}, else: {:ok, lines}
  end

  def check_option_lines_parameter([], acc, errors), do: {Enum.reverse(acc), Enum.reverse(errors)}

  def check_option_lines_parameter([{:optionline, line_number, raw_line, _options}], acc, errors) do
    check_option_lines_parameter([], [{:optionline, line_number, raw_line} | acc], [
      {:optionline_must_be_followed_by_tagline, {line_number, 0, line_number, 0}} | errors
    ])
  end

  # An optionline followed by a tagline is parsable, as we know the tag
  def check_option_lines_parameter(
        [
          {:optionline, line_number, raw_line, options},
          {:tagline, _, _, %{tag: tag}} = tagline | rest
        ],
        acc,
        errors
      ) do
    case Tags.parse_options(tag, options, raw_line) do
      {:ok, parsed} ->
        check_option_lines_parameter(
          [tagline | rest],
          [{:optionline, line_number, raw_line, Map.put(parsed, :tag, tag)} | acc],
          errors
        )

      {:error, error} ->
        # Find the columns of the first and last non-whitespace character
        l = String.length(raw_line)

        {first_character, last_character} =
          {l - String.length(String.trim_leading(raw_line)),
           String.length(String.trim_trailing(raw_line))}

        check_option_lines_parameter(
          [tagline | rest],
          [{:optionline, line_number, raw_line, %{}} | acc],
          [{error, {line_number, first_character, line_number, last_character}} | errors]
        )
    end
  end

  # An optionline not followed by a tagline is an error
  def check_option_lines_parameter(
        [{:optionline, line_number, raw_line, _options}, l | rest],
        acc,
        errors
      ) do
    check_option_lines_parameter([l | rest], [{:optionline, line_number, raw_line} | acc], [
      {:optionline_must_be_followed_by_tagline, {line_number, 0, line_number, 0}} | errors
    ])
  end

  def check_option_lines_parameter([line | rest], acc, errors),
    do: check_option_lines_parameter(rest, [line | acc], errors)

  # Parse an option line. An option line has the form [option1=val1, option2=val2, ...]
  def parse_options_line(str) do
    str
    |> String.trim()
    |> String.slice(1..-2//1)
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&parse_option/1)
  end

  # Parse an option line. An option inline has the form :tag:inline_options/
  def parse_options_inline(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&parse_option/1)
  end

  def parse_option(str) do
    case String.split(str, "=") do
      [identifier, value] ->
        {String.trim(identifier), String.trim(value)}

      # no value. An option is set to true
      _ ->
        {:no_value, str}
    end
  end
end
