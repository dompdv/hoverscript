defmodule Hoverscript.Reference.ReferenceGuideTest do
  use ExUnit.Case
  import TestHelpers

  describe "reference guide examples" do
    test "simple document example from reference" do
      input = """
:= Getting Started with Hoverscript

:== Introduction

Hoverscript is easy to learn. Here's what you need to know:

:* It uses clear, consistent syntax
:* Blocks are separated by blank lines
:* Inline formatting uses doubled characters

:== Basic Formatting

You can make text **bold** or //italic//.

:sep

:== Lists

Numbered lists are simple:

:. First step
:. Second step
:. Third step

That's it!
"""
      ast = parse!(input)
      
      # Headings nest subsequent blocks under a single top-level heading
      assert length(ast.children) >= 1
      headings = get_children(ast, :heading)
      assert length(headings) >= 3
      assert Enum.any?(headings, &(&1.level == 1))
      assert Enum.any?(headings, &(&1.level == 2))
      
      # Should have paragraphs
      paras = get_children(ast, :para)
      assert length(paras) >= 3
      
      # Should have bullet list
      bullet_lists = get_children(ast, :bullet_list)
      assert length(bullet_lists) >= 1
      
      # Should have numbered list
      numbered_lists = get_children(ast, :ordered_list)
      assert length(numbered_lists) >= 1
      
      # Should have separator
      separators = get_children(ast, :sep)
      assert length(separators) >= 1
    end

    test "advanced document example from reference" do
      input = """
[align=center]
:title Advanced Hoverscript Techniques

:== Code Examples

Here's some Elixir code:

[lang=elixir]
:verbatim
defmodule MyApp do
  def hello(name) do
    IO.puts("Hello, @name!")
  end
end
:verbatim

:== Nested Lists and Quotes

:* Main points:
:** Sub-point one
:** Sub-point two with //emphasis//
:* Another main point

:quote:einstein/
Imagination is more important than knowledge.
:quote:einstein/

:== Inline Formatting

You can combine **bold and //italic//** text.

Chemical formulas work too: H,,2,,O or E = mc^^2^^. 
"""
      ast = parse!(input)
      
      assert length(ast.children) >= 1
      assert length(get_children(ast, :heading)) >= 2
      
      # Should have title with center alignment
      titles = get_children(ast, :title)
      assert length(titles) >= 1
      assert hd(titles).options.align == "center"
      
      # Should have verbatim block with elixir language
      verbatims = get_children(ast, :verbatim)
      assert length(verbatims) >= 1
      assert hd(verbatims).options.lang == "elixir"
      
      # Should have nested bullet lists
      bullet_lists = get_children(ast, :bullet_list)
      assert length(bullet_lists) >= 1
      
      # Check for nested structure
      list = hd(bullet_lists)
      assert length(list.items) >= 2
      
      first_item = Enum.at(list.items, 0)
      assert length(first_item.nested) >= 1
      assert first_item.nested |> Enum.at(0) |> Map.get(:type) == :bullet_list
      
      # Should have named quote
      quotes = get_children(ast, :quote)
      assert length(quotes) >= 1
      assert hd(quotes).options.name == "einstein"
      
      # Should have paragraphs with complex formatting
      paras = get_children(ast, :para)
      assert length(paras) >= 2
      
      # Check for formatting markers in paragraphs
      formatting_para = Enum.find(paras, fn para ->
        text = extract_text(para)
        String.contains?(text, "**bold and //italic//**")
      end)
      
      assert formatting_para != nil
    end

    test "paragraph examples from reference" do
      # Test default paragraph
      input1 = "This is a simple paragraph."
      ast1 = parse!(input1)
      assert length(get_children(ast1, :para)) == 1

      # Test explicit paragraph with center alignment
      input2 = ":para:center/This text is centered"
      ast2 = parse!(input2)
      para2 = get_first_child(ast2, :para)
      assert para2.options.align == "center"

      # Test paragraph with option line
      input3 = "[align=right]\n:para\nThis text is right-aligned"
      ast3 = parse!(input3)
      para3 = get_first_child(ast3, :para)
      assert para3.options.align == "right"
    end

    test "heading examples from reference" do
      # Test shortcut syntax
      input1 = ":= Main Document Title"
      ast1 = parse!(input1)
      heading1 = get_first_child(ast1, :heading)
      assert heading1.level == 1

      # Test level 2 shortcut
      input2 = ":== Section Title"
      ast2 = parse!(input2)
      heading2 = get_first_child(ast2, :heading)
      assert heading2.level == 2

      # Test explicit heading with level parameter
      input3 = ":heading:level=4/Another Way to Write a Heading"
      ast3 = parse!(input3)
      heading3 = get_first_child(ast3, :heading)
      assert heading3.level == 4

      # Test multi-line heading
      input4 = ":== This is the beginning of a long heading\nthat continues on this line\nand even this line"
      ast4 = parse!(input4)
      heading4 = get_first_child(ast4, :heading)
      text = extract_text(heading4)
      assert String.contains?(text, "beginning of a long heading")
      assert String.contains?(text, "continues on this line")
    end

    test "list examples from reference" do
      # Test simple bullet list
      input1 = ":* First item\n:* Second item\n:* Third item"
      ast1 = parse!(input1)
      lists1 = get_children(ast1, :bullet_list)
      list1 = hd(lists1)
      assert length(list1.items) == 3

      # Test nested bullet list
      input2 = ":* Top level item\n:** Nested item one\n:** Nested item two\n:* Another top level item"
      ast2 = parse!(input2)
      lists2 = get_children(ast2, :bullet_list)
      list2 = hd(lists2)
      assert length(list2.items) == 2
      assert length(Enum.at(list2.items, 0).nested) == 1

      # Test simple numbered list
      input3 = ":. First item\n:. Second item\n:. Third item"
      ast3 = parse!(input3)
      lists3 = get_children(ast3, :ordered_list)
      assert length(hd(lists3).items) == 3

      # Test numbered list with custom counter
      input4 = "[counter=5]\n:num Continue numbering from 5\n:num This will be 6"
      ast4 = parse!(input4)
      lists4 = get_children(ast4, :ordered_list)
      list4 = hd(lists4)
      assert Enum.at(list4.items, 0).options.counter == 5
    end

    test "quote examples from reference" do
      # Test simple quote
      input1 = ":quote\nThis is a quoted text.\n:quote"
      ast1 = parse!(input1)
      quotes1 = get_children(ast1, :quote)
      assert length(quotes1) == 1

      # Test named quote
      input2 = ":quote:source1/\nText from source 1\n:quote:source1/"
      ast2 = parse!(input2)
      quotes2 = get_children(ast2, :quote)
      assert hd(quotes2).options.name == "source1"

      # Test nested quotes
      input3 = ":quote:outer/\nOuter\n:quote:inner/\nInner\n:quote:inner/\nOuter\n:quote:outer/"
      ast3 = parse!(input3)
      quotes3 = get_children(ast3, :quote)
      outer = hd(quotes3)
      nested_quotes = Enum.filter(outer.nested, fn block -> block.type == :quote end)
      assert length(nested_quotes) == 1
      assert hd(nested_quotes).options.name == "inner"
    end

    test "verbatim examples from reference" do
      # Test simple code block
      input1 = ":verbatim\nfunction hello() {\n  console.log(\"Hello\");\n}\n:verbatim"
      ast1 = parse!(input1)
      verbatims1 = get_children(ast1, :verbatim)
      assert length(verbatims1) == 1

      # Test with language specification
      input2 = "[lang=elixir]\n:verbatim\ndefmodule Hello do\n  def world, do: :ok\nend\n:verbatim"
      ast2 = parse!(input2)
      verbatims2 = get_children(ast2, :verbatim)
      assert hd(verbatims2).options.lang == "elixir"

      # Test named verbatim block
      input3 = ":verbatim:code1/\nCode with :verbatim\n:verbatim:code1/"
      ast3 = parse!(input3)
      verbatims3 = get_children(ast3, :verbatim)
      assert hd(verbatims3).options.name == "code1"
      content = extract_verbatim_content(hd(verbatims3))
      assert String.contains?(content, ":verbatim")
    end

    test "separator examples from reference" do
      # Test simple separator
      input1 = ":sep"
      ast1 = parse!(input1)
      seps1 = get_children(ast1, :sep)
      assert length(seps1) == 1

      # Test separator with type
      input2 = ":sep:stars/"
      ast2 = parse!(input2)
      seps2 = get_children(ast2, :sep)
      assert hd(seps2).options.type == "stars"
    end

    test "title examples from reference" do
      # Test simple title
      input1 = ":title My Document Title"
      ast1 = parse!(input1)
      titles1 = get_children(ast1, :title)
      assert length(titles1) == 1

      # Test title with alignment
      input2 = "[align=left]\n:title Left-aligned Title"
      ast2 = parse!(input2)
      titles2 = get_children(ast2, :title)
      assert hd(titles2).options.align == "left"
    end

    test "slot examples from reference" do
      # Test simple slot
      input1 = ":slot\nContent\n:slot"
      ast1 = parse!(input1)
      slots1 = get_children(ast1, :slot)
      assert length(slots1) == 1

      # Test named slot
      input2 = "[name=callout]\n:slot\nImportant\n:slot"
      ast2 = parse!(input2)
      slots2 = get_children(ast2, :slot)
      assert hd(slots2).options.name == "callout"
    end

    test "inline formatting examples from reference" do
      # Test basic formatting
      input1 = "//italic// **bold** __underline__ ~~strike~~ ^^super^^ ,,sub,,"
      ast1 = parse!(input1)
      para1 = get_first_child(ast1, :para)
      text1 = extract_text(para1)
      assert String.contains?(text1, "//italic//")
      assert String.contains?(text1, "**bold**")
      assert String.contains?(text1, "__underline__")
      assert String.contains?(text1, "~~strike~~")
      assert String.contains?(text1, "^^super^^")
      assert String.contains?(text1, ",,sub,,")

      # Test nested formatting
      input2 = "**Bold with //italic inside// it**"
      ast2 = parse!(input2)
      para2 = get_first_child(ast2, :para)
      assert String.contains?(extract_text(para2), "**Bold with //italic inside// it**")

      # Test complex nesting
      input3 = "When //the sky ,,low,, and **heavy**// __weighs__ like a lid"
      ast3 = parse!(input3)
      para3 = get_first_child(ast3, :para)
      text3 = extract_text(para3)
      assert String.contains?(text3, "//the sky ,,low,, and **heavy**//")
      assert String.contains?(text3, "__weighs__")
    end

    test "EEx template examples from reference" do
      input = ":para Dear <%= @user.name %>, your balance is <%= @account.balance %>."
      ast = parse!(input)
      para = get_first_child(ast, :para)
      text = extract_text(para)
      assert String.contains?(text, "<%= @user.name %>")
      assert String.contains?(text, "<%= @account.balance %>")
    end

    test "special inline examples from reference" do
      input =
        "See [:image:name=diagram1] and [:link:url=https://example.com]++here++ for [:footnote:ref1]."

      ast = parse!(input)
      para = get_first_child(ast, :para)
      text = extract_text(para)
      assert String.contains?(text, "[:image:name=diagram1]")
      assert String.contains?(text, "[:link:url=https://example.com]++here++")
      assert String.contains?(text, "[:footnote:ref1]")
    end

    test "continuation line examples from reference" do
      input = ":* First item paragraph one\n:+\nSecond paragraph of first item\n:* Second item"
      ast = parse!(input)
      lists = get_children(ast, :bullet_list)
      list = hd(lists)
      assert length(list.items) == 2
      assert length(content_blocks(Enum.at(list.items, 0).blocks)) == 1
    end

    test "line break examples from reference" do
      input = ":para First line::\nSecond line::\nThird line"
      ast = parse!(input)
      para = get_first_child(ast, :para)
      text = extract_text(para)
      assert String.contains?(text, "::")
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
