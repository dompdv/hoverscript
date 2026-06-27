# Hoverscript AST Reference

This document describes the **Abstract Syntax Tree** produced by `Hoverscript.Parser.Parse.parse/1`. It is aimed at developers who consume or transform the AST (HTML conversion, layout, custom tooling).

For Hoverscript **syntax** (what to write in `.hvt` files), see the [Hoverscript Reference Guide](REFERENCE.html).

## Quick start

```elixir
alias Hoverscript.Parser.Parse

case Parse.parse(hoverscript_source) do
  {:ok, ast} ->
    # ast is the root document node
    ast.children

  {:error, errors, ast} ->
    # errors is a map of error categories; ast is a partial tree
    {errors, ast}
end
```

See [Errors](ast/errors.html) for the error map structure.

## Parsing pipeline

The AST is built in five stages (`Hoverscript.Parser.Parse`):

1. **Tokenize lines** — classify each source line (`:line`, `:tagline`, `:blankline`, `:optionline`, `:continueline`, …).
2. **Check option lines** — validate `[param=value]` lines against the following tag line.
3. **Validate tag lines** — detect unknown tags and parameter errors.
4. **Build the tree** — stack-based incremental parser (`Hoverscript.Parser.ParseTokens`).
5. **Process inlines** — parse formatting within `joined_lines` (`Hoverscript.Parser.Inline`).

Stages 1–4 produce block structure; stage 5 adds the `inlines` field on text-bearing nodes.

## Root document node

Every successful or partial parse returns a map with `type: :document`:

| Field | Type | Description |
|-------|------|-------------|
| `type` | `:document` | Always present |
| `stage` | `:children` | Parser stage |
| `line_number` | integer | Usually `0` |
| `children` | list | Top-level block nodes |

### Top-level vs nested blocks

**Important:** several block types do not appear as direct `document.children` even when they look sequential in the source:

- **Headings** nest all following content of lower or equal outline level inside `heading.nested`, not as sibling `document.children`.
- **Lists, quotes, slots, footnotes** expose their content through `items`, `nested`, or `blocks` on the container node.

