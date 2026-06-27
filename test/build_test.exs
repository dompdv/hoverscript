defmodule Hoverscript.BuildTest do
  use ExUnit.Case, async: true

  @project "examples/build_project"
  @cycle_project "test/fixtures/build_cycle"
  @error_project "test/fixtures/build_parse_error"

  test "builds a project with TOML, imports, and EEx" do
    assert {:ok, ast, meta} = Hoverscript.build(@project)

    assert ast.type == :document
    assert is_binary(meta.expanded)
    assert Map.has_key?(meta.assigns, :site)
    assert Map.has_key?(meta.assigns, :chapters)
    assert length(meta.assigns.chapters) == 3

    assert meta.expanded =~ "Hoverscript Build Demo"
    assert meta.expanded =~ "Getting Started"
    assert meta.expanded =~ "Advanced Topics"
    assert meta.expanded =~ "Built from a project directory"

    headings =
      ast
      |> walk_nodes()
      |> Enum.filter(&(&1.type == :heading))
      |> Enum.map(& &1.body)

    assert "Getting Started" in headings
    assert "Advanced Topics" in headings
    assert "Reference" in headings
  end

  test "build!/1 returns ast" do
    ast = Hoverscript.build!(@project)
    assert ast.type == :document
  end

  test "dump_expanded writes intermediate file" do
    tmp = System.tmp_dir!() |> Path.join("hoverscript_build_test_#{:erlang.unique_integer()}.hvt")

    try do
      assert {:ok, _ast, _meta} = Hoverscript.build(@project, dump_expanded: tmp)
      assert File.exists?(tmp)
      content = File.read!(tmp)
      assert content =~ ":import" == false
      assert content =~ "Getting Started"
    after
      File.rm(tmp)
    end
  end

  test "detects import cycles" do
    assert {:error, :expand, errors} = Hoverscript.build(@cycle_project)
    assert Enum.any?(errors, fn {kind, _} -> kind == :import_cycle end)
  end

  test "remaps parse errors to source files" do
    assert {:error, :parse, errors, _ast} = Hoverscript.build(@error_project)

    assert map_size(errors) > 0

    {_category, [record | _]} = Enum.at(errors, 0)

    assert match?({_error, %{merged: _, source: _}}, record)
    assert record |> elem(1) |> Map.get(:source) |> Map.get(:start) |> Map.get(:file) =~ ".hvt"
  end

  test "import_hvt/2 via EEx inserts partial content" do
    project = "test/fixtures/build_import_hvt"

    assert {:ok, ast, _meta} = Hoverscript.build(project)
    text = ast |> walk_nodes() |> Enum.find(&(&1.type == :para)) |> extract_para_text()
    assert text =~ "injected via import_hvt"
  end

  defp walk_nodes(node, acc \\ [])

  defp walk_nodes(nodes, acc) when is_list(nodes) do
    Enum.reduce(nodes, acc, &walk_nodes/2)
  end

  defp walk_nodes(%{type: _} = node, acc) do
    acc = [node | acc]
    acc = if Map.has_key?(node, :children), do: walk_nodes(node.children, acc), else: acc
    acc = if Map.has_key?(node, :nested), do: walk_nodes(node.nested, acc), else: acc
    acc = if Map.has_key?(node, :blocks), do: walk_nodes(node.blocks, acc), else: acc

    if Map.has_key?(node, :items) and is_list(node.items) do
      walk_nodes(node.items, acc)
    else
      acc
    end
  end

  defp walk_nodes(_other, acc), do: acc

  defp extract_para_text(%{joined_lines: text}) when is_binary(text), do: text
  defp extract_para_text(%{body: text}) when is_binary(text), do: text
  defp extract_para_text(_), do: ""
end
