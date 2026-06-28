defmodule Mix.Tasks.HvtLatexTest do
  use ExUnit.Case, async: false

  @tag :tmp_dir
  test "writes LaTeX for a project directory", %{tmp_dir: tmp_dir} do
    out = Path.join(tmp_dir, "main.tex")

    in_project(fn ->
      Mix.Task.reenable("hvt_latex")
      Mix.Task.run("hvt_latex", ["examples/build_project", "--output", out])
    end)

    assert File.exists?(out)
    content = File.read!(out)
    assert content =~ "\\documentclass"
    assert content =~ "Built from a project directory"
  end

  @tag :tmp_dir
  test "writes LaTeX for a single .hvt file", %{tmp_dir: tmp_dir} do
    out = Path.join(tmp_dir, "heading.tex")
    input = Path.join("examples", "heading_example.hvt")

    in_project(fn ->
      Mix.Task.reenable("hvt_latex")
      Mix.Task.run("hvt_latex", [input, "--output", out])
    end)

    assert File.exists?(out)
    content = File.read!(out)
    assert content =~ "\\section{"
    assert content =~ "Histoire"
  end

  @tag :tmp_dir
  test "fragment mode omits document wrapper", %{tmp_dir: tmp_dir} do
    out = Path.join(tmp_dir, "fragment.tex")
    input = Path.join("examples", "short_test.hvt")

    in_project(fn ->
      Mix.Task.reenable("hvt_latex")
      Mix.Task.run("hvt_latex", [input, "--output", out, "--fragment"])
    end)

    content = File.read!(out)
    refute content =~ "\\documentclass"
    refute content =~ "\\begin{document}"
  end

  defp in_project(fun) do
    original = File.cwd!()

    try do
      File.cd!(Path.expand("."))
      fun.()
    after
      File.cd!(original)
    end
  end
end
