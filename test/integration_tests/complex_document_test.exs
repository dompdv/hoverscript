defmodule Hoverscript.Integration.ComplexDocumentTest do
  use ExUnit.Case
  import TestHelpers

  describe "complex document parsing" do
    test "document with multiple block types" do
      input = """
:= Main Title

:== Section One

This is the first paragraph of section one.

:* Bullet item 1
:* Bullet item 2

:== Section Two

:. Numbered item 1
:. Numbered item 2

:sep

:quote
This is a quote
:quote

:verbatim
Code block here
:verbatim
"""
      ast = parse!(input)
      
      # Headings nest content; collect block types recursively
      types = ast |> walk_nodes() |> Enum.map(& &1.type) |> Enum.uniq()
      assert :heading in types
      assert :para in types
      assert :bullet_list in types
      assert :ordered_list in types
      assert :sep in types
      assert :quote in types
      assert :verbatim in types
    end

    test "deeply nested structures" do
      input = """
:* Level 1
:** Level 2
:*** Level 3
:== Heading
:quote
:* List in quote
:quote
"""
      ast = parse!(input)
      
      bullet_lists = get_children(ast, :bullet_list)
      assert length(bullet_lists) >= 1
      
      bullet_list = hd(bullet_lists)
      assert length(bullet_list.items) >= 1
      
      level1_item = Enum.at(bullet_list.items, 0)
      assert length(level1_item.nested) >= 1
      
      level2_list = Enum.at(level1_item.nested, 0)
      assert length(level2_list.items) >= 1
      
      level2_item = Enum.at(level2_list.items, 0)
      assert length(level2_item.nested) >= 1
      
      level3_list = Enum.at(level2_item.nested, 0)
      assert length(level3_list.items) >= 1
    end

    test "document with all heading levels" do
      input = """
:=
:==
:===
:====
:=====
:======
"""
      ast = parse!(input)
      
      headings = get_children(ast, :heading)
      assert length(headings) == 6

      levels = Enum.map(headings, & &1.level) |> Enum.sort()
      assert levels == [1, 2, 3, 4, 5, 6]
    end

    test "document with mixed list types" do
      input = """
:* Bullet 1
:.. Numbered 1.1
:.. Numbered 1.2
:* Bullet 2
:.. Numbered 2.1
:* Bullet 3
"""
      ast = parse!(input)
      
      bullet_lists = get_top_level_children(ast, :bullet_list)
      assert length(bullet_lists) == 1
      
      bullet_list = hd(bullet_lists)
      assert length(bullet_list.items) == 3
      
      # First two bullet items contain nested numbered lists
      Enum.take(bullet_list.items, 2)
      |> Enum.each(fn item ->
        assert length(item.nested) == 1
        assert Enum.at(item.nested, 0).type == :ordered_list
      end)

      # Last bullet item has no nested list
      assert Enum.at(bullet_list.items, 2).nested == []
    end

    test "document with continuation lines" do
      input = """
:* First item
:+
Second paragraph of first item
:+
Third paragraph
:* Second item
"""
      ast = parse!(input)
      
      lists = get_children(ast, :bullet_list)
      assert length(lists) == 1
      
      list = hd(lists)
      assert length(list.items) == 2
      
      # First item should have continued blocks
      first_item = Enum.at(list.items, 0)
      assert Map.has_key?(first_item, :blocks)
      assert length(content_blocks(first_item.blocks)) == 2
    end

    test "document with line breaks" do
      input = """
:para First line::
Second line::
Third line
"""
      ast = parse!(input)
      
      paras = get_children(ast, :para)
      assert length(paras) == 1
      
      # Should contain the line break markers
      text = extract_text(hd(paras))
      assert String.contains?(text, "::")
    end

    test "document with all formatting types" do
      input = """
**bold** //italic// __underline__ ~~strike~~ ^^super^^ ,,sub,, <%= @var %> [:link:url=url]++text++
"""
      ast = parse!(input)
      
      paras = get_children(ast, :para)
      assert length(paras) == 1
      
      text = extract_text(hd(paras))
      assert String.contains?(text, "**bold**")
      assert String.contains?(text, "//italic//")
      assert String.contains?(text, "__underline__")
      assert String.contains?(text, "~~strike~~")
      assert String.contains?(text, "^^super^^")
      assert String.contains?(text, ",,sub,,")
      assert String.contains?(text, "<%= @var %>")
      assert String.contains?(text, "[:link:url=url]++text++")
    end

    test "document with nested quotes" do
      input = """
:quote:outer/
Outer quote
:quote:inner/
Inner quote
:quote:inner/
Back to outer
:quote:outer/
"""
      ast = parse!(input)
      
      quotes = get_top_level_children(ast, :quote)
      assert length(quotes) == 1
      
      outer_quote = hd(quotes)
      assert outer_quote.options.name == "outer"
      
      # Should have nested quote
      nested_quotes = Enum.filter(outer_quote.nested, fn block -> block.type == :quote end)
      assert length(nested_quotes) == 1
      
      inner_quote = hd(nested_quotes)
      assert inner_quote.options.name == "inner"
    end

    test "document with verbatim containing special characters" do
      input = """
:verbatim:code1/
This contains :verbatim markers
and //italic// markers
and **bold** markers
:verbatim:code1/
"""
      ast = parse!(input)
      
      verbatims = get_children(ast, :verbatim)
      assert length(verbatims) == 1
      
      content = extract_verbatim_content(hd(verbatims))
      assert String.contains?(content, ":verbatim markers")
      assert String.contains?(content, "//italic// markers")
      assert String.contains?(content, "**bold** markers")
    end

    test "document with all separator types" do
      input = """
:sep:line/
:sep:stars/
:sep:asterism/
:sep:dinkus/
"""
      ast = parse!(input)
      
      separators = get_children(ast, :sep)
      assert length(separators) == 4
      
      types = Enum.map(separators, fn sep -> sep.options.type end)
      assert "line" in types
      assert "stars" in types
      assert "asterism" in types
      assert "dinkus" in types
    end

    test "document with slots containing various content" do
      input = """
:slot:sidebar/
Sidebar content here
:* Item 1
:* Item 2
:slot
"""
      ast = parse!(input)

      slots = get_children(ast, :slot)
      assert length(slots) == 1

      slot = hd(slots)
      assert slot.options.name == "sidebar"

      nested_types = Enum.map(slot.nested, & &1.type)
      assert :para in nested_types
      assert :bullet_list in nested_types
    end

    test "large complex document" do
      input = """
:= Comprehensive Document Title

:== Introduction

This document demonstrates //all// the features of Hoverscript.

:== Formatting Examples

Here we have **bold**, //italic//, __underline__, ~~strike~~, ^^super^^ and ,,sub,, text.

:== List Examples

:* Bullet level 1
:** Bullet level 2
:*** Bullet level 3

:. Numbered level 1
:.. Numbered level 2
:... Numbered level 3

:== Code Examples

[lang=elixir]
:verbatim
defmodule Example do
  def hello(name) do
    IO.puts("Hello, @name!")
  end
end
:verbatim

:== Quote Examples

:quote:famous/
To be or not to be, that is the question.
:quote:famous/

:== Special Features

Line break test::
This should be on a new line.

EEx test: <%= @user.name %>

See [:link:url=https://example.com]++Example Link++

:sep:stars/

:title Conclusion

This concludes our comprehensive test document.
"""
      ast = parse!(input)
      
      assert length(get_children(ast, :heading)) >= 5
      
      types = ast |> walk_nodes() |> Enum.map(& &1.type) |> Enum.uniq()
      assert :heading in types
      assert :para in types
      assert :bullet_list in types
      assert :ordered_list in types
      assert :verbatim in types
      assert :quote in types
      assert :sep in types
      assert :title in types
    end
  end

  describe "error handling in complex documents" do
    test "document with parsing error still produces partial AST" do
      input = """
:= Valid Heading

:invalid_block_type This should cause an error

:para But this should still parse
"""
      result = parse(input)
      
      assert elem(result, 0) == :error
      ast = parse_ast(result)
      assert ast != nil
      
      assert length(get_children(ast, :heading)) >= 1
      assert length(get_children(ast, :para)) >= 1
    end

    test "document with multiple errors" do
      input = """
:= Valid

:invalid1

:invalid2:bad_param/

:para Valid paragraph
"""
      result = parse(input)
      
      assert elem(result, 0) == :error
      
      paras = get_children(parse_ast(result), :para)
      assert length(paras) >= 1
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
end
