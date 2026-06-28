defmodule Hoverscript.Converter.ToLatex do
  @moduledoc """
  Converts a Hoverscript AST to LaTeX.

  By default, output is a full LaTeX document rendered from an EEx template
  (`priv/latex/document.eex`). Pass `:fragment, true` to receive only the
  converted body (no preamble or `\\begin{document}` wrapper).

  ## Options

    * `:fragment` - when `true`, return body content only
    * `:template` - `:default` or a path to a custom `.eex` template
    * `:documentclass` - LaTeX document class (default: `"article"`)
    * `:class_options` - list of class options (default: `["11pt", "a4paper"]`)
    * `:packages` - extra package names to include
    * `:package_options` - map of package name to option keyword list
    * `:babel` - babel language option (e.g. `"english"`)
    * `:title`, `:author`, `:date` - document metadata for `\\maketitle`
    * `:preamble` - extra raw LaTeX inserted before `\\begin{document}`
    * `:heading_commands` - map of Hoverscript heading level (1..6) to LaTeX command name
    * `:listings` - when `true`, use `lstlisting` for verbatim blocks with a `lang` option

  ## Headings

  Hoverscript headings form an outline tree (`heading.nested`). LaTeX section
  commands are flat and sequential. This converter emits a section command for
  each heading, then recursively converts `nested` blocks as following content
  (including sub-headings) — never wrapped in nested LaTeX section environments.
  """

  @article_commands %{
    1 => "section",
    2 => "subsection",
    3 => "subsubsection",
    4 => "paragraph",
    5 => "subparagraph",
    6 => "subparagraph"
  }

  @report_commands %{
    1 => "chapter",
    2 => "section",
    3 => "subsection",
    4 => "subsubsection",
    5 => "paragraph",
    6 => "subparagraph"
  }

  @default_packages ~w(inputenc fontenc hyperref geometry graphicx ulem)

  @default_package_options %{
    "inputenc" => [utf8: true],
    "fontenc" => [T1: true],
    "geometry" => [margin: "2.5cm"],
    "ulem" => [normalem: true]
  }

  @doc """
  Converts a Hoverscript AST to a LaTeX string.
  """
  def to_latex(ast, opts \\ [])

  def to_latex(%{type: :document, children: children} = _ast, opts) do
    opts = normalize_opts(opts)
    {opts, body_children} = extract_title_metadata(children, opts)
    body = process_blocks(body_children, opts)

    if opts[:fragment] do
      body
    else
      render_document(body, opts)
    end
  end

  def to_latex(_ast, _opts), do: ""

  #### Document template

  defp render_document(body, opts) do
    template = template_path(opts)
    assigns = template_assigns(body, opts)

    EEx.eval_file(template, assigns: assigns)
  end

  defp template_path(opts) do
    case Keyword.get(opts, :template, :default) do
      :default -> default_template_path()
      path when is_binary(path) -> path
    end
  end

  defp default_template_path do
    Path.join(:code.priv_dir(:hoverscript), "latex/document.eex")
  end

  defp template_assigns(body, opts) do
    title = opts[:title]
    author = opts[:author]
    date = opts[:date]

    %{
      documentclass: opts[:documentclass],
      class_options: Enum.join(opts[:class_options], ","),
      usepackage_lines: build_usepackage_lines(opts),
      preamble_extra: opts[:preamble] || "",
      title: title && escape_latex(title),
      author: author && escape_latex(author),
      date: date,
      maketitle: title != nil and title != "",
      body: body
    }
  end

  defp build_usepackage_lines(opts) do
    packages =
      (@default_packages ++ List.wrap(opts[:packages]))
      |> Enum.uniq()

    package_options =
      @default_package_options
      |> Map.merge(Map.new(opts[:package_options] || [], fn {k, v} -> {to_string(k), v} end))

    packages
    |> Enum.map(fn pkg ->
      pkg = to_string(pkg)
      options = Map.get(package_options, pkg, [])

      case format_package_options(options) do
        "" -> "\\usepackage{#{pkg}}"
        opt_str -> "\\usepackage[#{opt_str}]{#{pkg}}"
      end
    end)
    |> maybe_add_babel(opts[:babel])
  end

  defp maybe_add_babel(lines, nil), do: lines
  defp maybe_add_babel(lines, ""), do: lines

  defp maybe_add_babel(lines, lang) do
    lines ++ ["\\usepackage[#{lang}]{babel}"]
  end

  defp format_package_options([]), do: ""

  defp format_package_options(options) do
    options
    |> Enum.map(fn
      {key, value} when is_boolean(value) and value -> Atom.to_string(key)
      {key, value} -> "#{key}=#{value}"
    end)
    |> Enum.join(",")
  end

  defp extract_title_metadata(children, opts) do
    case Enum.find(children, &(&1.type == :title)) do
      nil ->
        {opts, children}

      title_node ->
        title_text = title_node |> Map.get(:inlines, []) |> inlines_to_plain_text()

        opts =
          opts
          |> Keyword.put_new(:title, title_text)
          |> Keyword.update(:author, nil, & &1)

        {opts, Enum.reject(children, &(&1.type == :title))}
    end
  end

  defp inlines_to_plain_text(inlines) when is_list(inlines) do
    inlines
    |> Enum.map(&inline_to_plain_text/1)
    |> Enum.join()
    |> String.trim()
  end

  defp inline_to_plain_text({:string, str}), do: str
  defp inline_to_plain_text(:linebreak), do: " "

  defp inline_to_plain_text({tag, nested}) when tag in [:emph, :strong, :underline, :strikeout, :superscript, :subscript] do
    inlines_to_plain_text(nested)
  end

  defp inline_to_plain_text({:eex_tag, _, str}), do: str

  defp inline_to_plain_text({:options, _meta, nested}) when is_list(nested) do
    inlines_to_plain_text(nested)
  end

  defp inline_to_plain_text(_), do: ""

  defp normalize_opts(opts) do
    documentclass = Keyword.get(opts, :documentclass, "article")

    heading_commands =
      Keyword.get_lazy(opts, :heading_commands, fn ->
        commands_for_documentclass(documentclass)
      end)

    opts
    |> Keyword.put_new(:documentclass, documentclass)
    |> Keyword.put_new(:class_options, ["11pt", "a4paper"])
    |> Keyword.put_new(:packages, [])
    |> Keyword.put_new(:package_options, %{})
    |> Keyword.put_new(:fragment, false)
    |> Keyword.put_new(:listings, false)
    |> Keyword.put(:heading_commands, heading_commands)
  end

  defp commands_for_documentclass("report"), do: @report_commands
  defp commands_for_documentclass("book"), do: @report_commands
  defp commands_for_documentclass(_), do: @article_commands

  #### Blocks

  defp to_latex_block(%{type: :literal}, _opts), do: nil

  defp to_latex_block(%{type: :para, inlines: inlines} = node, opts) do
    options = Map.get(node, :options, %{})
    align = Map.get(options, :align, "justify")
    content = process_inlines(inlines, opts)

    case align do
      "center" -> "\\begin{center}\n#{content}\n\\end{center}\n\n"
      "right" -> "\\begin{flushright}\n#{content}\n\\end{flushright}\n\n"
      "left" -> "\\begin{flushleft}\n#{content}\n\\end{flushleft}\n\n"
      _ -> "#{content}\n\n"
    end
  end

  defp to_latex_block(%{type: :heading, level: level, inlines: inlines, nested: nested}, opts) do
    cmd = heading_command(level, opts)
    title = process_inlines(inlines, opts)
    "\\#{cmd}{#{title}}\n\n" <> process_blocks(nested, opts)
  end

  defp to_latex_block(%{type: :ordered_list, items: items}, opts) do
    "\\begin{enumerate}\n" <> process_blocks(items, opts) <> "\\end{enumerate}\n\n"
  end

  defp to_latex_block(%{type: :bullet_list, items: items}, opts) do
    "\\begin{itemize}\n" <> process_blocks(items, opts) <> "\\end{itemize}\n\n"
  end

  defp to_latex_block(%{type: :num, blocks: blocks, nested: nested, inlines: inlines}, opts) do
    item_content =
      process_inlines(inlines, opts) <>
        process_blocks(blocks, opts) <>
        process_blocks(nested, opts)

    "\\item #{item_content}\n"
  end

  defp to_latex_block(%{type: :list, blocks: blocks, nested: nested, inlines: inlines}, opts) do
    item_content =
      process_inlines(inlines, opts) <>
        process_blocks(blocks, opts) <>
        process_blocks(nested, opts)

    "\\item #{item_content}\n"
  end

  defp to_latex_block(%{type: :sep, options: options}, _opts) do
    case Map.get(options, :type, "line") do
      "stars" -> "\\bigskip\n\\noindent ***\n\\bigskip\n\n"
      "asterism" -> "\\bigskip\n\\noindent \\S\n\\bigskip\n\n"
      "dinkus" -> "\\bigskip\n\\noindent * * *\n\\bigskip\n\n"
      _ -> "\\noindent\\rule{\\linewidth}{0.4pt}\n\n"
    end
  end

  defp to_latex_block(%{type: :quote, nested: nested}, opts) do
    "\\begin{quote}\n" <> process_blocks(nested, opts) <> "\\end{quote}\n\n"
  end

  defp to_latex_block(%{type: :footnote, nested: nested}, opts) do
    content = process_blocks(nested, opts) |> String.trim()
    "\\footnote{#{content}}\n\n"
  end

  defp to_latex_block(%{type: :verbatim, raw_lines: raw_lines} = node, opts) do
    content = raw_lines |> Enum.map(&elem(&1, 2)) |> Enum.join("\n")
    options = Map.get(node, :options, %{})
    lang = Map.get(options, :lang)

    cond do
      opts[:listings] and lang != nil ->
        "\\begin{lstlisting}[language=#{lang}]\n#{content}\n\\end{lstlisting}\n\n"

      true ->
        "\\begin{verbatim}\n#{content}\n\\end{verbatim}\n\n"
    end
  end

  defp to_latex_block(%{type: :slot, nested: nested}, opts) do
    process_blocks(nested, opts)
  end

  defp to_latex_block(%{type: :title}, _opts), do: nil

  defp to_latex_block(node, _opts) do
    raise ArgumentError,
          "unsupported AST node type for LaTeX conversion: #{inspect(Map.get(node, :type))}"
  end

  defp process_blocks(blocks, opts) when is_list(blocks) do
    blocks
    |> Enum.map(&to_latex_block(&1, opts))
    |> Enum.reject(&is_nil/1)
    |> Enum.join()
  end

  defp process_blocks(str, _opts) when is_binary(str), do: str

  defp heading_command(level, opts) do
    commands = opts[:heading_commands]

    Map.get(commands, level) ||
      Map.get(commands, 6) ||
      "subparagraph"
  end

  #### Inlines

  defp process_inlines(inlines, opts) when is_list(inlines) do
    inlines
    |> Enum.map(&process_inlines(&1, opts))
    |> Enum.reject(&is_nil/1)
    |> Enum.join()
  end

  defp process_inlines({:string, str}, _opts), do: escape_latex(str)
  defp process_inlines(:linebreak, _opts), do: "\\\\"

  defp process_inlines({:emph, inlines}, opts),
    do: "\\emph{#{process_inlines(inlines, opts)}}"

  defp process_inlines({:underline, inlines}, opts),
    do: "\\underline{#{process_inlines(inlines, opts)}}"

  defp process_inlines({:strong, inlines}, opts),
    do: "\\textbf{#{process_inlines(inlines, opts)}}"

  defp process_inlines({:strikeout, inlines}, opts),
    do: "\\sout{#{process_inlines(inlines, opts)}}"

  defp process_inlines({:superscript, inlines}, opts),
    do: "\\textsuperscript{#{process_inlines(inlines, opts)}}"

  defp process_inlines({:subscript, inlines}, opts),
    do: "\\textsubscript{#{process_inlines(inlines, opts)}}"

  defp process_inlines({:eex_tag, _, str}, _opts), do: str

  defp process_inlines({:options, %{tag: :i_link, options: link_opts}, inlines}, opts) do
    url = Map.get(link_opts, :url, "")
    text = process_inlines(inlines, opts)
    "\\href{#{url}}{#{text}}"
  end

  defp process_inlines({:options, %{tag: :i_image, options: image_opts}, _inlines}, _opts) do
    path = Map.get(image_opts, :name, Map.get(image_opts, :url, ""))
    width = Map.get(image_opts, :width)
    height = Map.get(image_opts, :height)

    opts_str =
      [width: width, height: height]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> case do
        [] -> ""
        parts -> "[#{Enum.join(parts, ",")}]"
      end

    "\\includegraphics#{opts_str}{#{path}}"
  end

  defp process_inlines({:options, %{tag: :i_footnote}, inlines}, opts) do
    "\\footnote{#{process_inlines(inlines, opts)}}"
  end

  defp process_inlines(other, _opts), do: inspect(other)

  @doc false
  def escape_latex(str) when is_binary(str) do
    str
    |> String.replace("\\", "\\textbackslash{}")
    |> String.replace("&", "\\&")
    |> String.replace("%", "\\%")
    |> String.replace("$", "\\$")
    |> String.replace("#", "\\#")
    |> String.replace("_", "\\_")
    |> String.replace("{", "\\{")
    |> String.replace("}", "\\}")
    |> String.replace("~", "\\textasciitilde{}")
    |> String.replace("^", "\\textasciicircum{}")
  end
end
