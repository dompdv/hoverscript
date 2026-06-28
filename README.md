# Hoverscript

A lightweight markup language and Elixir parser for writing structured documents. Hoverscript is designed for people who need professional-looking documents without wrestling with a word processor or a heavyweight typesetting system.

## Rationale

Many non-technical professionals — lawyers, legal teams, consultants, and others — spend a large part of their day producing documents with tools that were never meant for the job. Word processors and similar WYSIWYG editors are everywhere, but they create friction:

- **Time lost to formatting** — authors spend hours nudging margins, fixing spacing, and chasing visual consistency instead of writing the substance of the document.
- **Styles remain a mystery** — features like paragraph styles, which are essential for serious document management, are rarely understood or used consistently.
- **Poor fit for complex work** — multi-document projects, reusable sections, and data-driven content (contracts from templates, reports built from parts) are awkward at best in a single monolithic file.

A **markup language** is a better fit: you focus on content, and an engine applies formatting automatically. **LaTeX** can produce beautiful, unlimited output, but its learning curve is steep for this audience. **Markdown** is simpler, but it falls short in two important ways:

1. **Limited formatting** — everyday needs like centering a paragraph, controlling alignment, or framing a block are either missing or bolted on inconsistently.
2. **Layout tied to meaning** — in Markdown, structure often depends on indentation and line breaks. Changing how the source looks can change what it *means*. Reading raw Markdown is not always pleasant, and automatic reformatting is limited — a bit like code that must stay within a strict column width because readability depends on it.

**Hoverscript** is an attempt to address this:

- A **simple, lightweight markup language** — easier to learn than LaTeX, more regular than Markdown.
- **Natural formatting directives** — alignment, frames, list levels, and similar options are first-class, not afterthoughts.
- **Indentation- and line-width–insensitive** — whitespace in the source does not change semantics; you write content, not layout.
- **Built-in auto-formatting** — a formatter rewrites your source so it *looks* like the output: logical indentation, consistent line width, visual alignment of tags and text.
- **Multi-document projects** — cross-file imports, EEx templating, and TOML data files let you bundle and merge documents (templates, chapters, reusable clauses).

On a more personal note, building Hoverscript was also an opportunity to write a parser by hand — a rewarding learning exercise in language design and incremental parsing.

## Language at a glance

Blocks are marked with a leading colon. Parameters can appear inline, on the line before the block, or both.

```hoverscript
:= Document title

:p A simple paragraph with no specific formatting. In Hoverscript, a document is made of blocks. 
   A block directive is identified by the fact that a ":" semi-colon is the first character of the line

[align=center]
:para A centered paragraph — something Markdown does not offer out of the box.

:para:left/Left-aligned text with **bold**, //italic//, and __underline__.

:=== Section heading

:* First bullet item
:** Nested item
:. Numbered item with [counter=3]

:quote
A nestable quote block.
:quote

:verbatim:lang=elixir/
def hello, do: :world
:verbatim
```

Inline formatting uses readable delimiters: `**bold**`, `//emphasis//`, `__underline__`, `~~strikeout~~`, `^^superscript^^`, `,,subscript,,`, and `::` for a line break.

See the [language reference](doc/REFERENCE.md) and [examples/hoverscript_guide.hvt](examples/hoverscript_guide.hvt) for the full syntax.

## Auto-formatting

Because indentation does not carry meaning, you can write compact, messy source. Running the formatter produces a readable layout that mirrors the logical structure and target appearance — constant line width, aligned tags, indented nesting.

**Before** (valid source, hard to read):

```hoverscript
:= My Document Title

[align=center]
:para This paragraph is centered and can be written on one long line without worrying about line breaks or indentation because the formatter will take care of that.

:para:left/Left-aligned paragraph with **bold** and //italic// formatting.

:* Item one that continues on the same line
:** Nested item
:* Item two

[align=right]
:para A right-aligned closing note.
```

**After** (`mix hvt_layout` or `Hoverscript.format/1`):

```hoverscript
:=        My Document Title

[align=center]
:para        This paragraph is centered and can be written on one long line without worrying about line breaks
                               or indentation because the formatter will take care of that.

:para:left/  Left-aligned paragraph with **bold** and //italic// formatting.

:*           Item one that continues on the same line
:**             Nested item
:*           Item two

[align=right]
:para                                                                            A right-aligned closing note.
```

The formatted text is still valid Hoverscript — parse it again and you get the same document structure.

## Bundling documents

For multi-file projects, a **build** step expands `:import` directives, substitutes variables from TOML data files, and parses the result as one document. A typical use case is a letter or contract template: a shared letterhead partial, plus a main file filled in from data.

```
letter/
├── main.hvt
├── client.toml           # → @client in templates
└── partials/
    └── letterhead.hvt
```

`client.toml`:

```toml
name = "Jean Dupont"
address = "12 rue de la Paix, 75002 Paris"
date = "27 June 2025"
```

`partials/letterhead.hvt`:

