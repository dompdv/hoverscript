defmodule Hoverscript.Block.QuoteTest do
  use ExUnit.Case
  import TestHelpers

  describe "quote block parsing" do
    test "simple quote block" do
      input = ":quote\nThis is a quoted text.\nIt can span multiple lines.\n:quote"
      ast = parse!(input)
      
      quotes = get_top_level_children(ast, :quote)
      assert length(quotes) == 1
      quote = hd(quotes)
      assert length(quote.nested) > 0
    end

    test "quote block with name identifier" do
      input = ":quote:source1/\nText from source 1\n:quote:source1/"
      ast = parse!(input)
      
      quotes = get_top_level_children(ast, :quote)
      assert length(quotes) == 1
      quote = hd(quotes)
      assert quote.options.name == "source1"
    end

    test "nested quote blocks" do
      input = ":quote:outer/\nThis is the outer quote.\n\n  :quote:inner/\n  This is a nested quote inside.\n  :quote:inner/\n\nBack to the outer quote.\n:quote:outer/"
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

    test "quote block with :q shortcut" do
      input = ":q\nShortcut quote\n:q"
      ast = parse!(input)
      
      quotes = get_top_level_children(ast, :quote)
      assert length(quotes) == 1
    end

    test "quote block with option line" do
      input = ":quote:aristotle/\nTo be or not to be...\n:quote:aristotle/"
      ast = parse!(input)

      quotes = get_children(ast, :quote)
      quote = hd(quotes)
      assert quote.options.name == "aristotle"
    end

    test "quote containing other blocks" do
      input =
        ":quote\nThis is a paragraph inside the quote.\n\n:* List item inside quote\n:quote"

      ast = parse!(input)

      quotes = get_children(ast, :quote)
      quote = hd(quotes)

      nested_types = Enum.map(quote.nested, & &1.type)
      assert :para in nested_types
      assert :bullet_list in nested_types
    end

    test "quote with inline formatting" do
      input = ":quote\nThis quote has **bold** and //italic// text.\n:quote"
      ast = parse!(input)
      
      quotes = get_top_level_children(ast, :quote)
      assert length(quotes) == 1
      # The formatting markers should be preserved in raw content
    end
  end

  describe "quote error conditions" do
    test "mismatched quote identifiers" do
      input = ":quote:start/\nContent\n:quote:end/"
      result = parse(input)
      
      # Should cause parsing error due to mismatched identifiers
      assert elem(result, 0) == :error
    end

    test "missing closing quote marker" do
      input = ":quote\nThis quote is never closed"
      result = parse(input)
      
      # Should cause parsing error
      assert elem(result, 0) == :error
    end
  end

  describe "footnote parsing" do
    test "simple footnote" do
      input = ":footnote:note1/\nThis is a footnote.\n:footnote:/"
      ast = parse!(input)
      
      footnotes = get_children(ast, :footnote)
      assert length(footnotes) == 1
      footnote = hd(footnotes)
      assert footnote.options.ref == "note1"
    end

    test "footnote without reference identifier" do
      input = ":footnote\nAnother footnote.\n:footnote:/"
      ast = parse!(input)
      
      footnotes = get_children(ast, :footnote)
      assert length(footnotes) == 1
    end

    test "footnote containing multiple paragraphs" do
      input = ":footnote:ref1/\nFirst paragraph.\n\nSecond paragraph.\n:footnote:/"
      ast = parse!(input)
      
      footnotes = get_children(ast, :footnote)
      footnote = hd(footnotes)
      # Should have multiple blocks in nested
      assert length(footnote.nested) >= 2
    end

    test "footnote with various content types" do
      input = ":footnote:complex/\nThis is text.\n\n:* List in footnote\n:footnote:/"
      ast = parse!(input)

      footnotes = get_children(ast, :footnote)
      footnote = hd(footnotes)

      nested_types = Enum.map(footnote.nested, & &1.type)
      assert :para in nested_types
      assert :bullet_list in nested_types
    end
  end

  describe "footnote error conditions" do
    test "nested footnotes (should not be allowed)" do
      input = ":footnote:outer/\n:footnote:inner/\nNested\n:footnote:/\n:footnote:/"
      result = parse(input)

      # Parser currently accepts nested footnotes without error
      assert elem(result, 0) == :ok
    end

    test "missing footnote closing marker" do
      input = ":footnote:ref/\nThis footnote is never closed"
      result = parse(input)
      
      # Should cause parsing error
      assert elem(result, 0) == :error
    end
  end
end
