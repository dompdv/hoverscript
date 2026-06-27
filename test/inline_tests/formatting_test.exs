defmodule Hoverscript.Inline.FormattingTest do
  use ExUnit.Case
  import TestHelpers

  describe "inline formatting parsing" do
    test "italic formatting" do
      input = "This is //italic// text"
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      # The raw text should contain the formatting markers
      assert String.contains?(extract_text(para), "//italic//")
    end

    test "bold formatting" do
      input = "This is **bold** text"
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      assert String.contains?(extract_text(para), "**bold**")
    end

    test "underline formatting" do
      input = "This is __underlined__ text"
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      assert String.contains?(extract_text(para), "__underlined__")
    end

    test "strikeout formatting" do
      input = "This is ~~strikethrough~~ text"
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      assert String.contains?(extract_text(para), "~~strikethrough~~")
    end

    test "superscript formatting" do
      input = "This is x^^2^^ superscript"
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      assert String.contains?(extract_text(para), "^^2^^")
    end

    test "subscript formatting" do
      input = "This is H,,2,,O subscript"
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      assert String.contains?(extract_text(para), ",,2,,")
    end

    test "multiple formatting types in one paragraph" do
      input = "**// Depart Italique et gras// ^^super^^ ,,subs,, ~~barré~~ et fin **"
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      text = extract_text(para)
      assert String.contains?(text, "**//")
      assert String.contains?(text, "// ^^")
      assert String.contains?(text, "^^ ,,")
      assert String.contains?(text, ",, ~~")
      assert String.contains?(text, "~~barré~~")
    end

    test "nested formatting - bold with italic inside" do
      input = "**Bold with //italic inside// it**"
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      assert String.contains?(extract_text(para), "**Bold with //italic inside// it**")
    end

    test "nested formatting - italic with bold inside" do
      input = "//Italic with **bold inside**//"
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      assert String.contains?(extract_text(para), "//Italic with **bold inside**//")
    end

    test "complex nested formatting" do
      input = "When //the sky ,,low,, and **heavy**// __weighs__ like a lid"
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      text = extract_text(para)
      assert String.contains?(text, "//the sky ,,low,, and **heavy**//")
      assert String.contains?(text, "__weighs__")
    end

    test "formatting at start of paragraph" do
      input = "//Italic at start// of paragraph"
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      assert String.starts_with?(extract_text(para), "//Italic")
    end

    test "formatting at end of paragraph" do
      input = "Paragraph ending with **bold**"
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      assert String.ends_with?(extract_text(para), "bold**")
    end

    test "adjacent formatting markers" do
      input = "**bold**//italic//"
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      assert String.contains?(extract_text(para), "**bold**//italic//")
    end

    test "formatting in headings" do
      input = ":= **Bold** and //Italic// Heading"
      ast = parse!(input)
      
      heading = get_first_child(ast, :heading)
      text = extract_text(heading)
      assert String.contains?(text, "**Bold**")
      assert String.contains?(text, "//Italic//")
    end

    test "formatting in list items" do
      input = ":* List item with **bold** text"
      ast = parse!(input)
      
      lists = get_children(ast, :bullet_list)
      list = hd(lists)
      item_text = extract_text(Enum.at(list.items, 0))
      assert String.contains?(item_text, "**bold**")
    end
  end

  describe "formatting error conditions" do
    test "unclosed italic marker" do
      input = "This is //unclosed italic text"
      result = parse(input)

      assert elem(result, 0) == :error
    end

    test "unclosed bold marker" do
      input = "This is **unclosed bold text"
      result = parse(input)

      assert elem(result, 0) == :error
    end

    test "mismatched formatting markers" do
      input = "This is **bold //italic** text"
      result = parse(input)

      assert elem(result, 0) == :error
    end
  end

  describe "EEx template parsing" do
    test "simple EEx tag" do
      input = ":para Dear <%= @user.name %>,"
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      assert String.contains?(extract_text(para), "<%= @user.name %>")
    end

    test "multiple EEx tags" do
      input = ":para Dear <%= @user.name %>, your balance is <%= @account.balance %>."
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      text = extract_text(para)
      assert String.contains?(text, "<%= @user.name %>")
      assert String.contains?(text, "<%= @account.balance %>")
    end

    test "EEx tag in heading" do
      input = ":= Welcome <%= @user.name %>"
      ast = parse!(input)
      
      heading = get_first_child(ast, :heading)
      assert String.contains?(extract_text(heading), "<%= @user.name %>")
    end

    test "EEx tag in list item" do
      input = ":* Item for <%= @user.name %>"
      ast = parse!(input)
      
      lists = get_children(ast, :bullet_list)
      item_text = extract_text(Enum.at(hd(lists).items, 0))
      assert String.contains?(item_text, "<%= @user.name %>")
    end

    test "EEx tag with complex expression" do
      input = ":para Result: <%= if @condition do \"yes\" else \"no\" end %>"
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      assert String.contains?(extract_text(para), "<%= if @condition do")
    end
  end

  describe "special inline parsing" do
    test "image inline" do
      input = "See [:image:name=diagram1] for details."
      ast = parse!(input)

      para = get_first_child(ast, :para)
      assert String.contains?(extract_text(para), "[:image:name=diagram1]")
    end

    test "link inline with text" do
      input = "Click [:link:url=https://example.com]++here++ for more."
      ast = parse!(input)

      para = get_first_child(ast, :para)
      assert String.contains?(extract_text(para), "[:link:url=https://example.com]++here++")
    end

    test "footnote inline" do
      input = ":para This needs a citation[:footnote:ref1]."
      ast = parse!(input)
      
      para = get_first_child(ast, :para)
      assert String.contains?(extract_text(para), "[:footnote:ref1]")
    end

    test "image inline with named parameter" do
      input = "See [:image:name=diagram1] for details."
      ast = parse!(input)

      para = get_first_child(ast, :para)
      assert String.contains?(extract_text(para), "[:image:name=diagram1]")
    end

    test "link inline without text" do
      input = "Visit [:link:url=https://example.com] today."
      ast = parse!(input)

      para = get_first_child(ast, :para)
      assert String.contains?(extract_text(para), "[:link:url=https://example.com]")
    end

    test "multiple special inlines in one paragraph" do
      input =
        "See [:image:name=img1] and [:link:url=http://example.com]++link++ for [:footnote:ref1]."

      ast = parse!(input)

      para = get_first_child(ast, :para)
      text = extract_text(para)
      assert String.contains?(text, "[:image:name=img1]")
      assert String.contains?(text, "[:link:url=http://example.com]++link++")
      assert String.contains?(text, "[:footnote:ref1]")
    end
  end
end