To collect all nodes of a given type regardless of depth, walk the tree recursively (see [Traversing the AST](#traversing-the-ast)).

## Node fields

All nodes are plain maps (`%{}`). **There is no single shared shape** — each `type` uses a different subset of fields. For example, `:document` only has `children`; `:sep` has no text at all; list items use both `nested` and `blocks` for different purposes.

See **[Node fields by type](ast/node_fields.html)** for:

- A **quick-reference matrix** (which fields each `type` uses)
- Per-type tables with **presence** (always / optional / unused) and **purpose**
- Where child nodes live (`children` vs `nested` vs `items` vs `blocks`)
- The text pipeline: `body` → `raw_lines` → `joined_lines` → `inlines`

### Field names at a glance

| Field | Role |
|-------|------|
| `type` | Node category atom — determines all other fields |
| `stage` | Parser sub-state when the node closed (usually ignorable) |
| `line_number` | 0-based source line where the node starts |
| `children` | Top-level blocks on `:document` only |
| `nested` | Section body (`:heading`) or inner blocks (containers, list sub-lists) |
| `items` | List entries on `:bullet_list` / `:ordered_list` |
| `blocks` | `:+` continuation paragraphs on `:list` / `:num` items |
| `raw_lines` | Source line tokens; verbatim body; error positions |
| `body` | First-line text from the opening tag |
| `joined_lines` | Canonical plain-text content (input to inline pass) |
| `inlines` | Parsed inline formatting (keyword list, stage 5) |
| `options` | Validated tag parameters |
| `level` | Outline or list depth |
| `closing_tag` | Parsed closing tag on fenced blocks |
| `tag`, `tag_name`, `tag_expr`, `raw_line`, `optionline` | Tag-line metadata |

## Node type index

| Category | `type` values | Fields reference | Examples |
|----------|---------------|------------------|----------|
| Document | `:document` | [node_fields — document](ast/node_fields.html#document) | This page |
| Structural | `:literal` | [node_fields — literal](ast/node_fields.html#literal) | [Blocks — Literal](ast/blocks.html#literal-nodes) |
| Text blocks | `:para`, `:title`, `:heading`, `:sep`, `:verbatim` | [node_fields](ast/node_fields.html) | [Blocks](ast/blocks.html) |
| Containers | `:quote`, `:footnote`, `:slot` | [node_fields — containers](ast/node_fields.html#quote-footnote-slot) | [Blocks — Containers](ast/blocks.html#container-blocks) |
| Lists | `:bullet_list`, `:ordered_list`, `:list`, `:num` | [node_fields — lists](ast/node_fields.html#bullet_list-and-ordered_list) | [Lists](ast/lists.html) |
| Inlines | (inside `inlines`) | [node_fields — inlines](ast/node_fields.html#inline-content-inlines-field) | [Inlines](ast/inlines.html) |
| Errors | (parse result tuple) | — | [Errors](ast/errors.html) |

### Language ↔ AST cross-reference

| Hoverscript topic | Syntax guide | AST detail |
|-------------------|--------------|------------|
| Paragraphs | [Paragraphs](REFERENCE.html#paragraphs) | [Paragraphs](ast/blocks.html#paragraphs) |
| Headings | [Headings](REFERENCE.html#headings) | [Headings](ast/blocks.html#headings) |
| Titles | [Titles](REFERENCE.html#titles) | [Titles](ast/blocks.html#titles) |
| Bullet lists | [Bullet Lists](REFERENCE.html#bullet-lists) | [Lists](ast/lists.html) |
| Numbered lists | [Numbered Lists](REFERENCE.html#numbered-lists) | [Lists](ast/lists.html) |
| Quotes | [Quote Blocks](REFERENCE.html#quote-blocks) | [Quote](ast/blocks.html#quote) |
| Footnotes | [Footnotes](REFERENCE.html#footnotes) | [Footnote](ast/blocks.html#footnote) |
| Verbatim | [Verbatim](REFERENCE.html#verbatim-blocks-code-blocks) | [Verbatim](ast/blocks.html#verbatim) |
| Separators | [Separators](REFERENCE.html#separators) | [Separator](ast/blocks.html#separator) |
| Slots | [Slots](REFERENCE.html#slots) | [Slot](ast/blocks.html#slot) |
| Inline formatting | [Inline Formatting](REFERENCE.html#inline-formatting) | [Inlines](ast/inlines.html) |
| Continuation lines | [Continuation Lines](REFERENCE.html#continuation-lines) | [List continuations](ast/lists.html#continuation-lines) |

## Traversing the AST

```elixir
def walk_nodes(node, acc \\ [])

def walk_nodes(nodes, acc) when is_list(nodes),
  do: Enum.reduce(nodes, acc, &walk_nodes/2)

def walk_nodes(%{type: _} = node, acc) do
  acc = [node | acc]
  acc = if node[:children], do: walk_nodes(node.children, acc), else: acc
  acc = if node[:nested], do: walk_nodes(node.nested, acc), else: acc
  acc = if node[:blocks], do: walk_nodes(node.blocks, acc), else: acc

  if node[:items] && is_list(node.items) do
    walk_nodes(node.items, acc)
  else
    acc
  end
end

def walk_nodes(_other, acc), do: acc
```

When counting **content** blocks inside list continuations, skip `:literal` nodes (blank-line placeholders):

```elixir
content_blocks = Enum.filter(blocks, &(&1.type != :literal))
```

## Related modules

| Module | Role |
|--------|------|
| `Hoverscript.Parser.Parse` | Public parse entry point |
| `Hoverscript.Parser.ParseTokens` | Block tree builder |
| `Hoverscript.Parser.Inline` | Inline pass |
| `Hoverscript.Parser.Tags` | Parameter validation |
| `Hoverscript.Converter.ToHtml` | AST → HTML |
| `Hoverscript.Parser.Layout` | AST → formatted Hoverscript text |

## Further reading

- **[Node fields by type](ast/node_fields.html)** — per-type field reference (start here for AST consumption)
- [Block nodes](ast/blocks.html) — paragraphs, headings, containers, verbatim, …
- [List nodes](ast/lists.html) — bullet/ordered lists, items, nesting, continuations
- [Inline nodes](ast/inlines.html) — bold, links, images, EEx, …
- [Errors](ast/errors.html) — error categories and partial AST behaviour
