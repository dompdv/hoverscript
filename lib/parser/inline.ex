defmodule Hoverscript.Parser.Inline do
  alias Hoverscript.Parser.Tagline

  def process_tree(%{type: :document} = document) do
    case process_node(document) do
      {:error, errors, node} ->
        {:error, :inline_error, errors |> List.flatten(), node}

      {:ok, _} = ast ->
        ast
    end
  end

  # Process all embedded text in nodes
  def process_node(node) do
    # Process text attached directly to the node
    {errors_joined_lines, node} =
      if Map.has_key?(node, :joined_lines),
        do: process_joined_lines(node),
        else: {[], node}

    # Process blocks embedded in the node (via the :blocks, :items or :nested keys)
    {errors_blocks, node} =
      Enum.reduce([:blocks, :items, :nested, :children], {[], node}, fn key, {errors, node} ->
        if Map.has_key?(node, key) do
          {block_errors, node} = process_blocks(node, key)
          {errors ++ block_errors, node}
        else
          {errors, node}
        end
      end)

    total_errors = errors_joined_lines ++ errors_blocks

    if total_errors != [],
      do: {:error, total_errors, node},
      else: {:ok, node}
  end

  # Process blocks embedded in the node (via the :blocks, :items or :nested keys)
  def process_blocks(node, key) do
    blocks = node[key]
    processed_block = Enum.map(blocks, &process_node/1)
    # Check if there are errors in the blocks
    errors = for {:error, error, _} <- processed_block, do: error

    # Extract blocks from the processed blocks
    blocks =
      processed_block
      |> Enum.map(fn
        {:ok, block} -> block
        {:error, _, block} -> block
      end)

    {errors, Map.put(node, key, blocks)}
  end

  def process_joined_lines(node) do
    lines = node[:joined_lines]

    case parse_string(lines) do
      {:ok, parsed_lines} ->
        {[], Map.put(node, :inlines, parsed_lines)}

      {:error, error} ->
        {line_number, column, error} = process_error(error, node)

        {[{error, {line_number, column, line_number, column}}],
         Map.put(node, :inlines, [{:string, lines}])}
    end
  end

  #### ERROR PROCESSING ####

  def process_error({:unclosed_tags, _tack} = error, node) do
    # Indicate the error at the end of the paragraph
    {:line, line_number, t} = List.last(node[:raw_lines])
    {line_number, String.length(t), error}
  end

  def process_error({:unclosed_eex_tag, _l} = error, node) do
    # Indicate the error at the end of the paragraph
    {:line, line_number, t} = List.last(node[:raw_lines])
    {line_number, String.length(t), error}
  end

  def process_error({error, tag, stack, local_line, column}, node) do
    # Convert local line to global line
    line_number = node[:line_number] + local_line - 1

    # The "column" is the character number in the joined_lines. So we have to remove the length of the previous lines
    previous_line_lengths =
      for {:line, n, t} <- node[:raw_lines], n < line_number, do: String.length(t)

    column =
      if previous_line_lengths != [],
        # removing also the "\n" at the end of each previous line
        do: column - Enum.sum(previous_line_lengths) - length(previous_line_lengths),
        else: column

    {line_number, column, {error, tag, stack}}
  end

  #### PARSING OF A STRING TO CREATE THE INLINE STRUCTURE ####

  def tokenize(str), do: str |> String.graphemes() |> tokenize(1, [])

  # tokenize(grapheme list, line number, accumulator)
  def tokenize([], _, acc), do: Enum.reverse(acc)

  # EEx tags (<% %>)
  def tokenize(["<", "%" | r], n, acc) do
    # swallow everything till "%>"
    {rest, eex_tag} = get_eex_tag(r, n)
    tokenize(rest, n, [eex_tag | acc])
  end

  # Option tag
  def tokenize(["[", ":" | r], n, acc) do
    # swallow everything till "]"
    {rest, options} = get_options(r, n)
    tokenize(rest, n, [options | acc])
  end

  def tokenize(["+", "+" | r], n, acc), do: tokenize(r, n, [{:options_text, n} | acc])

  def tokenize(["/", "/" | r], n, acc), do: tokenize(r, n, [{:emph, n} | acc])
  def tokenize(["_", "_" | r], n, acc), do: tokenize(r, n, [{:underline, n} | acc])
  def tokenize(["*", "*" | r], n, acc), do: tokenize(r, n, [{:strong, n} | acc])
  def tokenize(["~", "~" | r], n, acc), do: tokenize(r, n, [{:strikeout, n} | acc])
  def tokenize(["^", "^" | r], n, acc), do: tokenize(r, n, [{:superscript, n} | acc])
  def tokenize([",", "," | r], n, acc), do: tokenize(r, n, [{:subscript, n} | acc])

  def tokenize([":", ":", "\n" | r], n, acc), do: tokenize(r, n, [{:linebreak, n} | acc])

  def tokenize(["\n" | r], n, acc), do: tokenize(r, n + 1, [{:char, n, "\n"} | acc])
  # Any other char
  def tokenize([c | r], n, acc), do: tokenize(r, n, [{:char, n, c} | acc])

  def parse_string(str) do
    tokens = tokenize(str)

    case list_of_inlines(tokens, [], []) do
      {:ok, _} = inlines ->
        inlines

      {:error, {:closing_bad_tag, tag, stack, local_line, residual_length}} ->
        {:error, {:closing_bad_tag, tag, stack, local_line, find_column(tokens, residual_length)}}

      {:error, _} = error ->
        error
    end
  end

  # Convert the tokens to a number of characters, from the number of remaining tokens
  def find_column(tokens, residual_length) do
    to_keep = length(tokens) - residual_length
    chars = tokens |> Enum.take(to_keep) |> Enum.count(fn t -> elem(t, 0) == :char end)
    2 * to_keep - chars
  end

  # list_of_inlines(tokens, stack of tags, accumulator)
  # returns : {rest of tokens, accumulator} if the tokens are not consumed
  # returns : {:ok, parsed_string} if all tokens are consumed and there is no error
  # returns : {:error, error} if there is an error
  # error can be: {:unclosed_tags, stack of unclosed tags}
  #             {:closing_bad_tag, tag, stack of tags, rest of tokens}
  #             {:bad_options, line number, options}
  def list_of_inlines([], [], acc) do
    {:ok, Enum.reverse(acc)}
  end

  # If there are still unclosed tags, it is an error
  def list_of_inlines([], l, _acc) do
    {:error, {:unclosed_tags, l}}
  end

  def list_of_inlines([{:bad_eex_tag, _, _} | _], l, _acc) do
    {:error, {:unclosed_eex_tag, l}}
  end

  # If the first token is a char, we get the string and continue
  def list_of_inlines([{:char, _, _} | _] = tokens, stack, acc) do
    {rest, str} = get_string(tokens)
    list_of_inlines(rest, stack, [{:string, str} | acc])
  end

  # Eex tag management
  def list_of_inlines([{:eex_tag, _, _} = tag | r], stack, acc) do
    list_of_inlines(r, stack, [tag | acc])
  end

  # Line break management
  def list_of_inlines([{:linebreak, _} | r], stack, acc) do
    list_of_inlines(r, stack, [:linebreak | acc])
  end

  # Options management

  # Options followed by a ++text++
  def list_of_inlines([{:options, line, options}, {:options_text, _} | r], stack, acc) do
    # Parsing the options
    case Tagline.parse_inline_tag(options) do
      {:error, %{error: error, tag_name: tag}} ->
        {:error, {error, tag, stack, line, length(r)}}

      parsed_options ->
        case list_of_inlines(r, [{:options_text, parsed_options} | stack], []) do
          # If there is an error, propagate it up
          {:error, _} = error ->
            error

          # else add the tag to the accumulator and continue
          {rest, tag_acc} ->
            list_of_inlines(rest, stack, [{:options, parsed_options, tag_acc} | acc])
        end
    end
  end

  # Options not followed by a ++text++
  def list_of_inlines([{:options, line, options} | r], stack, acc) do
    # Parsing the options
    case Tagline.parse_inline_tag(options) do
      {:error, %{error: error, tag_name: tag}} ->
        {:error, {error, tag, stack, line, length(r)}}

      parsed_options ->
        list_of_inlines(r, stack, [{:options, parsed_options, []} | acc])
    end
  end

  # End of the ++text++ after an option
  def list_of_inlines([{:options_text, _} | r], [{:options_text, _options} | _stack], acc) do
    {r, Enum.reverse(acc)}
  end

  # End of the ++text++ if not in an option : it is an error
  def list_of_inlines([{:options_text, line} | r], stack, _acc) do
    {:error, {:dangling_options_text, :options_text, stack, line, length(r)}}
  end

  # Other markers (strong, etc)
  def list_of_inlines([{tag, line} | r], stack, acc) do
    cond do
      # If the tag is at the to of the stack, then it is a closing tag, we can return
      stack != [] and tag == hd(stack) ->
        {r, Enum.reverse(acc)}

      # If the tag is not in the stack, then it is the start of a new tag
      tag not in stack ->
        # Process the inside of the tag, which is a list of inlines
        case list_of_inlines(r, [tag | stack], []) do
          # If there is an error, propagate it up
          {:error, _} = error -> error
          # else add the tag to the accumulator and continue
          {rest, tag_acc} -> list_of_inlines(rest, stack, [{tag, tag_acc} | acc])
        end

      # The tag is already in the stack, it is an error, as we can not nest a tag inside the *same* tag
      true ->
        {:error, {:closing_bad_tag, tag, stack, line, length(r)}}
    end
  end

  # Get a string from a consecutive list of char tokens
  def get_string(tokens), do: get_string(tokens, [])

  def get_string([{:char, _, char} | r], acc) do
    get_string(r, [char | acc])
  end

  def get_string(r, acc) do
    {r, acc |> Enum.reverse() |> Enum.join()}
  end

  #### OPTIONS PROCESSING ####
  def eat_til_end_of_options(["]" | r], acc), do: {r, Enum.reverse(acc)}
  def eat_til_end_of_options([c | r], acc), do: eat_til_end_of_options(r, [c | acc])
  def eat_til_end_of_options([], acc), do: {:not_found, Enum.reverse(acc)}

  # Get the string of options, and return the rest of the tokens
  def get_options(r, n) do
    {rest, c} = eat_til_end_of_options(r, [])
    options_text = Enum.join([":" | c])

    cond do
      rest == :not_found ->
        {[], {:bad_options, n, options_text}}

      true ->
        {rest, {:options, n, options_text}}
    end
  end

  #### EEX TAGS PROCESSING ####
  def eat_til_end_of_eex_tag(["%", ">" | r], acc), do: {r, Enum.reverse([">", "%" | acc])}
  def eat_til_end_of_eex_tag([c | r], acc), do: eat_til_end_of_eex_tag(r, [c | acc])
  def eat_til_end_of_eex_tag([], acc), do: {:not_found, Enum.reverse(acc)}

  def get_eex_tag(r, n) do
    {rest, c} = eat_til_end_of_eex_tag(r, [])
    eex_tag = Enum.join(["<", "%" | c])

    cond do
      rest == :not_found ->
        {[], {:bad_eex_tag, n, eex_tag}}

      true ->
        {rest, {:eex_tag, n, eex_tag}}
    end
  end
end
