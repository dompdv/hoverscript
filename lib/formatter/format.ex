defmodule Hoverscript.Formatter.Format do
  @moduledoc """
  This module transforms the AST into a text representation that follows a format.
  - There is a column on the left that contains the name of the node.
  - There is an automatic indentation for each child node.
  - The text is automatically wrapped to fit the maximum width.
  """

  # Global default options
  # Width: the maximum width of the text
  # Column: the width of the column on the left where the tags are
  # Step: the number of spaces to indent for each level of indentation
  @default_opts [width: 100, column: 10, step: 3]

  # The entry point of the module. It takes an AST and output a text representation
  # This function should be idempotent (calling it on the output of itself should not change the output)
  def format(node, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)

    # Put on the stack the current node type and the current level of indentation (0 for the root node), and the current level of right indentation (0 for the root node)
    %{type: node_type} = node
    apply_format = format(node, [{node_type, 0, 0}], opts) |> String.trim_trailing("\n")

    # Alway add a blankline at the end
    apply_format <> "\n\n"
  end

  #### The format function for :document node
  def format(%{type: :document} = node, stack, opts) do
    # Iterate over the children of the document
    # No additional indentation for the nodes inside the root node
    process_blocks(node.children, stack, opts, 0, 0)
  end

  #### The format function for :literal node
  # :literal nodes are node that should be printed "as is"
  def format(%{type: :literal, raw_lines: [{:blankline, _, _str}]}, _, _), do: "\n"
  def format(%{type: :literal, raw_lines: [{:optionline, _, str}]}, _, _), do: str <> "\n"

  # In the case of a :continueline, we take the indentation into account and "clean" the line
  def format(%{type: :literal, raw_lines: [{:continueline, _, _str}]}, stack, opts) do
    column = Keyword.fetch!(opts, :column)
    step = Keyword.fetch!(opts, :step)

    String.duplicate(" ", sum_left_indent(stack, step) + column) <>
      ":+\n"
  end

  #### The format function for :para node
  def format(%{type: tag} = node, stack, opts) when tag in [:para, :title] do
    alignment = Map.get(node.options, :align, "justify") |> String.to_atom()
    column = Keyword.fetch!(opts, :column)
    step = Keyword.fetch!(opts, :step)
    width = Keyword.fetch!(opts, :width)
    %{tag_expr: tag_expr, joined_lines: text} = node

    process_optionline(node) <>
      text_format(
        text,
        tag_expr,
        column,
        sum_left_indent(stack, step),
        sum_right_indent(stack, step),
        width,
        alignment
      ) <> "\n"
  end

  #### The format function for :quote node
  def format(%{type: tag} = node, stack, opts) when tag in [:quote, :footnote, :slot] do
    add_right_indent = if tag == :quote, do: 1, else: 0
    add_left_indent = if tag == :slot, do: 0, else: 1
    column = Keyword.fetch!(opts, :column)
    step = Keyword.fetch!(opts, :step)
    width = Keyword.fetch!(opts, :width)
    %{tag_expr: tag_expr, body: text} = node
    left_indent = sum_left_indent(stack, step)
    right_indent = sum_right_indent(stack, step)

    node_text =
      process_optionline(node) <>
        text_format(text, tag_expr, column, left_indent, right_indent, width, :left) <>
        "\n" <>
        process_blocks(node.nested, stack, opts, add_left_indent, add_right_indent)

    if Map.has_key?(node, :closing_tag) do
      %{closing_tag: closing_tag} = node
      %{tag_expr: tag_expr, body: text} = node

      node_text <>
        process_optionline(closing_tag) <>
        text_format(text, tag_expr, column, left_indent, right_indent, width, :left) <>
        "\n"
    else
      node_text
    end
  end

  def format(%{type: :verbatim} = node, stack, opts) do
    column = Keyword.fetch!(opts, :column)
    step = Keyword.fetch!(opts, :step)
    width = Keyword.fetch!(opts, :width)
    %{tag_expr: tag_expr, body: text, raw_lines: raw_lines} = node
    left_indent = sum_left_indent(stack, step)
    right_indent = sum_right_indent(stack, step)

    node_text =
      process_optionline(node) <>
        text_format(text, tag_expr, column, left_indent, right_indent, width, :left) <>
        "\n" <>
        verbatim_format(raw_lines, column, left_indent) <> "\n"

    if Map.has_key?(node, :closing_tag) do
      %{closing_tag: closing_tag} = node
      %{tag_expr: tag_expr, body: text} = node

      node_text <>
        process_optionline(closing_tag) <>
        text_format(text, tag_expr, column, left_indent, right_indent, width, :left) <>
        "\n"
    else
      node_text
    end
  end

  #### The format function for :heading node
  def format(%{type: :heading} = node, stack, opts) do
    column = Keyword.fetch!(opts, :column)
    step = Keyword.fetch!(opts, :step)
    width = Keyword.fetch!(opts, :width)
    %{tag_expr: tag_expr, joined_lines: text} = node

    process_optionline(node) <>
      text_format(
        text,
        tag_expr,
        column,
        sum_left_indent(stack, step),
        sum_right_indent(stack, step),
        width,
        :left
      ) <>
      "\n" <> process_blocks(node.nested, stack, opts, 1, 0)
  end

  #### The format function for :ordered_list or bullet_list nodes
  def format(%{type: tag} = node, stack, opts) when tag in [:ordered_list, :bullet_list] do
    process_blocks(node.items, stack, opts, 0, 0)
  end

  #### The format function for list item nodes (:list or :num)
  def format(%{type: tag} = node, stack, opts) when tag in [:num, :list] do
    column = Keyword.fetch!(opts, :column)
    step = Keyword.fetch!(opts, :step)
    width = Keyword.fetch!(opts, :width)
    %{tag_expr: tag_expr, joined_lines: text} = node

    process_optionline(node) <>
      text_format(
        text,
        tag_expr,
        column,
        sum_left_indent(stack, step),
        sum_right_indent(stack, step),
        width,
        :left
      ) <>
      "\n" <>
      process_blocks(node.blocks, stack, opts, 0, 0) <>
      process_blocks(node.nested, stack, opts, 1, 0)
  end

  def format(%{type: :sep} = node, stack, opts) do
    column = Keyword.fetch!(opts, :column)
    step = Keyword.fetch!(opts, :step)
    width = Keyword.fetch!(opts, :width)
    %{tag_expr: tag_expr, body: text} = node

    process_optionline(node) <>
      text_format(
        text,
        tag_expr,
        column,
        sum_left_indent(stack, step),
        sum_right_indent(stack, step),
        width,
        :left
      ) <> "\n"
  end

  def format(_node, _stack, _opts) do
    raise "MISSING PARAGRAPH TYPE"
  end

  ######## Utility functions ########

  #### Process a list of blocks
  # - blocks: the list of blocks to process
  # - stack: the stack of node types and indentation levels
  # - opts: the options
  # - delta_indent: the number of indentation level to add to the current indentation level
  # - delta_indent_right: the number of right indentation level to add to the current indentation level

  def process_blocks(blocks, stack, opts, delta_indent, delta_indent_right, sep \\ "") do
    for(
      block <- blocks,
      do: format(block, [{block.type, delta_indent, delta_indent_right} | stack], opts)
    )
    |> Enum.join(sep)
  end

  #### Process the [option] line of a node
  # Reformat the options nicely
  def process_optionline(node) do
    if Map.has_key?(node, :optionline) and node.optionline != nil do
      {_, _, %{options: options}} = node.optionline
      process_options(options)
    else
      ""
    end
  end

  #### Reformats the options
  def process_options(options) do
    option_text =
      for({option, value} <- options, option != :tag, do: "#{option}=#{value}")
      |> Enum.join(", ")

    "[#{option_text}]\n"
  end

  #### Compute the indentation level of the current node, adding the indentation deltas of the stack
  def sum_left_indent(stack, step) do
    Enum.reduce(stack, 0, fn {_, indent, _}, acc -> acc + indent * step end)
  end

  def sum_right_indent(stack, step) do
    Enum.reduce(stack, 0, fn {_, _, indent}, acc -> acc + indent * step end)
  end

  #### Format a verbatim text
  def count_trailing_spaces(s), do: String.length(s) - String.length(String.trim_trailing(s))

  def verbatim_format(raw_lines, column, indent) do
    # We want to preserve the relative indentation
    # So we first trim the line and keep the number of spaces trimmed
    trimmed_lines =
      for {:line, _, line} <- raw_lines do
        trimmed_line = String.trim_leading(line)
        trimmed_length = String.length(trimmed_line)
        # the blank lines are excluded from the computation
        if trimmed_length == 0,
          do: {trimmed_line, :blank},
          else: {trimmed_line, String.length(line) - trimmed_length}
      end

    # the min_trimmed represents the spaces that we can remove from all lines so that
    # the leftmost line is on column 0
    min_trimmed =
      trimmed_lines
      |> Enum.map(&elem(&1, 1))
      |> Enum.reject(&(&1 == :blank))
      |> Enum.min()

    for {line, trimmed_by} <- trimmed_lines do
      if trimmed_by == :blank,
        do: "",
        else: String.duplicate(" ", column + indent + trimmed_by - min_trimmed) <> line
    end
    |> Enum.join("\n")
  end

  #### Format a text to fit in a given width
  def text_format("", tag, _column_width, _indent, _right_ident, _body_width, _alignment), do: tag

  # Parameters
  # - string: the string to format
  # - tag: the tag of the node
  # - column_width: the width of the left column
  # - indent: the indentation level (in number of spaces)
  # - right_indent: the right indentation level (in number of spaces)
  # - body_width: the width of the body of the text
  def text_format(string, tag, column_width, indent, right_indent, body_width, alignment) do
    tag = if tag == "", do: "", else: tag <> " "
    # wrap the body, then add the tag and the indentation
    # the strange string (":_$:?:_$: ") is used to mark the linebreaks
    actual_width = body_width - indent - right_indent

    string
    |> String.replace("::\n", " :_$:?:_$: ")
    |> String.replace(["\n", "\t"], " ")
    |> wrap(actual_width)
    |> align(alignment, actual_width)
    |> Enum.with_index()
    |> Enum.reduce([], fn {line, index}, acc ->
      if index == 0,
        do: [
          tag <>
            String.duplicate(" ", max(0, column_width + indent - String.length(tag))) <> line
          | acc
        ],
        else: [String.duplicate(" ", column_width + indent) <> line | acc]
    end)
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  #### Align the text
  def align(lines, :left, _width), do: lines

  def align(lines, :right, width) do
    new_width = max(width, for(line <- lines, do: String.length(line)) |> Enum.max())
    for line <- lines, do: String.duplicate(" ", new_width - String.length(line)) <> line
  end

  def align(lines, :center, width) do
    new_width = max(width, for(line <- lines, do: String.length(line)) |> Enum.max())

    for(line <- lines, do: String.duplicate(" ", div(new_width - String.length(line), 2)) <> line)
  end

  def align(lines, :justify, _width), do: lines

  #### Wraps a string to a given width
  # Spliting the string by words
  # Do not cut [:tag:] inlines
  def split(str) do
    # Split by [:label: xxx]++
    str
    |> String.split(~r/\[:([a-zA-Z_]+):(.*)\]\+\+/, include_captures: true)
    |> Enum.map(fn
      s ->
        if String.starts_with?(s, "[:") and String.ends_with?(s, "++"),
          do: s,
          else: String.split(s, ~r/\[:([a-zA-Z_]+):(.*)\]/, include_captures: true)
    end)
    |> List.flatten()
    |> Enum.map(fn
      "[:" <> _ = s -> s
      s -> String.split(s, ~r/\s/, trim: true)
    end)
    |> List.flatten()
  end

  def wrap(string, max_line_length) do
    # Split by words
    [word | rest] = split(string)
    lines_assemble(rest, max_line_length, String.length(word), [word], [])
  end

  # no more words to process
  defp lines_assemble([], _, _, line, acc),
    do: [line |> Enum.reverse() |> Enum.join(" ") | acc] |> Enum.reverse()

  # Process LineBreaks
  # using a special token ":_$:?:_$:" to mark the linebreaks
  # If we have a space before a linebreak, we remove it
  defp lines_assemble(["", ":_$:?:_$:" | rest], max, line_length, line, acc) do
    lines_assemble([":_$:?:_$:" | rest], max, line_length, line, acc)
  end

  # go to the next line
  defp lines_assemble([":_$:?:_$:" | rest], max, _line_length, line, acc) do
    text_line = ["::" | line] |> Enum.reverse() |> Enum.join(" ")
    lines_assemble(rest, max, 0, [], [text_line | acc])
  end

  # process one word
  defp lines_assemble([word | rest], max, line_length, line, acc) do
    l_word = String.length(word)

    if line_length + 1 + l_word > max do
      text_line = line |> Enum.reverse() |> Enum.join(" ")
      # if we exceed the size, then accumulate the line and start a new one
      lines_assemble(rest, max, l_word, [word], [text_line | acc])
    else
      # otherwise, add the word to the line
      lines_assemble(rest, max, line_length + 1 + l_word, [word | line], acc)
    end
  end
end
