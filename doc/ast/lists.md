# List nodes

List structure in the AST. For Hoverscript list syntax see [Bullet Lists](../REFERENCE.html#bullet-lists) and [Numbered Lists](../REFERENCE.html#numbered-lists).

> **Field reference:** see [Node fields by type — lists](node_fields.html#bullet_list-and-ordered_list) for the `:bullet_list`, `:ordered_list`, `:list`, and `:num` field layouts.

## Overview

```
:document
  └── :bullet_list | :ordered_list
        └── items: [:list | :num, ...]
              ├── body / joined_lines / inlines
              ├── nested: [sub :bullet_list | :ordered_list, ...]
              └── blocks: [continuation :para, :literal, ...]
```

| AST `type` | Source markers | Role |
|------------|----------------|------|
| `:bullet_list` | `:*`, `:**`, `:list`, `:l` | Bullet list container |
| `:ordered_list` | `:.`, `:..`, `:num`, `:n` | Numbered list container |
| `:list` | (item) | Single bullet item |
| `:num` | (item) | Single numbered item |

List **containers** appear as `:bullet_list` / `:ordered_list`. Individual **items** retain the parser tag type `:list` or `:num`.

## List container

```elixir
%{
  type: :bullet_list,       # or :ordered_list
  stage: :items,
  level: 1,
  line_number: 0,
  items: [
    %{type: :list, level: 1, body: "First item", ...},
    %{type: :list, level: 1, body: "Second item", ...}
  ]
}
```

| Field | Notes |
|-------|-------|
| `level` | Container nesting depth (1–3) |
| `items` | Ordered list of item nodes |

A blank line between list items in the source creates **separate** list containers at the same document level.

## List item

```elixir
%{
  type: :list,              # or :num for numbered items
  stage: :blocks,
  level: 2,
  options: %{level: 2},
  body: "Nested item one",
  joined_lines: "Nested item one",
  inlines: [string: "Nested item one"],
  nested: [
    %{
      type: :bullet_list,   # or :ordered_list
      level: 2,
      items: [...]
    }
  ],
  blocks: [],
  tag_expr: ":**",
  tag_name: ":**"
}
```

| Field | Notes |
|-------|-------|
| `nested` | Sub-lists attached to this item (0 or 1 list container typical) |
| `blocks` | Extra paragraphs from `:+` continuation lines |
| `options.counter` | On `:num` items: integer or string counter value |

### Numbered item counter

The first item may inherit `[counter=N]` from an option line:

```elixir
options: %{level: 1, counter: 5}   # integer on first item
options: %{level: 1, counter: "1"} # string on subsequent items
```

The parser does not always auto-increment counters on later items; inspect `options.counter` per item.

## Nesting

Nesting is expressed through `item.nested`, not as sibling items:

```hoverscript
:* Top level
:** Nested A
:** Nested B
:* Another top
```

```elixir
# First item
%{
  type: :list,
  body: "Top level",
  nested: [
    %{
      type: :bullet_list,
      level: 2,
      items: [
        %{type: :list, body: "Nested A", ...},
        %{type: :list, body: "Nested B", ...}
      ]
    }
  ]
}
```

Mixed bullet/numbered nesting (`:*` with `:..` children) produces `:ordered_list` inside `nested`.

## Continuation lines

**Syntax:** [Continuation lines](../REFERENCE.html#continuation-lines)

`:+` adds paragraphs to the **current list item** via `blocks`:

```hoverscript
:* First paragraph
:+
Second paragraph
:* Next item
```

```elixir
%{
  type: :list,
  body: "First paragraph",
  blocks: [
    %{type: :literal, ...},           # blank line after :+
    %{type: :para, joined_lines: "Second paragraph", ...}
  ]
}
```

When counting continuation paragraphs, filter `:literal` entries:

```elixir
Enum.filter(item.blocks, &(&1.type != :literal))
```

Multiple `:+` lines produce alternating `:literal` and `:para` nodes in `blocks`.

## Multi-line items

Lines continuing a list item **without** `:+` are joined into `joined_lines` on the same item (soft wrap within the item).

## Traversal tips

- Use **top-level** `document.children` to count list *containers* at document root.
- Use `item.nested` to descend into sub-lists — not `document.children`.
- Recursive walk required if lists live inside `heading.nested` or container `nested`.

See also: [Block nodes](blocks.html) · [AST overview](../AST.html)
