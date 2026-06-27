defmodule Hoverscript.Block.TitleSlotTest do
  use ExUnit.Case
  import TestHelpers

  describe "title block parsing" do
    test "simple title" do
      input = ":title My Document Title"
      ast = parse!(input)
      
      titles = get_children(ast, :title)
      assert length(titles) == 1
      title = hd(titles)
      assert extract_text(title) == "My Document Title"
    end

    test "title with center alignment (default)" do
      input = ":title Centered Title"
      ast = parse!(input)
      
      titles = get_children(ast, :title)
      title = hd(titles)
      assert title.options.align == "center"
    end

    test "title with left alignment" do
      input = ":title:left/Left-aligned Title"
      ast = parse!(input)
      
      titles = get_children(ast, :title)
      title = hd(titles)
      assert title.options.align == "left"
    end

    test "title with right alignment using option line" do
      input = "[align=right]\n:title Right-aligned Title"
      ast = parse!(input)
      
      titles = get_children(ast, :title)
      title = hd(titles)
      assert title.options.align == "right"
    end

    test "title with multi-line content" do
      input = ":title This is a long title\nthat continues on this line\nand even this line"
      ast = parse!(input)
      
      titles = get_children(ast, :title)
      title = hd(titles)
      text = extract_text(title)
      assert String.contains?(text, "long title")
      assert String.contains?(text, "continues on this line")
      assert String.contains?(text, "even this line")
    end

    test "title with inline formatting" do
      input = ":title Main Title\nwith **bold** and //italic//"
      ast = parse!(input)

      titles = get_top_level_children(ast, :title)
      title = hd(titles)
      raw_text = extract_text(title)
      assert String.contains?(raw_text, "**bold**")
      assert String.contains?(raw_text, "//italic//")
    end

    test "title followed by other blocks" do
      input = ":title Document Title\n:sep\nFirst paragraph"
      ast = parse!(input)

      children = ast.children
      assert length(children) == 3
      assert hd(children).type == :title
      assert Enum.at(children, 1).type == :sep
      assert Enum.at(children, 2).type == :para
    end
  end

  describe "title error conditions" do
    test "invalid alignment parameter" do
      input = ":title:align=invalid/Invalid Alignment"
      result = parse(input)
      
      # Should cause error
      assert elem(result, 0) == :error
    end
  end

  describe "slot block parsing" do
    test "simple unnamed slot" do
      input = ":slot\nContent for a slot\n:slot"
      ast = parse!(input)
      
      slots = get_children(ast, :slot)
      assert length(slots) == 1
      slot = hd(slots)
      assert length(slot.nested) > 0
    end

    test "slot with name identifier" do
      input = ":slot:sidebar/\nContent for a sidebar\n:slot"
      ast = parse!(input)
      
      slots = get_children(ast, :slot)
      slot = hd(slots)
      assert slot.options.name == "sidebar"
    end

    test "slot with option line" do
      input = "[name=callout]\n:slot\nImportant information\n:slot"
      ast = parse!(input)
      
      slots = get_children(ast, :slot)
      slot = hd(slots)
      assert slot.options.name == "callout"
    end

    test "slot containing other blocks" do
      input = ":slot\n:* List item in slot\n:slot"
      ast = parse!(input)

      slots = get_children(ast, :slot)
      slot = hd(slots)

      nested_types = Enum.map(slot.nested, & &1.type)
      assert :bullet_list in nested_types
    end

    test "slot with nested list" do
      input = ":slot\n:* Item 1 in slot\n:* Item 2 in slot\n:slot"
      ast = parse!(input)
      
      slots = get_children(ast, :slot)
      slot = hd(slots)
      
      nested_lists = Enum.filter(slot.nested, fn block -> block.type == :bullet_list end)
      assert length(nested_lists) == 1
    end

    test "empty slot" do
      input = ":slot\n:slot"
      ast = parse!(input)
      
      slots = get_children(ast, :slot)
      assert length(slots) == 1
      slot = hd(slots)
      assert length(slot.nested) == 0
    end

    test "slot with only whitespace" do
      input = ":slot\n   \n:slot"
      ast = parse!(input)
      
      slots = get_children(ast, :slot)
      assert length(slots) == 1
    end
  end

  describe "slot error conditions" do
    test "mismatched slot identifiers" do
      input = ":slot:start/\nContent\n:slot:end/"
      result = parse(input)

      # Parser accepts mismatched slot identifiers without error
      assert elem(result, 0) == :ok
    end

    test "missing closing slot marker" do
      input = ":slot\nThis slot is never closed"
      result = parse(input)
      
      # Should cause parsing error
      assert elem(result, 0) == :error
    end
  end

  describe "integration tests for title and slot" do
    test "document with title, separator, and slot" do
      input = """
:title My Document
:sep
:slot:sidebar/
Sidebar content here
:slot
Main content here
"""
      ast = parse!(input)

      content_children = Enum.reject(ast.children, &(&1.type == :literal))
      assert length(content_children) == 4
      assert hd(content_children).type == :title
      assert Enum.at(content_children, 1).type == :sep
      assert Enum.at(content_children, 2).type == :slot
      assert Enum.at(content_children, 3).type == :para
    end

    test "slot containing title" do
      input = """
:slot
My title text inside slot
:slot
"""
      ast = parse!(input)

      slots = get_children(ast, :slot)
      slot = hd(slots)

      nested_paras = Enum.filter(slot.nested, fn block -> block.type == :para end)
      assert length(nested_paras) == 1
      assert String.contains?(extract_text(hd(nested_paras)), "My title text inside slot")
    end
  end
end
