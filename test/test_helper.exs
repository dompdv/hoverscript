defmodule TestHelpers do
  alias Hoverscript.Parser.Parse

  @doc """
  Parse Hoverscript input and return the AST.

  Returns {:ok, ast} or {:error, errors, ast}
  """
  def parse(input) do
    Parse.parse(input)
  end

  @doc """
  Parse Hoverscript input and return the AST, failing if there are errors.

  Useful for tests that expect successful parsing.
  """
  def parse!(input) do
    case parse(input) do
      {:ok, ast} ->
        ast

      {:error, errors, _ast} ->
        raise "Parsing failed with errors: #{inspect(errors)}"
    end
  end

  @doc """
  Extract the error map from a parse result tuple.
  """
  def parse_errors({:error, errors, _ast}), do: errors
  def parse_errors(_), do: %{}

  @doc """
  Extract the AST from a parse result, including partial AST on error.
  """
  def parse_ast({:ok, ast}), do: ast
  def parse_ast({:error, _errors, ast}), do: ast

  @doc """
  Recursively walk the AST and collect all nodes.
  """
  def walk_nodes(node, acc \\ [])

  def walk_nodes(nodes, acc) when is_list(nodes) do
    Enum.reduce(nodes, acc, &walk_nodes/2)
  end

  def walk_nodes(%{type: _} = node, acc) do
    acc = [node | acc]
    acc = if Map.has_key?(node, :children), do: walk_nodes(node.children, acc), else: acc
    acc = if Map.has_key?(node, :nested), do: walk_nodes(node.nested, acc), else: acc
    acc = if Map.has_key?(node, :blocks), do: walk_nodes(node.blocks, acc), else: acc

    if Map.has_key?(node, :items) and is_list(node.items) do
      walk_nodes(node.items, acc)
    else
      acc
    end
  end

  def walk_nodes(_other, acc), do: acc

  @doc """
  Get all nodes of a given type from the document AST (recursive).
  """
  def get_children(ast, type) do
    ast
    |> walk_nodes()
    |> Enum.filter(fn child -> child.type == type end)
    |> Enum.reverse()
  end

  @doc """
  Get the first node of type from the document AST (recursive).
  """
  def get_first_child(ast, type) do
    Enum.find(get_children(ast, type), fn child -> child.type == type end)
  end

  @doc """
  Filter out blank-line literal nodes from a blocks list.
  """
  def content_blocks(blocks) when is_list(blocks) do
    Enum.filter(blocks, fn block -> block.type != :literal end)
  end

  def content_blocks(_), do: []

  @doc """
  Get direct children of the document AST of a given type (non-recursive).
  """
  def get_top_level_children(ast, type) do
    Enum.filter(ast.children, fn child -> child.type == type end)
  end

  @doc """
  Get the first direct child of the document AST of a given type (non-recursive).
  """
  def get_top_level_child(ast, type) do
    Enum.find(ast.children, fn child -> child.type == type end)
  end

  @doc """
  Extract text content from an AST node.
  """
  def extract_text(node) do
    cond do
      Map.has_key?(node, :joined_lines) and node.joined_lines != "" ->
        String.trim(node.joined_lines)

      Map.has_key?(node, :body) and is_binary(node.body) ->
        String.trim(node.body)

      node.raw_lines ->
        node.raw_lines
        |> Enum.map(fn
          {:line, _, text} -> text
          {_, _, text} -> text
        end)
        |> Enum.join(" ")
        |> String.trim()

      true ->
        ""
    end
  end

  @doc """
  Create a simple paragraph AST node for testing.
  """
  def simple_para(content, line_number \\ 0) do
    %{
      type: :para,
      stage: :lines,
      line_number: line_number,
      raw_lines: [{:line, line_number, content}],
      options: %{},
      optionline: nil,
      tag_expr: ""
    }
  end

  @doc """
  Create a simple heading AST node for testing.
  """
  def simple_heading(level, content, line_number \\ 0) do
    %{
      type: :heading,
      stage: :lines,
      line_number: line_number,
      level: level,
      raw_lines: [{:line, line_number, content}],
      options: %{},
      optionline: nil,
      tag_expr: ""
    }
  end

  @doc """
  Create a minimal document AST with given children.
  """
  def minimal_document(children) do
    %{
      type: :document,
      stage: :children,
      line_number: 0,
      children: children
    }
  end
end
