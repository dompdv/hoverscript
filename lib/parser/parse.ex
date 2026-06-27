defmodule Hoverscript.Parser.Parse do
  alias Hoverscript.Parser.Tagline
  alias Hoverscript.Parser.Options
  alias Hoverscript.Parser.ParseTokens
  alias Hoverscript.Parser.Inline

  # Blankline is a line with only spaces (or nothing)
  @blankline_regex ~r/^[\s\t]*$/u
  # An option line is like spaces[somthing]spaces
  @optionline_regex ~r/^[\s\t]*\[.*\][\s\t]*$/u
  # A bad option line is like [somthing]somethingelse
  @optionline_bad_regex ~r/^[\s\t]*\[.*\].*$/u
  @tagline_regex ~r/^[\s\t]*:.*$/u
  # A continue line is a lines like "  :+  "
  @breakline_regex ~r/^[\s\t]*::[\s\t]*$/u
  @continueline_regex ~r/^[\s\t]*:\+[\s\t]*$/u

  # Parse an Hoverscript document
  # The parsing happens in several steps:
  # 1- Tokenize  : Identify the type of each line (blank line, option line, tag line, normal line,...). Each line is a token
  #    (this is the tokenized_line function) (for example a tag line is parsed to identify the tag and the options)
  #    Each line returns first {type of line, raw line, line number, result of the parsing}.
  #    In case of an error, the result of the parsing a tuple of 2 elements {:error, error_description}
  #    At the end of the step, it returns {:ok, list of tokenized lines} or {:error, error_name, error_description}
  #
  # 2- Check the optionline parameters (indeed, it has to be done in a second pass, as the optionline depends on the NEXT line)
  #    Same return as Step 1
  #
  # 3- Build the syntax tree
  #         - Normalize each line in a tuple of 3 elements : the type of line, the line number, and the result of the initial parsing).
  #           Exception for the optionlines which are a 4-element tuple (optionlines are going to disappear just after)
  #           taglines are replaced according to a rule like {:tagline, line_number, %{tag: tag}=tag_description} -> {tag, line_number, tag_description}
  #         - Remove the optionline and add the options to the tagline (simplifying the parsing. Done by club_option_lines/1)
  #         - Parser itself, which build the AST
  #
  # 4- Process the inline text (bold, etc...)

  def parse(str) do
    acc_errors0 = %{}

    # step_1_line_tokenize -> no emitted error
    {:ok, tokenized_lines} = step_1_line_tokenize(str)
    acc_errors1 = acc_errors0

    # step_2_check_options_and_parameters -> {:error, :bad_options, errors}
    # Errors :
    # - {optionline_must_be_followed_by_tagline, {line_number_start, column_number_start, line_number_end, column_number_end}]
    # - {{:unauthorized_parameters, [parameter_names]}, {line_number_start, column_number_start, line_number_end, column_number_end}}
    # - {{:parameter_errors, [{:invalid_alignment, {:align, "tight"}, "tight"}], tag_line}, {line_number_start, column_number_start, line_number_end, column_number_end}}

    {checked_tokens, acc_errors2} =
      case step_2_check_options_and_parameters(tokenized_lines) do
        {:ok, lines} -> {lines, acc_errors1}
        {:error, error_type, errors, lines} -> {lines, Map.put(acc_errors1, error_type, errors)}
      end

    {cleaned_tokens, acc_errors3} =
      case step_3_identify_tagline_errors(checked_tokens) do
        {:ok, lines} -> {lines, acc_errors2}
        {:error, error_type, errors, lines} -> {lines, Map.put(acc_errors2, error_type, errors)}
      end

    {ast_without_inlines, acc_errors4} =
      case step_4_parse(cleaned_tokens) do
        {:ok, ast} -> {ast, acc_errors3}
        {:error, error_type, errors, ast} -> {ast, Map.put(acc_errors3, error_type, errors)}
      end

    {final_ast, accumulated_errors} =
      case step_5_parse_inlines(ast_without_inlines) do
        {:ok, ast_inlined} -> {ast_inlined, acc_errors4}
        {:error, error_type, errors, ast} -> {ast, Map.put(acc_errors4, error_type, errors)}
      end

    if accumulated_errors != %{},
      do: {:error, accumulated_errors, final_ast},
      else: {:ok, final_ast}
  end

  def step_1_line_tokenize(str) do
    {:ok,
     str
     |> String.split("\n")
     |> Enum.with_index()
     # Parse each line. The result per line is a tuple of 3 elements : the type of line, the raw line and the result of the parsing
     # the result of the parsing is a tuple of 2 elements : either (:ok, parsed string} or {:error, error_name, [error_descriptions], parsed_string}
     |> tokenize()}
  end

  def step_2_check_options_and_parameters(tokenized_lines) do
    tokenized_lines
    |> Options.check_option_lines_parameter()
  end

  def step_3_identify_tagline_errors(tokenized_lines) do
    {errors, lines} =
      tokenized_lines
      |> Enum.reduce(
        {[], []},
        fn
          {:tagline, line_number, raw_line, {:error, error}}, {errors, lines} ->
            {[{error, {line_number, 0, line_number, 0}} | errors],
             [{:line, line_number, raw_line} | lines]}

          line, {errors, lines} ->
            {errors, [line | lines]}
        end
      )

    if errors != [],
      do: {:error, :bad_tagline, errors, Enum.reverse(lines)},
      else: {:ok, tokenized_lines}
  end

  def step_4_parse(tokenized_lines) do
    tokenized_lines
    # Replace taglines with the tag name, creating lines like {:heading,_,_}
    |> Enum.map(fn
      {:tagline, line_number, raw_line, %{tag: tag} = tag_description} ->
        {tag, line_number,
         Map.put(tag_description, :raw_line, raw_line) |> Map.put(:optionline, nil)}

      {:optionline, line_number, str, options} ->
        {:optionline, line_number, %{string: str, options: options}}

      line ->
        line
    end)
    # Add the option line to the following tagline (simplifying the parsing) (and remove the optionline)
    |> club_option_lines()
    # The parsing itself
    |> ParseTokens.parse()
  end

  def step_5_parse_inlines(parsed) do
    parsed |> Inline.process_tree()
  end

  # Tokenize a list of lines. Each line is a tuple of 2 elements : the line and the line number
  # We can't do a simple Enum.map(@tokenize_line/1) because we have to handle the case of
  # Verbatim blocks
  # If we are within a Verbatim block, we don't parse the line, we just keep it as is, till we
  # find the closing verbatim tag

  def tokenize(lines), do: tokenize(lines, :normal, [])

  def tokenize([], _, acc), do: Enum.reverse(acc)

  def tokenize([line | rest], :normal, acc) do
    case tokenize_line(line) do
      # Switch mode to verbatim
      {:tagline, _, _, %{tag: :verbatim, options: %{name: identifier}}} = token ->
        tokenize(rest, {:verbatim, identifier}, [token | acc])

      # Staying in normal mode
      token ->
        tokenize(rest, :normal, [token | acc])
    end
  end

  # We are within a Verbatim block
  def tokenize([{text, line_number} = line | rest], {:verbatim, identifier} = mode, acc) do
    case tokenize_line(line) do
      # Switch back to normal if we encouter the closing verbatim tag (same identifier)
      {:tagline, _, _, %{tag: :verbatim, options: %{name: ^identifier}}} = token ->
        tokenize(rest, :normal, [token | acc])

      # otherwise, just accumulate ":line" tokens
      _ ->
        tokenize(rest, mode, [{:line, line_number, text} | acc])
    end
  end

  # tokenize a line. A line can be a blank line, an option line, a tag line or a normal line
  # It's a tuple of 3 elements : the type of line, the raw line and the result of the parsing
  # the result of the parsing is a tuple of 2 elements : either (:ok, parsed string} or {:error, error_desription}
  def tokenize_line({str, line_number}) do
    cond do
      Regex.match?(@breakline_regex, str) ->
        {:line, line_number, str}

      Regex.match?(@continueline_regex, str) ->
        {:continueline, line_number, str}

      Regex.match?(@blankline_regex, str) ->
        {:blankline, line_number, str}

      # Parse an option line. An option line has the form [option1=val1, option2=val2, ...]
      Regex.match?(@optionline_regex, str) ->
        {:optionline, line_number, str, Options.parse_options_line(str)}

      # Parse an option line. An option line has the form [option1=val1, option2=val2, ...]
      Regex.match?(@optionline_bad_regex, str) ->
        {:optionline, line_number, str, {:error, :bad_option_line}}

      # Parse a tag line. A tag line has the form either ":tag" or ":tag option1, option2/" or ":/"
      # THe parsing is done in another Module
      Regex.match?(@tagline_regex, str) ->
        {:tagline, line_number, str, Tagline.parse_tag_line(str)}

      # Parse a continueline. A continueline is a line like "  :+  "
      Regex.match?(@continueline_regex, str) ->
        {:continueline, line_number, str}

      true ->
        {:line, line_number, str}
    end
  end

  # Add the option line to the following tagline (simplifying the parsing)
  def club_option_lines(lines), do: club_option_lines(lines, [])

  def club_option_lines([], acc), do: Enum.reverse(acc)

  # nothing to do if the following line is not a tagline
  def club_option_lines([h, {tag, _, _} = n | r], acc)
      when tag in [:blankline, :continueline, :line, :optionline] do
    club_option_lines([n | r], [h | acc])
  end

  # if the current line is an option line, then the next one is a tagline (checked before)
  def club_option_lines([{:optionline, _, %{options: options1}} = optionline, tagline | r], acc) do
    {tag, index, %{options: options2} = tag_description} = tagline

    new_tagline =
      {tag, index,
       tag_description
       # Keeping the optionline just in case
       |> Map.put(:optionline, optionline)
       # Merging the options from the optionline with the options from the tagline
       # the optionline take the precedence on the options in the tagline (if there is a conflict)
       |> Map.put(:options, Map.merge(options2, options1))}

    # remove the optionline
    club_option_lines(r, [new_tagline | acc])
  end

  def club_option_lines([h | r], acc), do: club_option_lines(r, [h | acc])
end
