defmodule Hoverscript.Converter.ToLatexTest do
  use ExUnit.Case
  import TestHelpers

  alias Hoverscript.Converter.ToLatex

  describe "to_latex/2 fragment mode" do
    test "simple paragraph" do
      ast = parse!(":para Hello world")
      latex = ToLatex.to_latex(ast, fragment: true)

      assert latex =~ "Hello world"
      refute latex =~ "\\documentclass"
    end

    test "escapes LaTeX special characters" do
      ast = parse!(":para 100% done with foo_bar")
      latex = ToLatex.to_latex(ast, fragment: true)

      assert latex =~ "100\\%"
      assert latex =~ "foo\\_bar"
    end

    test "inline formatting" do
      ast = parse!("This has **bold** and //italic// text")
      latex = ToLatex.to_latex(ast, fragment: true)

      assert latex =~ "\\textbf{bold}"
      assert latex =~ "\\emph{italic}"
    end

    test "headings emit flat section commands from nested outline" do
      input = """
      := Chapter

      :para Intro text.

      :== Section

      :para Section body.

      :=== Subsection

      :para Subsection body.
      """

      ast = parse!(input)
      latex = ToLatex.to_latex(ast, fragment: true)

      assert latex =~ "\\section{Chapter}"
      assert latex =~ "\\subsection{Section}"
      assert latex =~ "\\subsubsection{Subsection}"
      assert latex =~ "Intro text."
      assert latex =~ "Section body."
      assert latex =~ "Subsection body."

      refute latex =~ "\\begin{section}"
      refute latex =~ "\\begin{subsection}"

      section_pos = :binary.match(latex, "\\section{Chapter}") |> elem(0)
      subsection_pos = :binary.match(latex, "\\subsection{Section}") |> elem(0)
      subsubsection_pos = :binary.match(latex, "\\subsubsection{Subsection}") |> elem(0)

      assert section_pos < subsection_pos
      assert subsection_pos < subsubsection_pos
    end

    test "bullet and ordered lists" do
      input = """
      :*
      First item

      :*
      Second item

      :.
      Numbered one

      :.
      Numbered two
      """

      ast = parse!(input)
      latex = ToLatex.to_latex(ast, fragment: true)

      assert latex =~ "\\begin{itemize}"
      assert latex =~ "\\end{itemize}"
      assert latex =~ "\\begin{enumerate}"
      assert latex =~ "\\end{enumerate}"
      assert latex =~ "First item"
      assert latex =~ "Numbered two"
    end

    test "quote block" do
      ast = parse!(":quote\nQuoted text\n:quote")
      latex = ToLatex.to_latex(ast, fragment: true)

      assert latex =~ "\\begin{quote}"
      assert latex =~ "Quoted text"
      assert latex =~ "\\end{quote}"
    end

    test "verbatim block" do
      input = """
      :verbatim
      line one
      line two
      :verbatim
      """

      ast = parse!(input)
      latex = ToLatex.to_latex(ast, fragment: true)

      assert latex =~ "\\begin{verbatim}"
      assert latex =~ "line one"
      assert latex =~ "line two"
      assert latex =~ "\\end{verbatim}"
    end

    test "separator types" do
      ast = parse!("[type=stars]\n:sep")
      latex = ToLatex.to_latex(ast, fragment: true)
      assert latex =~ "***"
    end
  end

  describe "to_latex/2 full document" do
    test "wraps body in document template" do
      ast = parse!(":para Body text")
      latex = ToLatex.to_latex(ast)

      assert latex =~ "\\documentclass[11pt,a4paper]{article}"
      assert latex =~ "\\usepackage"
      assert latex =~ "\\begin{document}"
      assert latex =~ "Body text"
      assert latex =~ "\\end{document}"
    end

    test "custom document class and class options" do
      ast = parse!(":para Content")
      latex = ToLatex.to_latex(ast, documentclass: "report", class_options: ["12pt"])

      assert latex =~ "\\documentclass[12pt]{report}"
    end

    test "title block becomes maketitle metadata, not a section" do
      input = """
      :title My Document Title

      :para First paragraph.
      """

      ast = parse!(input)
      latex = ToLatex.to_latex(ast)

      assert latex =~ "\\title{My Document Title}"
      assert latex =~ "\\maketitle"
      assert latex =~ "First paragraph."
      refute latex =~ "\\section{My Document Title}"
    end

    test "extra preamble is injected" do
      ast = parse!(":para Text")
      latex = ToLatex.to_latex(ast, preamble: "\\newcommand{\\testcmd}{ok}")

      assert latex =~ "\\newcommand{\\testcmd}{ok}"
    end
  end

  describe "escape_latex/1" do
    test "escapes all special characters" do
      assert ToLatex.escape_latex("#$%&~_^{}") ==
               "\\#\\$\\%\\&\\textasciitilde{}\\_\\textasciicircum{}\\{\\}"
    end
  end

  describe "Hoverscript public API" do
    test "ast_to_latex and text_to_latex" do
      ast = parse!(":para API test")
      assert Hoverscript.ast_to_latex(ast, fragment: true) =~ "API test"
      assert {:ok, latex} = Hoverscript.text_to_latex(":para API test", fragment: true)
      assert latex =~ "API test"
    end
  end
end
