defmodule Hoverscript.Block.VerbatimTest do
  use ExUnit.Case
  import TestHelpers

  describe "verbatim block parsing" do
    test "simple verbatim block" do
      input = ":verbatim\nfunction hello() {\n  console.log(\"Hello, world!\");\n}\n:verbatim"
      ast = parse!(input)

      verbatims = get_children(ast, :verbatim)
      assert length(verbatims) == 1
      verbatim = hd(verbatims)

      # Should preserve exact content including indentation
      raw_content = extract_verbatim_content(verbatim)
      assert String.contains?(raw_content, "function hello() {")
      assert String.contains?(raw_content, "console.log")
    end

    test "verbatim block with language specification" do
      input = "[lang=elixir]\n:verbatim\ndefmodule Hello do\n  def world, do: :ok\nend\n:verbatim"
      ast = parse!(input)

      verbatims = get_children(ast, :verbatim)
      verbatim = hd(verbatims)
      assert verbatim.options.lang == "elixir"
    end

    test "verbatim block with name identifier" do
      input = ":verbatim:code1/\nThis is named code\n:verbatim:code1/"
      ast = parse!(input)

      verbatims = get_children(ast, :verbatim)
      verbatim = hd(verbatims)
      assert verbatim.options.name == "code1"
    end

    test "verbatim block containing verbatim markers" do
      input = ":verbatim:code1/\nThis code contains :verbatim markers\nthat would otherwise end the block.\n:verbatim:code1/"
      ast = parse!(input)

      verbatims = get_children(ast, :verbatim)
      assert length(verbatims) == 1

      content = extract_verbatim_content(hd(verbatims))
      assert String.contains?(content, ":verbatim markers")
    end

    test "verbatim block preserves indentation" do
      input = ":verbatim\n    def foo\n        puts \"foo\"\n    end\n:verbatim"
      ast = parse!(input)

      verbatims = get_children(ast, :verbatim)
      content = extract_verbatim_content(hd(verbatims))

      # Should preserve the exact indentation
      assert String.contains?(content, "    def foo")
      assert String.contains?(content, "        puts")
    end

    test "verbatim block with type parameter" do
      input = ":verbatim:type=code/\nCode content\n:verbatim"
      ast = parse!(input)

      verbatims = get_children(ast, :verbatim)
      verbatim = hd(verbatims)
      assert verbatim.options.type == "code"
    end

    test "empty verbatim block" do
      input = ":verbatim\n:verbatim"
      ast = parse!(input)

      verbatims = get_children(ast, :verbatim)
      assert length(verbatims) == 1
      content = extract_verbatim_content(hd(verbatims))
      assert String.trim(content) == ""
    end

    test "verbatim block with only whitespace" do
      input = ":verbatim\n   \n  \n:verbatim"
      ast = parse!(input)

      verbatims = get_children(ast, :verbatim)
      content = extract_verbatim_content(hd(verbatims))
      assert String.trim(content) == ""
    end
  end

  describe "verbatim error conditions" do
    test "mismatched verbatim identifiers" do
      input = ":verbatim:start/\nContent\n:verbatim:end/"
      result = parse(input)

      # Should cause parsing error due to mismatched identifiers
      assert elem(result, 0) == :error
    end

    test "missing closing verbatim marker" do
      input = ":verbatim\nThis verbatim is never closed"
      result = parse(input)

      # Should cause parsing error
      assert elem(result, 0) == :error
    end

    test "verbatim block with invalid language parameter" do
      input = "[lang=]\n:verbatim\nContent\n:verbatim"
      result = parse(input)
      assert elem(result, 0) == :error
      error = elem(result, 1)
      assert Map.has_key?(error, :bad_options)
      # Empty language might be invalid
      # This depends on parser validation
    end
  end

  # Helper function to extract content from verbatim blocks
  defp extract_verbatim_content(verbatim) do
    verbatim.raw_lines
    |> Enum.map(fn
      {:line, _, text} -> text
      {_, _, text} -> text
    end)
    |> Enum.join("\n")
  end

  describe "separator parsing" do
    test "simple separator" do
      input = ":sep"
      ast = parse!(input)

      separators = get_children(ast, :sep)
      assert length(separators) == 1
    end

    test "separator with line type" do
      input = ":sep:line/"
      ast = parse!(input)

      separators = get_children(ast, :sep)
      separator = hd(separators)
      assert separator.options.type == "line"
    end

    test "separator with stars type" do
      input = ":separator:stars/"
      ast = parse!(input)

      separators = get_children(ast, :sep)
      separator = hd(separators)
      assert separator.options.type == "stars"
    end

    test "separator with option line" do
      input = "[type=asterism]\n:sep"
      ast = parse!(input)

      separators = get_children(ast, :sep)
      separator = hd(separators)
      assert separator.options.type == "asterism"
    end

    test "multiple separators in sequence" do
      input = ":sep\n:sep\n:sep"
      ast = parse!(input)

      separators = get_children(ast, :sep)
      assert length(separators) == 3
    end

    test "separator between other blocks" do
      input = ":para First paragraph\n:sep\n:para Second paragraph"
      ast = parse!(input)

      children = ast.children
      assert length(children) == 3
      assert hd(children).type == :para
      assert Enum.at(children, 1).type == :sep
      assert Enum.at(children, 2).type == :para
    end
  end

  describe "separator error conditions" do
    test "invalid separator type" do
      input = ":sep:type=invalid/"
      result = parse(input)

      # Should cause error for invalid type
      assert elem(result, 0) == :error
    end
  end
end
