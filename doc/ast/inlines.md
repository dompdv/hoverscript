# Inline nodes

Inline structure lives in the `inlines` field on text-bearing block nodes (`:para`, `:heading`, `:title`, list items, …). It is populated in **stage 5** of parsing.

**Syntax reference:** [Inline formatting](../REFERENCE.html#inline-formatting)

## Format

`inlines` is a **keyword list** of tagged segments:

```elixir
[
  string: "Plain text ",
  strong: [string: "bold"],
  string: " and ",
  emph: [string: "italic"],
  string: "."
]
```

Each formatting tag maps to a nested keyword list of child segments. Leaf text uses the `string` key.

## Formatting tags

| Marker | Inline tag | Nested value |
|--------|------------|--------------|
| `**text**` | `:strong` | `[string: "text"]` |
| `//text//` | `:emph` | `[string: "text"]` |
| `__text__` | `:underline` | `[string: "text"]` |
| `~~text~~` | `:strikeout` | `[string: "text"]` |
| `^^text^^` | `:superscript` | `[string: "text"]` |
| `,,text,,` | `:subscript` | `[string: "text"]` |
| line ending `::` | `:linebreak` | (no children) |

### Example

Source: `**Bold with //italic inside// it**`

```elixir
[
  strong: [
    string: "Bold with ",
    emph: [string: "italic inside"],
    string: " it"
  ]
]
```

Nesting the **same** tag inside itself (e.g. `**a **b** c**`) produces an `:inline_error`.

## EEx templates

Source: `Hello <%= @name %>`

```elixir
[
  string: "Hello ",
  {:eex_tag, 0, "<%= @name %>"}
]
```

EEx tags are preserved verbatim for later evaluation; they are not executed by the parser.

## Special inlines

**Syntax:** [Special inlines](../REFERENCE.html#special-inlines)

Form: `[:tag:parameters]++optional text++`

Parsed as a tuple element:

```elixir
{
  :options,
  %{
    tag: :i_link,           # :i_image | :i_link | :i_footnote
    tag_name: "link",
    options: %{url: "https://example.com"}
  },
  [string: "link text"]    # empty list if no ++text++
}
```

### Parameter names (parser)

The inline parser requires **named** parameters for special inlines:

| Tag | Parameter | Example |
|-----|-----------|---------|
| Image | `name=` | `[:image:name=diagram1]` |
| Link | `url=` | `[:link:url=https://example.com]++here++` |
| Footnote | `ref` positional in brackets | `text[:footnote:ref1]` |

Positional-only forms like `[:image:diagram1]` or `[:link:https://…]` without `url=` may produce `:inline_error`.

Lines starting with `[` are tokenized as **option lines** at the block level; special inlines must appear **inside** paragraph text, not alone on a line.

## Error fallback

When inline parsing fails, the node still receives an `inlines` field:

```elixir
inlines: [string: "raw unparsed joined_lines text"]
```

and an `:inline_error` entry is added to the parse error map.

## Which nodes have `inlines`

| Node type | Inline parsing |
|-----------|----------------|
| `:para`, `:title`, `:heading` | Yes, on `joined_lines` |
| `:list`, `:num` (items) | Yes, on item text |
| `:verbatim` | No |
| `:sep` | No |
| `:literal` | No |

See also: [Errors — inline_error](errors.html#inline_error) · [Block nodes](blocks.html) · [AST overview](../AST.html)
