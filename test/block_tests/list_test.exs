defmodule Hoverscript.Block.ListTest do
  use ExUnit.Case
  import TestHelpers

  describe "bullet list parsing" do
    test "simple bullet list with single items" do
      input = ":* First item\n:* Second item\n:* Third item"
      ast = parse!(input)
      
      lists = get_top_level_children(ast, :bullet_list)
      assert length(lists) == 1
      list = hd(lists)
      assert length(list.items) == 3
    end

    test "bullet list with level 2 nesting" do
      input = ":* Top level item\n:** Nested item one\n:** Nested item two\n:* Another top level item"
      ast = parse!(input)
      
      lists = get_top_level_children(ast, :bullet_list)
      assert length(lists) == 1
      list = hd(lists)
      assert length(list.items) == 2  # Two top-level items
      
      # Check nesting
      first_item = Enum.at(list.items, 0)
      assert length(first_item.nested) == 1
      nested_list = Enum.at(first_item.nested, 0)
      assert nested_list.type == :bullet_list
      assert length(nested_list.items) == 2
    end

    test "bullet list with level 3 nesting" do
      input = ":* Level 1\n:** Level 2\n:*** Level 3\n:* Back to Level 1"
      ast = parse!(input)
      
      lists = get_top_level_children(ast, :bullet_list)
      assert length(lists) == 1
      list = hd(lists)
      assert length(list.items) == 2
      
      # Check deep nesting
      first_item = Enum.at(list.items, 0)
      assert length(first_item.nested) == 1
      level2_list = Enum.at(first_item.nested, 0)
      assert length(level2_list.items) == 1
      
      level2_item = Enum.at(list.items, 0)
      assert length(level2_item.nested) == 1
      level3_list = Enum.at(level2_item.nested, 0)
      assert length(level3_list.items) == 1
    end

    test "bullet list with explicit :list marker" do
      input = ":list First item\n:list Second item"
      ast = parse!(input)
      
      lists = get_top_level_children(ast, :bullet_list)
      assert length(lists) == 1
      assert length(hd(lists).items) == 2
    end

    test "bullet list with :l shortcut" do
      input = ":l First item\n:l Second item"
      ast = parse!(input)
      
      lists = get_top_level_children(ast, :bullet_list)
      assert length(lists) == 1
      assert length(hd(lists).items) == 2
    end

    test "bullet list item with multiple paragraphs using continuation" do
      input = ":* First paragraph\n:+\nSecond paragraph\n:+\nThird paragraph\n:* Next item"
      ast = parse!(input)
      
      lists = get_top_level_children(ast, :bullet_list)
      assert length(lists) == 1
      list = hd(lists)
      assert length(list.items) == 2
      
      # First item should have continued blocks
      first_item = Enum.at(list.items, 0)
      assert Map.has_key?(first_item, :blocks)
      assert length(content_blocks(first_item.blocks)) == 2
    end

    test "bullet list with multi-line items" do
      input = ":* This item has multiple lines\nof content that continues here\n:* This is a separate item"
      ast = parse!(input)
      
      lists = get_top_level_children(ast, :bullet_list)
      list = hd(lists)
      assert length(list.items) == 2
      
      first_item_text = extract_text(Enum.at(list.items, 0))
      assert String.contains?(first_item_text, "multiple lines")
      assert String.contains?(first_item_text, "continues here")
    end
  end

  describe "numbered list parsing" do
    test "simple numbered list" do
      input = ":. First item\n:. Second item\n:. Third item"
      ast = parse!(input)
      
      lists = get_top_level_children(ast, :ordered_list)
      assert length(lists) == 1
      list = hd(lists)
      assert length(list.items) == 3
    end

    test "numbered list with explicit :num marker" do
      input = ":num First step\n:num Second step"
      ast = parse!(input)
      
      lists = get_top_level_children(ast, :ordered_list)
      assert length(lists) == 1
      assert length(hd(lists).items) == 2
    end

    test "numbered list with :n shortcut" do
      input = ":n First step\n:n Second step"
      ast = parse!(input)
      
      lists = get_top_level_children(ast, :ordered_list)
      assert length(lists) == 1
      assert length(hd(lists).items) == 2
    end

    test "numbered list with custom starting counter" do
      input = "[counter=5]\n:num Continue from 5\n:num This should be 6"
      ast = parse!(input)
      
      lists = get_top_level_children(ast, :ordered_list)
      list = hd(lists)
      assert Enum.at(list.items, 0).options.counter == 5
    end

    test "numbered list with level 2 nesting" do
      input = ":. Main step one\n:.. Sub-step one\n:.. Sub-step two\n:. Main step two"
      ast = parse!(input)
      
      lists = get_top_level_children(ast, :ordered_list)
      assert length(lists) == 1
      list = hd(lists)
      assert length(list.items) == 2
      
      # Check nesting
      first_item = Enum.at(list.items, 0)
      assert length(first_item.nested) == 1
      nested_list = Enum.at(first_item.nested, 0)
      assert nested_list.type == :ordered_list
      assert length(nested_list.items) == 2
    end

    test "mixed bullet and numbered list nesting" do
      input = ":* Overview\n:.. First detailed step\n:.. Second detailed step\n:* Summary"
      ast = parse!(input)
      
      # Should have bullet list with nested numbered list
      bullet_lists = get_children(ast, :bullet_list)
      assert length(bullet_lists) == 1
      
      bullet_list = hd(bullet_lists)
      first_item = Enum.at(bullet_list.items, 0)
      assert length(first_item.nested) == 1
      assert Enum.at(first_item.nested, 0).type == :ordered_list
    end

    test "blank lines create separate lists" do
      input = ":. Item 1\n\n:. Item 2"
      ast = parse!(input)
      
      lists = get_top_level_children(ast, :ordered_list)
      # Should create two separate lists
      assert length(lists) == 2
      assert length(hd(lists).items) == 1
      assert length(Enum.at(lists, 1).items) == 1
    end

    test "continuation line keeps items in same list" do
      input = ":. Item 1\n:+\n:. Item 2"
      ast = parse!(input)
      
      lists = get_top_level_children(ast, :ordered_list)
      # Should create one list with two items
      assert length(lists) == 1
      assert length(hd(lists).items) == 2
    end
  end

  describe "list error conditions" do
    test "invalid list level" do
      input = ":list:level=4/Invalid Level"
      result = parse(input)
      
      # Level 4 is invalid for lists (max is 3)
      assert elem(result, 0) == :error
    end

    test "invalid counter parameter" do
      input = ":num:counter=invalid/Invalid Counter"
      result = parse(input)
      
      assert elem(result, 0) == :error
    end
  end
end
