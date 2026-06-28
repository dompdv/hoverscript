defmodule Hoverscript.Converter.ToHtml do
  @moduledoc """
  This module is responsible for converting a Hoverscript AST to the HTML format that we use to display the preview.
  """

  # TODO: check that all tags are handled (blocks and inlines)

  def to_html(hoverscript_ast) do
    to_floki(hoverscript_ast) |> Floki.raw_html()
  end

  def to_floki(hoverscript_ast) do
    to_html_ast(hoverscript_ast)
  end

  @classes %{
    document: "py-3",
    heading: %{
      1 => "py-3 font-bold text-3xl",
      2 => "py-2 font-bold text-2xl",
      3 => "py-1 font-bold text-xl",
      4 => "py-3 font-bold text-lg",
      5 => "py-2 font-bold text-base",
      6 => "py-1 font-bold text-sm"
    },
    para: "px-2 py-1",
    title: "mx-4 border",
    sep: "",
    footnote: "px-2 py-1 italic text-xs",
    slot: "px-2 py-1",
    quote: "px-2 py-1 border-l-4 border-gray-400 bg-gray-100",
    verbatim: "px-2 py-1 bg-gray-100",
    ordered_list: "px-2 py-1 list-decimal",
    bullet_list: "px-2 py-1 list-disc",
    # Increase indentation for nested lists, with levels ranging from 1 to 6
    num: %{
      1 => "ml-4",
      2 => "ml-8",
      3 => "ml-12",
      4 => "ml-16",
      5 => "ml-20",
      6 => "ml-24"
    },
    list: %{
      1 => "ml-4",
      2 => "ml-8",
      3 => "ml-12",
      4 => "ml-16",
      5 => "ml-20",
      6 => "ml-24"
    }
  }

  def to_html_ast(%{type: :literal}), do: nil

  def to_html_ast(%{type: :document, children: children} = node) do
    [{"div", node_attrs(node), process_blocks(children)}]
  end

  def to_html_ast(%{type: :para, inlines: inlines} = node) do
    %{options: options} = node
    align = Map.get(options, :align, "justify")

    add_class =
      case align do
        "center" -> " text-center"
        "right" -> "text-right"
        "left" -> " text-left"
        "justify" -> " text-justify"
      end

    attrs =
      node_attrs(node)
      |> Enum.map(fn
        {"class", s} -> {"class", s <> add_class}
        c -> c
      end)

    {"p", attrs, process_inlines(inlines)}
  end

  def to_html_ast(%{type: :heading, level: level, inlines: inlines, nested: nested} = node) do
    [{"h#{level}", node_attrs(node), process_inlines(inlines)}] ++ process_blocks(nested)
  end

  def to_html_ast(%{type: :ordered_list, items: items} = node) do
    {"ol", node_attrs(node), process_blocks(items)}
  end

  def to_html_ast(%{type: :bullet_list, items: items} = node) do
    {"ul", node_attrs(node), process_blocks(items)}
  end

  def to_html_ast(%{type: :num, blocks: blocks, nested: nested, inlines: inlines} = node) do
    {"li", node_attrs(node),
     process_inlines(inlines) ++ process_blocks(blocks) ++ process_blocks(nested)}
  end

  def to_html_ast(%{type: :list, blocks: blocks, nested: nested, inlines: inlines} = node) do
    {"li", node_attrs(node),
     process_inlines(inlines) ++ process_blocks(blocks) ++ process_blocks(nested)}
  end

  def to_html_ast(%{type: :sep, options: %{type: _sep_type}} = node) do
    # ["line", "stars", "asterism", "dinkus"]
    {"hr", node_attrs(node), ""}
  end

  def to_html_ast(%{type: :quote, nested: nested} = node) do
    {"blockquote", node_attrs(node), process_blocks(nested)}
  end

  def to_html_ast(%{type: :footnote, nested: nested} = node) do
    {"p", node_attrs(node), process_blocks(nested)}
  end

  def to_html_ast(%{type: :verbatim, raw_lines: raw_lines} = node) do
    {"pre", node_attrs(node), raw_lines |> Enum.map(&elem(&1, 2)) |> Enum.join("\n")}
  end

  def to_html_ast(%{type: :slot, nested: nested} = node) do
    {"p", node_attrs(node), process_blocks(nested)}
  end

  def to_html_ast(%{type: :title, inlines: inlines} = node) do
    {"div", node_attrs(node), process_inlines(inlines)}
  end

  def node_attrs(%{type: type, line_number: n} = node) do
    classes =
      case Map.get(@classes, type, "") do
        by_level when is_map(by_level) ->
          Map.get(by_level, Map.get(node, :level, 1), "")

        class ->
          class
      end

    [{"class", classes}, {"id", "preview-ref-#{n}"}]
  end

  #### Inlines

  def process_inlines(inlines) when is_list(inlines) do
    Enum.map(inlines, &process_inlines/1) |> Enum.filter(&(&1 != nil)) |> List.flatten()
  end

  def process_inlines({:string, str}), do: str
  def process_inlines(:linebreak), do: {"br", [], []}

  def process_inlines({:emph, inlines}),
    do: {"span", [{"class", "italic"}], process_inlines(inlines)}

  def process_inlines({:underline, inlines}),
    do: {"span", [{"class", "underline"}], process_inlines(inlines)}

  def process_inlines({:strong, inlines}),
    do: {"span", [{"class", "font-bold"}], process_inlines(inlines)}

  def process_inlines({:strikeout, inlines}),
    do: {"del", [{"class", "line-through"}], process_inlines(inlines)}

  #    do: {"span", [{"class", "line-through"}], process_inlines(inlines)}

  def process_inlines({:superscript, inlines}), do: {"sup", [], process_inlines(inlines)}

  def process_inlines({:subscript, inlines}), do: {"sub", [], process_inlines(inlines)}

  def process_inlines({:eex_tag, _, str}), do: {"pre", [], str}

  def process_inlines(str), do: {"pre", [], inspect(str)}

  def process_blocks([]), do: []

  def process_blocks(blocks) when is_list(blocks) do
    blocks |> Enum.map(&to_html_ast/1) |> Enum.filter(&(&1 != nil)) |> List.flatten()
  end

  def process_blocks(str) when is_binary(str), do: str
end