```hoverscript
:= Cabinet Dupont & Associés

:para 15 avenue de l'Opéra, 75001 Paris

:sep
```

`main.hvt`:

```hoverscript
:import partials/letterhead.hvt

:para Paris, <%= @client["date"] %>

:para Dear <%= @client["name"] %>,

:para We write to you regarding your file. You may be reached at <%= @client["address"] %>.

:para Yours sincerely,
```

The build inlines the letterhead, replaces the `<%= @client[...] %>` placeholders, and parses the merged text. You can then convert the result to HTML or LaTeX:

```elixir
{:ok, ast, _meta} = Hoverscript.build("letter")
html = Hoverscript.ast_to_html(ast)
File.write!("letter.html", html)

latex = Hoverscript.ast_to_latex(ast)
File.write!("letter.tex", latex)
```

See the [Project Build Guide](doc/BUILD.md) for the full syntax (parameterized imports, loops, and more). A runnable demo lives in [`examples/build_project/`](examples/build_project/).

## Usage

### Parse, format, and convert to HTML

```elixir
# Parse then convert to HTML
{:ok, ast} = Hoverscript.parse(hoverscript_text)
html = Hoverscript.ast_to_html(ast)

# One step: Hoverscript text → HTML
{:ok, html} = Hoverscript.text_to_html(hoverscript_text)
html = Hoverscript.text_to_html!(":= Title\n\n:para Hello **world**")

# Format source in memory
{:ok, formatted} = Hoverscript.format(messy_text)
formatted = Hoverscript.format!(messy_text, width: 80, column: 8, step: 2)
```

### Convert to LaTeX

The LaTeX converter produces a full document by default (preamble, packages, `\begin{document}`). Pass `fragment: true` for body content only.

```elixir
# Parse then convert to LaTeX
{:ok, ast} = Hoverscript.parse(hoverscript_text)
latex = Hoverscript.ast_to_latex(ast)
File.write!("output.tex", latex)

# One step: Hoverscript text → LaTeX
{:ok, latex} = Hoverscript.text_to_latex(hoverscript_text)
latex = Hoverscript.text_to_latex!(":= Title\n\n:para Hello **world**")

# Body only (no preamble)
latex = Hoverscript.ast_to_latex(ast, fragment: true)

# Custom document class and metadata
latex = Hoverscript.ast_to_latex(ast,
  documentclass: "report",
  class_options: ["12pt", "a4paper"],
  babel: "english",
  author: "Jane Doe"
)

# From a built project
{:ok, ast, _meta} = Hoverscript.build("examples/build_project")
latex = Hoverscript.ast_to_latex(ast)
File.write!("_build/main.tex", latex)
```

### Format files in place

The `hvt_layout` mix task scans a directory for `.hvt` files, parses each one, and writes the formatted result back when parsing succeeds.

```bash
mix hvt_layout examples
mix hvt_layout examples --width 80 --column 8 --step 2
```

### Build a project directory

```bash
mix hvt_build examples/build_project
mix hvt_build examples/build_project --dump-expanded /tmp/out.hvt --html
```

```elixir
{:ok, ast, meta} = Hoverscript.build("examples/build_project")

meta.expanded    # expanded Hoverscript text
meta.source_map  # line → original file (for error reporting)

html = Hoverscript.ast_to_html(ast)
File.write!("output.html", html)
```

### Build LaTeX (and optionally PDF)

The `hvt_latex` mix task builds a project directory or parses a single `.hvt` file, writes a `.tex` file, and can run a LaTeX engine to produce a PDF.

```bash
# Project directory (TOML + imports + EEx, like hvt_build)
mix hvt_latex examples/build_project
mix hvt_latex examples/build_project --output _build/main.tex
mix hvt_latex examples/build_project --pdf

# Single file
mix hvt_latex examples/heading_example.hvt
mix hvt_latex examples/heading_example.hvt --stdout

# Converter options
mix hvt_latex examples/build_project --documentclass report --babel english --author "Author"
mix hvt_latex examples/short_test.hvt --fragment -o body.tex
```

By default, project output is written to `_build/<entry>.tex` (e.g. `_build/main.tex`). Use `--pdf` to run `pdflatex` twice in the output directory (`--engine xelatex` or `lualatex` to override).

## Documentation

| Resource | Description |
|----------|-------------|
| [doc/REFERENCE.md](doc/REFERENCE.md) | Language reference |
| [doc/BUILD.md](doc/BUILD.md) | Multi-file projects (TOML, imports, EEx) |
| [doc/AST.md](doc/AST.md) | AST structure |
| [examples/doc_en.hvt](examples/doc_en.hvt) | Complete language specification |
| [examples/hoverscript_guide.hvt](examples/hoverscript_guide.hvt) | Guided tour of features |
| [examples/hvscript_example.hvt](examples/hvscript_example.hvt) | Comprehensive feature demo |
| [examples/build_project/](examples/build_project/) | Multi-file build demo |
