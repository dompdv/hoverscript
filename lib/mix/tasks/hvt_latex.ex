defmodule Mix.Tasks.HvtLatex do
  @moduledoc """
  Builds a Hoverscript project or file and writes LaTeX output.

  Project directories are expanded (TOML, imports, EEx) before conversion,
  like `mix hvt_build`. A single `.hvt` file is parsed directly.

  ## Usage

      mix hvt_latex examples/build_project
      mix hvt_latex examples/build_project --output _build/main.tex
      mix hvt_latex examples/build_project --pdf
      mix hvt_latex examples/heading_example.hvt --stdout
      mix hvt_latex examples/build_project --documentclass report --babel english

  ## Options

    * `--entry` - entry file for project directories (default: `main.hvt`)
    * `--output`, `-o` - write LaTeX to this path (default: `<dir>/_build/<entry>.tex`)
    * `--dump-expanded` - write expanded HVT text to this path (projects only)
    * `--stdout` - print LaTeX to stdout instead of writing a file
    * `--pdf` - run a LaTeX engine on the generated `.tex` file to produce a PDF
    * `--engine` - LaTeX engine for `--pdf` (`pdflatex`, `xelatex`, `lualatex`; default: `pdflatex`)
    * `--documentclass` - LaTeX document class passed to the converter
    * `--class-options` - comma-separated class options (e.g. `11pt,a4paper`)
    * `--babel` - babel language option
    * `--author`, `--title`, `--date` - document metadata for `\\maketitle`
    * `--fragment` - emit body content only (no preamble or `\\begin{document}`)
    * `--template` - path to a custom document `.eex` template
  """

  use Mix.Task

  @shortdoc "Build Hoverscript and write LaTeX (optionally PDF)"

  @switches [
    entry: :string,
    output: :string,
    dump_expanded: :string,
    stdout: :boolean,
    pdf: :boolean,
    engine: :string,
    documentclass: :string,
    class_options: :string,
    babel: :string,
    author: :string,
    title: :string,
    date: :string,
    fragment: :boolean,
    template: :string
  ]

  @aliases [
    o: :output
  ]

  @engines ~w(pdflatex xelatex lualatex)

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches, aliases: @aliases)

    if invalid != [] do
      Mix.raise("invalid arguments: #{inspect(invalid)}")
    end

    target = positional |> List.first() |> default_target() |> Path.expand()

    unless File.exists?(target) do
      Mix.raise("path not found: #{target}")
    end

    latex_opts = build_latex_opts(opts)

    {latex, source_label} =
      if File.dir?(target) do
        build_project_latex(target, opts, latex_opts)
      else
        build_file_latex(target, latex_opts)
      end

    output_path = output_path(target, opts)

    cond do
      opts[:stdout] ->
        Mix.shell().info(latex)

      true ->
        write_output!(output_path, latex)
        Mix.shell().info("Wrote #{output_path}")
    end

    if opts[:pdf] do
      unless opts[:stdout] do
        compile_pdf!(output_path, opts)
      else
        Mix.shell().error("--pdf requires a written .tex file; omit --stdout")
        System.halt(1)
      end
    end

    Mix.shell().info("LaTeX build succeeded (#{source_label}).")
  end

  defp default_target(nil), do: "."
  defp default_target(path), do: path

  defp build_project_latex(dir, opts, latex_opts) do
    build_opts =
      [
        entry: opts[:entry],
        dump_expanded: opts[:dump_expanded]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    Mix.shell().info("Building #{dir}...")

    case Hoverscript.build(dir, build_opts) do
      {:ok, ast, meta} ->
        latex = Hoverscript.ast_to_latex(ast, latex_opts)
        {latex, "#{line_count(meta.expanded)} expanded lines"}

      {:error, :expand, errors} ->
        Mix.shell().error("Expansion failed:")
        print_expand_errors(errors)
        System.halt(1)

      {:error, :parse, errors, _ast} ->
        Mix.shell().error("Parse failed:")
        print_parse_errors(errors)
        System.halt(1)
    end
  end

  defp build_file_latex(path, latex_opts) do
    unless String.ends_with?(path, ".hvt") do
      Mix.raise("expected a directory or .hvt file, got: #{path}")
    end

    Mix.shell().info("Parsing #{path}...")

    case Hoverscript.parse_file(path) do
      {:ok, ast} ->
        {Hoverscript.ast_to_latex(ast, latex_opts), Path.basename(path)}

      {:error, %{file: reason}, _} ->
        Mix.raise("read failed: #{inspect(reason)}")

      {:error, errors, _ast} ->
        Mix.shell().error("Parse failed:")
        print_parse_errors(errors)
        System.halt(1)
    end
  end

  defp build_latex_opts(opts) do
    base =
      [
        documentclass: opts[:documentclass],
        babel: opts[:babel],
        author: opts[:author],
        title: opts[:title],
        date: opts[:date],
        fragment: opts[:fragment],
        template: template_opt(opts[:template])
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case class_options(opts[:class_options]) do
      nil -> base
      class_options -> Keyword.put(base, :class_options, class_options)
    end
  end

  defp template_opt(nil), do: nil
  defp template_opt(path), do: path

  defp class_options(nil), do: nil

  defp class_options(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp output_path(target, opts) do
    cond do
      opts[:stdout] ->
        nil

      opts[:output] ->
        Path.expand(opts[:output])

      File.dir?(target) ->
        entry = opts[:entry] || "main.hvt"
        base = entry |> Path.basename() |> Path.rootname(".hvt")
        Path.join([target, "_build", "#{base}.tex"])

      true ->
        target |> Path.rootname(".hvt") |> Kernel.<>(".tex")
    end
  end

  defp write_output!(path, latex) do
    path |> Path.dirname() |> File.mkdir_p!()

    case File.write(path, latex) do
      :ok ->
        :ok

      {:error, reason} ->
        Mix.raise("failed to write #{path}: #{inspect(reason)}")
    end
  end

  defp compile_pdf!(tex_path, opts) do
    engine = opts[:engine] || "pdflatex"

    unless engine in @engines do
      Mix.raise("unsupported engine #{inspect(engine)}; expected one of #{inspect(@engines)}")
    end

    unless System.find_executable(engine) do
      Mix.shell().error("#{engine} not found on PATH")
      System.halt(1)
    end

    out_dir = Path.dirname(tex_path)
    tex_name = Path.basename(tex_path)
    args = ["-interaction=nonstopmode", "-output-directory", out_dir, tex_name]

    Mix.shell().info("Running #{engine}...")

    for pass <- 1..2 do
      case System.cmd(engine, args, cd: out_dir, stderr_to_stdout: true) do
        {output, 0} ->
          if pass == 2 do
            pdf_path = tex_path |> Path.rootname(".tex") |> Kernel.<>(".pdf")
            Mix.shell().info("Wrote #{pdf_path}")
          end

          output

        {output, _code} ->
          Mix.shell().error("#{engine} failed (pass #{pass}):")
          Mix.shell().error(output)
          System.halt(1)
      end
    end
  end

  defp line_count(text), do: text |> String.split("\n") |> length()

  defp print_expand_errors(errors) do
    for error <- List.wrap(errors) do
      Mix.shell().error("  #{format_expand_error(error)}")
    end
  end

  defp print_parse_errors(errors) when is_map(errors) do
    for {category, records} <- errors,
        record <- List.wrap(records) do
      Mix.shell().error("  #{category}: #{inspect(record)}")
    end
  end

  defp format_expand_error({:entry_not_found, path}), do: "entry file not found: #{path}"

  defp format_expand_error({:file_not_found, details}) do
    "file not found: #{details.path} (#{inspect(details.reason)})"
  end

  defp format_expand_error({:import_cycle, details}) do
    "import cycle at #{details.file} importing #{details.import}"
  end

  defp format_expand_error({:eex_error, details}) do
    "EEx error in #{details.file}:#{details.line}: #{details.reason}"
  end

  defp format_expand_error({:toml_parse_error, details}) do
    "TOML parse error in #{details.file}: #{inspect(details.reason)}"
  end

  defp format_expand_error({:toml_read_error, details}) do
    "TOML read error in #{details.file}: #{inspect(details.reason)}"
  end

  defp format_expand_error({:dump_failed, details}) do
    "failed to write expanded file #{details.path}: #{inspect(details.reason)}"
  end

  defp format_expand_error(other), do: inspect(other)
end
