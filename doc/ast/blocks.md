# Block nodes

Block-level AST nodes. For Hoverscript syntax of each block type, follow the links to the [Reference Guide](../REFERENCE.html).

> **Field reference:** see [Node fields by type](node_fields.html) for which map keys each `type` uses and why.

## Literal nodes

Blank lines and other non-content line tokens are sometimes preserved as `:literal` nodes:

```elixir
%{
  type: :literal,
  stage: :line,
  line_number: 1,
  raw_lines: [{:blankline, 1, ""}]
}
```

They appear inside `heading.nested`, list item `blocks`, and occasionally as trailing `document.children`. Filter them out when measuring content length.

---

## Paragraphs

**Syntax:** [Paragraphs](../REFERENCE.html#paragraphs)

```elixir
%{
  type: :para,
  stage: :lines,
  line_number: 0,
  options: %{align: "justify"},      # or "left" | "right" | "center"
  body: "First line text",           # when opened with a tag line
  joined_lines: "Line one\nLine two",
  inlines: [string: "Line one\nLine two"],
  raw_lines: [{:line, 0, "Line one"}],
  optionline: nil,
  tag_expr: "",                      # empty for implicit paragraphs
  tag_name: "para"                   # present when using :para / :p
}
```

| Field | Notes |
|-------|-------|
| `options.align` | String, default `"justify"` |
| `options.frame` | Integer `0` or `1` when set |
| `joined_lines` | Preferred source for full text; use over `body` for multi-line |
| `inlines` | Added in inline pass; absent if inline parsing failed partially |

Implicit paragraphs (plain text lines) have empty `tag_expr` and minimal `options`.

---

## Headings

**Syntax:** [Headings](../REFERENCE.html#headings)

```elixir
%{
  type: :heading,
  stage: :nested,
  level: 2,
  options: %{level: 2},
  body: "Section Title",
  joined_lines: "Section Title",
  inlines: [string: "Section Title"],
  nested: [
    %{type: :literal, ...},
    %{type: :para, ...},
    %{type: :heading, level: 3, nested: [...], ...}
  ],
  tag_expr: ":==",
  tag_name: ":=="
}
```

### Nesting model

Headings use an **outline tree**: content after a heading stays in `nested` until a heading of **equal or higher** level (lower number) closes the section.

Consequences:

- A document `:= Title` / `:== Section` / paragraph sequence yields **one** top-level `:heading` child on `:document`, not three siblings.
- To find all headings, walk the tree recursively — do not rely on `document.children` alone.

| Field | Notes |
|-------|-------|
| `level` | Integer 1–6 |
| `nested` | Paragraphs, lists, sub-headings, blank-line literals, … |
| `blocks` | Usually empty on headings |

---

## Titles

**Syntax:** [Titles](../REFERENCE.html#titles)

```elixir
%{
  type: :title,
  stage: :lines,
  options: %{align: "center"},
  body: "My Document Title",
  joined_lines: "My Document Title\nSecond line",
  inlines: [...],
  tag_expr: ":title",
  tag_name: "title"
}
```

Titles are **not** nested like headings; they appear as direct `document.children`. Inline formatting on the **first tag line** with markers like `**` may not parse as a title (use continuation lines for formatted title text).

---

## Separator

**Syntax:** [Separators](../REFERENCE.html#separators)

```elixir
%{
  type: :sep,
  stage: :none,
  options: %{type: "line"},    # "line" | "stars" | "asterism" | "dinkus"
  line_number: 1
}
```

Separators are leaf nodes with no text content or `inlines`.

---

## Verbatim

**Syntax:** [Verbatim / code blocks](../REFERENCE.html#verbatim-blocks-code-blocks)

```elixir
%{
  type: :verbatim,
  stage: :lines,
  options: %{name: :default_verbatim, lang: "elixir"},
  raw_lines: [
    {:line, 2, "def hello, do: :ok"},
    {:line, 3, "end"}
  ],
  line_number: 1
}
```

| Field | Notes |
|-------|-------|
| `raw_lines` | Source lines preserved literally; **no** inline parsing |
| `options.lang` | `"html"`, `"js"`, `"elixir"`, … when specified |
| `options.name` | Named block identifier or `:default_verbatim` |

---

## Container blocks

Fenced blocks that require explicit open/close markers. Inner content is in `nested`.

### Quote

**Syntax:** [Quote blocks](../REFERENCE.html#quote-blocks)

```elixir
%{
  type: :quote,
  stage: :nested,
  options: %{name: "einstein"},    # or :default_quote
  nested: [
    %{type: :para, ...},
    %{type: :bullet_list, ...}
  ],
  closing_tag: %{tag: :quote, ...}
}
```

### Footnote

**Syntax:** [Footnotes](../REFERENCE.html#footnotes)

```elixir
%{
  type: :footnote,
  stage: :nested,
  options: %{ref: "note1"},
  nested: [%{type: :para, ...}]
}
```

### Slot

**Syntax:** [Slots](../REFERENCE.html#slots)

```elixir
%{
  type: :slot,
  stage: :nested,
  options: %{name: "sidebar"},
  nested: [%{type: :para, ...}, %{type: :bullet_list, ...}]
}
```

Container blocks do not use `:title` or heading shortcuts reliably inside `nested` in all cases; prefer paragraphs and lists for nested content.

---

## Document root

```elixir
%{
  type: :document,
  stage: :children,
  line_number: 0,
  children: [
    %{type: :heading, ...},
    %{type: :para, ...},
    %{type: :bullet_list, ...},
    %{type: :literal, ...}
  ]
}
```

Typical top-level `children` types: `:heading`, `:para`, `:title`, `:bullet_list`, `:ordered_list`, `:quote`, `:footnote`, `:slot`, `:verbatim`, `:sep`, `:literal`.

See also: [List nodes](lists.html) · [Inline nodes](inlines.html) · [AST overview](../AST.html)
