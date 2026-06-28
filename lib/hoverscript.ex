defmodule Hoverscript do
  @moduledoc """
  Public API for parsing and converting Hoverscript documents.

  ## Parsing

      {:ok, ast} = Hoverscript.parse(":para Hello")
      ast = Hoverscript.parse!(":para Hello")
      {:ok, ast} = Hoverscript.parse_file("doc/doc_en.hvt")
      ast = Hoverscript.parse_file!("doc/doc_en.hvt")

  ## Formatting

      {:ok, text} = Hoverscript.format(":para Hello")
      text = Hoverscript.format!(":para Hello")
      text = Hoverscript.format_ast(ast, width: 80, column: 8, step: 2)

  ## HTML

      {:ok, html} = Hoverscript.text_to_html(":para Hello")
      html = Hoverscript.text_to_html!(":para Hello")
      html = Hoverscript.ast_to_html(ast)
      floki = Hoverscript.ast_to_floki(ast)
  """

  alias Hoverscript.Parser.Parse
  alias Hoverscript.Formatter.Format
  alias Hoverscript.Converter.ToHtml
  alias Hoverscript.Build

  @doc """
  Parses a Hoverscript document.

  Returns `{:ok, ast}` on success, or `{:error, errors, ast}` when parsing
  completes with accumulated errors (a partial AST is still returned).

  ## Examples

      iex> {:ok, ast} = Hoverscript.parse(":para Hello")
      iex> ast.type
      :document

  """
  def parse(text) when is_binary(text) do
    Parse.parse(text)
  end

  @doc """
  Parses a Hoverscript document, raising `Hoverscript.ParseError` on failure.

  ## Examples

      iex> ast = Hoverscript.parse!(":para Hello")
      iex> ast.type
      :document

  """
  def parse!(text) when is_binary(text) do
    case parse(text) do
      {:ok, ast} -> ast
      {:error, errors, _ast} -> raise Hoverscript.ParseError, errors: errors
    end
  end

  @doc """
  Reads and parses a Hoverscript file.

  Returns `{:error, %{file: reason}, nil}` when the file cannot be read.

  ## Examples

      iex> path = Path.join("examples", "short_test.hvt")
      iex> {:ok, ast} = Hoverscript.parse_file(path)
      iex> ast.type
      :document

  """
  def parse_file(path) do
    case File.read(path) do
      {:ok, content} -> parse(content)
      {:error, reason} -> {:error, %{file: reason}, nil}
    end
  end

  @doc """
  Reads and parses a Hoverscript file, raising on failure.

  File read errors raise `File.Error`. Parse errors raise `Hoverscript.ParseError`.
  """
  def parse_file!(path) do
    path |> File.read!() |> parse!()
  end

  @doc """
  Formats an AST as Hoverscript text.

  ## Options

    * `:width` - maximum line width (default: `100`)
    * `:column` - tag column width (default: `10`)
    * `:step` - indentation spaces per level (default: `3`)

  ## Examples

      iex> ast = Hoverscript.parse!(":para Hello")
      iex> text = Hoverscript.format_ast(ast)
      iex> is_binary(text)
      true

  """
  def format_ast(ast, opts \\ []), do: Format.format(ast, opts)

  @doc """
  Parses and formats a Hoverscript document.

  Returns formatted text even when parsing produces errors.

  ## Examples

      iex> {:ok, text} = Hoverscript.format(":para Hello")
      iex> is_binary(text)
      true

  """
  def format(text, opts \\ []) do
    case parse(text) do
      {:ok, ast} -> {:ok, format_ast(ast, opts)}
      {:error, errors, ast} -> {:error, errors, format_ast(ast, opts)}
    end
  end

  @doc """
  Parses and formats a Hoverscript document, raising on parse failure.
  """
  def format!(text, opts \\ []), do: text |> parse!() |> format_ast(opts)

  @doc """
  Converts an AST to HTML.

  ## Examples

      iex> ast = Hoverscript.parse!(":para Hello")
      iex> html = Hoverscript.ast_to_html(ast)
      iex> String.contains?(html, "Hello")
      true

  """
  def ast_to_html(ast), do: ToHtml.to_html(ast)

  @doc """
  Converts an AST to a Floki HTML tree (without serializing to a string).

  ## Examples

      iex> ast = Hoverscript.parse!(":para Hello")
      iex> floki = Hoverscript.ast_to_floki(ast)
      iex> is_list(floki)
      true

  """
  def ast_to_floki(ast), do: ToHtml.to_floki(ast)

  @doc """
  Parses a Hoverscript document and converts it to HTML.

  Returns HTML even when parsing produces errors.

  ## Examples

      iex> {:ok, html} = Hoverscript.text_to_html(":para Hello")
      iex> String.contains?(html, "Hello")
      true

  """
  def text_to_html(text) do
    case parse(text) do
      {:ok, ast} -> {:ok, ast_to_html(ast)}
      {:error, errors, ast} -> {:error, errors, ast_to_html(ast)}
    end
  end

  @doc """
  Parses a Hoverscript document and converts it to HTML, raising on parse failure.
  """
  def text_to_html!(text), do: text |> parse!() |> ast_to_html()

  @doc """
  Builds a Hoverscript project directory into a parsed AST.

  See `Hoverscript.Build.run/2` for options and return values.
  """
  def build(project_dir, opts \\ []), do: Build.run(project_dir, opts)

  @doc """
  Builds a Hoverscript project directory, raising on failure.
  """
  def build!(project_dir, opts \\ []), do: Build.run!(project_dir, opts)
end
