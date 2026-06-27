# Hoverscript Project Build

This page describes how to build a **Hoverscript project directory** — a small “site” made of several `.hvt` files, optional TOML data, EEx templates, and a single entry point that expands into one document before parsing.

> **Single-file parsing:** To parse one `.hvt` string or file without expansion, use [`Hoverscript.parse/1`](Hoverscript.html#parse/1) or [`Hoverscript.parse_file/1`](Hoverscript.html#parse_file/1). See the [Hoverscript Reference Guide](REFERENCE.html) for the language itself.

## Table of Contents

1. [Overview](#overview)
2. [Project layout](#project-layout)
3. [Build pipeline](#build-pipeline)
4. [API usage](#api-usage)
5. [CLI usage](#cli-usage)
6. [TOML data files](#toml-data-files)
7. [Import syntax](#import-syntax)
8. [EEx templates](#eex-templates)
9. [Source map and errors](#source-map-and-errors)
10. [Complete example](#complete-example)
11. [Limitations](#limitations)

## Overview

A Hoverscript project is a directory that contains:

| Item | Default | Purpose |
|------|---------|---------|
| Entry file | `main.hvt` | Root document; expansion starts here |
| TOML files | `*.toml` at project root | Data exposed as EEx assigns |
| Partial files | any `.hvt` path | Included via `:import` or `import_hvt/2` |

The build step **expands** the entry file (runs EEx, resolves imports) into a single Hoverscript document in memory, then **parses** it with the standard pipeline. Parse errors can be traced back to the original source file and line.

## Project layout

```
my_project/
├── main.hvt              # entry point (override with :entry option)
├── site.toml             # → @site in EEx
├── chapters.toml         # → @chapters in EEx
└── partials/
    ├── header.hvt
    └── chapter.hvt
```

Paths in `:import` directives are **relative to the project root**, not to the file that imports them.

A working demo lives in [`examples/build_project/`](../examples/build_project/) in the repository.

## Build pipeline

```
┌─────────────┐     ┌──────────────────────┐     ┌─────────────┐     ┌──────────────┐
│  *.toml     │────▶│  EEx + :import       │────▶│  Expanded   │────▶│  AST         │
│  → assigns  │     │  (recursive expand)  │     │  .hvt text  │     │  (+ errors)  │
└─────────────┘     └──────────────────────┘     └─────────────┘     └──────────────┘
                              │
                              ▼
                     Source map (line → file)
```

1. **Load TOML** — every `*.toml` in the project root becomes an assign (`site.toml` → `@site`).
2. **Expand entry** — evaluate EEx in each file (except inside `:verbatim` blocks), resolve `:import` directives recursively.
3. **Parse** — run the normal parser on the expanded text.
4. **Remap errors** — attach original `file` + `line` to each parse error via the source map.

## API usage

```elixir
# Success: AST + metadata
{:ok, ast, meta} = Hoverscript.build("examples/build_project")

meta.source_map   # line mapping for error reporting
meta.expanded     # final Hoverscript text (String.t())
meta.assigns      # merged TOML + extra assigns
meta.project_dir
meta.entry

# Convert to HTML
html = Hoverscript.ast_to_html(ast)

# Raising version
ast = Hoverscript.build!("examples/build_project")
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `:entry` | `"main.hvt"` | Entry file relative to the project directory |
| `:assigns` | `%{}` | Extra EEx assigns merged on top of TOML data |
| `:dump_expanded` | `nil` | When set to a path, write the expanded HVT text to that file (useful for debugging) |

### Return values

**Success** — `{:ok, ast, meta}`

**Expansion failure** — `{:error, :expand, errors}`

Common expansion errors:

| Error | Meaning |
|-------|---------|
| `{:entry_not_found, path}` | Entry file does not exist |
| `{:file_not_found, details}` | Imported or referenced file missing |
| `{:import_cycle, details}` | Circular import chain detected |
| `{:eex_error, details}` | EEx evaluation failed |
| `{:toml_parse_error, details}` | Invalid TOML syntax |
| `{:toml_read_error, details}` | TOML file could not be read |

**Parse failure** — `{:error, :parse, errors, ast}`

A partial AST is still returned. Errors include both merged-line positions and remapped source locations (see [Source map and errors](#source-map-and-errors)).

## CLI usage

```bash
# Build the demo project
mix hvt_build examples/build_project

# Custom entry file
mix hvt_build my_project --entry index.hvt

# Dump expanded text for inspection
mix hvt_build examples/build_project --dump-expanded /tmp/expanded.hvt

# Print HTML on success
mix hvt_build examples/build_project --html
```

The task exits with code `1` on expansion or parse failure and prints error details.

## TOML data files

Every `*.toml` file in the **project root** is loaded at build time. The file stem (without extension) becomes the assign key:

| File | Assign | Example access in EEx |
|------|--------|----------------------|
| `site.toml` | `@site` | `<%= @site["title"] %>` |
| `chapters.toml` | `@chapters` | `<%= for ch <- @chapters do %>` |

### Example: `site.toml`

```toml
title = "Hoverscript Build Demo"
author = "Hoverscript Team"
```

Used in a partial:

```hoverscript
:= <%= @site["title"] %>

:para by <%= @site["author"] %>
```

### Example: `chapters.toml`

```toml
[[chapters]]
title = "Getting Started"
level = 2

[[chapters]]
title = "Advanced Topics"
level = 2
```

When the TOML file stem matches the sole top-level key (here `chapters`), the assign receives the **inner value** directly — `@chapters` is a list, not `%{"chapters" => [...]}`.

For files like `site.toml` with multiple top-level keys, `@site` is the full decoded map.

### Extra assigns

Pass additional data from Elixir:

```elixir
Hoverscript.build("my_project", assigns: %{version: "1.0"})
```

Then use `<%= @version %>` in any `.hvt` file.

## Import syntax

Imports are **preprocessor directives**. They are expanded before parsing and never appear in the final AST.

An import **replaces** the directive line with the full content of the target file (which itself may contain EEx and further imports).

### Short form

```hoverscript
:import partials/header.hvt
```

The `.hvt` extension is optional; `partials/header` resolves to `partials/header.hvt`.

### With parameters (option line)

Parameters are merged into the EEx assigns **for the imported file only**:

```hoverscript
[title=Introduction, level=2]
:import partials/chapter.hvt
```

Inside `partials/chapter.hvt`:

```hoverscript
:heading <%= @title %>

:para This is chapter **<%= @title %>** at level <%= @level %>.
```

### Long form with inline parameters

```hoverscript
:import:partials/chapter.hvt:title=Introduction,level=2/
```

Path first, then comma-separated `key=value` pairs before the closing `/`.

### Import cycles

Circular imports are detected and rejected:

```
main.hvt → a.hvt → b.hvt → a.hvt   ❌  {:import_cycle, ...}
```

Importing the **same file with different parameters** is allowed (not treated as a cycle).

## EEx templates

During the build phase, EEx tags (`<%`, `<%=`, `<%#`) are **executed** and replaced with generated Hoverscript text. This differs from single-file parsing, where EEx tags are preserved as inline nodes for later evaluation.

EEx is **not** evaluated inside `:verbatim` blocks — content there is left unchanged, matching parser behaviour.

### Variables

Use `@key` to access assigns from TOML and import parameters:

```hoverscript
:= <%= @site["title"] %>
```

### Loops and imports

Generate import directives dynamically:

```hoverscript
<%= for chapter <- @chapters do %>
[title=<%= chapter["title"] %>,level=<%= chapter["level"] %>]
:import partials/chapter.hvt
<% end %>
```

Each iteration produces an option line + import that expands `partials/chapter.hvt` with the given parameters.

### Inline import: `import_hvt/2`

For inserting partial content inside a line (not as a block import), use:

```hoverscript
:para See also: <%= Hoverscript.Build.EExHelpers.import_hvt("partials/snippet.hvt") %>.
```

With parameters:

```hoverscript
<%= Hoverscript.Build.EExHelpers.import_hvt("partials/chapter.hvt", title: "Appendix", level: 3) %>
```

> **Note:** Block imports (`:import`) provide precise source-map line tracking. Content inserted via `import_hvt/2` inside EEx is mapped to the EEx source line rather than to individual lines in the partial.

## Source map and errors

The expander records, for each line of the merged document, which source file and line it came from.

When parsing fails, errors are enriched:

```elixir
{:error, :parse, errors, _ast} = Hoverscript.build("my_project")

# errors is a map like:
# %{
#   bad_tagline: [
#     {{:unknown_tag, _details}, %{
#       merged: {12, 0, 12, 0},
#       source: %{
#         start: %{file: "partials/broken.hvt", line: 3},
#         end:   %{file: "partials/broken.hvt", line: 3}
#       }
#     }}
#   ]
# }
```

- **`merged`** — line/column in the expanded document (what the parser sees)
- **`source.start` / `source.end`** — original file and line in your project

Line numbers are **0-based**, consistent with the parser's internal line indexing.

## Complete example

This mirrors [`examples/build_project/`](../examples/build_project/).

### `main.hvt`

```hoverscript
:import partials/header.hvt

:=== Chapters

<%= for chapter <- @chapters do %>
[title=<%= chapter["title"] %>,level=<%= chapter["level"] %>]
:import partials/chapter.hvt
<% end %>

:para Built from a project directory with TOML data and imports.
```

### `partials/header.hvt`

```hoverscript
:= <%= @site["title"] %>

:para by <%= @site["author"] %>

:sep
```

### `partials/chapter.hvt`

```hoverscript
:heading <%= @title %>

:para This is chapter **<%= @title %>** at level <%= @level %>.
```

### Build and inspect

```elixir
{:ok, ast, meta} = Hoverscript.build("examples/build_project")

IO.puts(meta.expanded)
# =>
# := Hoverscript Build Demo
# :para by Hoverscript Team
# :sep
# ...
# :heading Getting Started
# :para This is chapter **Getting Started** at level 2.
# ...
```

Or from the command line:

```bash
mix hvt_build examples/build_project --dump-expanded /tmp/out.hvt
```

## Limitations

| Topic | Behaviour |
|-------|-----------|
| **EEx in verbatim** | Not evaluated during build |
| **`import_hvt/2` source map** | Lines map to the EEx call site, not the partial |
| **TOML scope** | Only `*.toml` in the project root (not subdirectories) |
| **Code execution** | EEx runs arbitrary Elixir — only build trusted projects |
| **Post-build EEx** | After build, the AST contains plain Hoverscript; no `<% %>` tags remain unless they were inside verbatim blocks |

For single-file workflows where EEx should be preserved in the AST for runtime evaluation, use [`Hoverscript.parse/1`](Hoverscript.html#parse/1) directly instead of `Hoverscript.build/2`.
