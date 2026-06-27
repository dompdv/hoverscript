defmodule Hoverscript.Block.HeadingTest do
  use ExUnit.Case
  import TestHelpers

  describe "heading parsing" do
    test "level 1 heading with := shortcut" do
      input = ":= Main Title"
      ast = parse!(input)
      
      heading = get_first_child(ast, :heading)
      assert heading != nil
      assert heading.level == 1
      assert extract_text(heading) == "Main Title"
    end

    test "level 2 heading with :== shortcut" do
      input = ":== Section Title"
      ast = parse!(input)
      
      heading = get_first_child(ast, :heading)
      assert heading.level == 2
      assert extract_text(heading) == "Section Title"
    end

    test "level 3 heading with :=== shortcut" do
      input = ":=== Subsection Title"
      ast = parse!(input)
      
      heading = get_first_child(ast, :heading)
      assert heading.level == 3
      assert extract_text(heading) == "Subsection Title"
    end

    test "heading with explicit :heading marker and level parameter" do
      input = ":heading:level=4/Another Heading"
      ast = parse!(input)
      
      heading = get_first_child(ast, :heading)
      assert heading.level == 4
      assert extract_text(heading) == "Another Heading"
    end

    test "heading with :h shortcut and level parameter" do
      input = ":h:level=5/Shortcut Heading"
      ast = parse!(input)
      
      heading = get_first_child(ast, :heading)
      assert heading.level == 5
      assert extract_text(heading) == "Shortcut Heading"
    end

    test "heading with positional level parameter" do
      input = ":h:2/Positional Level Heading"
      ast = parse!(input)
      
      heading = get_first_child(ast, :heading)
      assert heading.level == 2
      assert extract_text(heading) == "Positional Level Heading"
    end

    test "heading with option line" do
      input = "[level=3]\n:h Option Line Heading"
      ast = parse!(input)
      
      heading = get_first_child(ast, :heading)
      assert heading.level == 3
      assert extract_text(heading) == "Option Line Heading"
    end

    test "multi-line heading" do
      input = ":== This is the beginning of the heading\nthat continues on this line\nand even this line"
      ast = parse!(input)
      
      heading = get_first_child(ast, :heading)
      text = extract_text(heading)
      assert String.contains?(text, "beginning of the heading")
      assert String.contains?(text, "continues on this line")
      assert String.contains?(text, "even this line")
    end

    test "heading followed by paragraph" do
      input = ":= Main Title\n\nThis is the first paragraph."
      ast = parse!(input)
      
      children = ast.children
      # The heading contains the paragraph in its nested structure
      assert length(children) == 1
      assert hd(children).type == :heading
      assert length(hd(children).nested) > 0
    end

    test "multiple headings of different levels" do
      input = ":= Level 1\n:== Level 2\n:=== Level 3"
      ast = parse!(input)
      
      # Headings are nested, not separate siblings
      headings = get_top_level_children(ast, :heading)
      assert length(headings) == 1
      assert hd(headings).level == 1
      
      # Check nested headings
      nested_level2 = Enum.find(hd(headings).nested, fn node -> node.type == :heading and node.level == 2 end)
      assert nested_level2 != nil
      
      nested_level3 = Enum.find(nested_level2.nested, fn node -> node.type == :heading and node.level == 3 end)
      assert nested_level3 != nil
    end

    test "heading with inline formatting" do
      input = ":= **Bold** and //Italic// Heading"
      ast = parse!(input)
      
      heading = get_first_child(ast, :heading)
      # Raw text should contain formatting markers
      raw_text = extract_text(heading)
      assert String.contains?(raw_text, "**Bold**")
      assert String.contains?(raw_text, "//Italic//")
    end
  end

  describe "heading error conditions" do
    test "invalid level parameter" do
      input = ":h:level=0/Invalid Level"
      result = parse(input)
      
      # Should return error
      assert elem(result, 0) == :error
    end

    test "level parameter out of range" do
      input = ":h:level=7/Level Too High"
      result = parse(input)
      
      # Should return error
      assert elem(result, 0) == :error
    end

    test "non-numeric level parameter" do
      input = ":h:level=invalid/Non-numeric Level"
      result = parse(input)
      
      # Should return error
      assert elem(result, 0) == :error
    end
  end
end
