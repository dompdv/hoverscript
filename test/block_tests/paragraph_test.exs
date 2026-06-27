defmodule Hoverscript.Block.ParagraphTest do
  use ExUnit.Case
  import TestHelpers

  describe "paragraph parsing" do
    test "simple paragraph without explicit marker" do
      input = "This is a simple paragraph."
      ast = parse!(input)
      
      # Should have one child which is a paragraph
      assert length(ast.children) == 1
      para = get_first_child(ast, :para)
      assert para != nil
      assert extract_text(para) == "This is a simple paragraph."
    end

    test "paragraph with explicit :para marker" do
      input = ":para This is an explicit paragraph"
      ast = parse!(input)
      
      assert length(ast.children) == 1
      para = get_first_child(ast, :para)
      assert para != nil
      assert extract_text(para) == "This is an explicit paragraph"
    end

    test "paragraph with :p shortcut marker" do
      input = ":p This is a paragraph with p marker"
      ast = parse!(input)
      
      assert length(ast.children) == 1
      para = get_first_child(ast, :para)
      assert para != nil
      assert extract_text(para) == "This is a paragraph with p marker"
    end

    test "paragraph with center alignment" do
      input = ":para:center/This text is centered"
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      assert para.options.align == "center"
      assert extract_text(para) == "This text is centered"
    end

    test "paragraph with right alignment using option line" do
      input = "\n[align=right]\n:para\nThis text is right-aligned"
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      assert para.options.align == "right"
      assert extract_text(para) == "This text is right-aligned"
    end

    test "paragraph with frame option" do
      input = ":para:frame=1/This paragraph has a frame"
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      assert para.options.frame == 1
      assert extract_text(para) == "This paragraph has a frame"
    end

    test "multi-line paragraph" do
      input = "This is the first line\nof a multi-line paragraph\nthat continues here."
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      text = extract_text(para)
      assert String.contains?(text, "first line")
      assert String.contains?(text, "multi-line")
      assert String.contains?(text, "continues here")
    end

    test "multiple paragraphs separated by blank lines" do
      input = "First paragraph.\n\nSecond paragraph."
      ast = parse!(input)
      
      paras = get_children(ast, :para)
      assert length(paras) == 2
      assert extract_text(hd(paras)) == "First paragraph."
      assert extract_text(Enum.at(paras, 1)) == "Second paragraph."
    end

    test "paragraph with inline formatting (preserved in raw text)" do
      input = "This has **bold** and //italic// text"
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      # The raw text should contain the formatting markers
      raw_text = extract_text(para)
      assert String.contains?(raw_text, "**bold**")
      assert String.contains?(raw_text, "//italic//")
    end

    test "empty paragraph" do
      input = ":para/"
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      assert extract_text(para) == ""
    end

    test "paragraph with only whitespace" do
      input = ":para    "
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      assert String.trim(extract_text(para)) == ""
    end
  end

  describe "paragraph error conditions" do
    test "invalid alignment parameter" do
      input = ":para:align=invalid/This should cause an error"
      result = parse(input)
      
      # Should return error tuple
      assert elem(result, 0) == :error
      errors = parse_errors(result)
      assert Map.has_key?(errors, :bad_tagline) ||
             Map.has_key?(errors, :parameter_errors)
    end
  end
end
