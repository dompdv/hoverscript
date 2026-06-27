# Parse errors

`Hoverscript.Parser.Parse.parse/1` returns either `{:ok, ast}` or `{:error, errors, ast}`.

Even on error, **`ast` is always present** (possibly partial). Downstream converters (`ToHtml`, `Layout`) can still process it.

```elixir
case Hoverscript.Parser.Parse.parse(source) do
  {:ok, ast} -> ast
  {:error, errors, ast} -> handle_errors(errors, ast)
end
```

## Error map shape

`errors` is a map keyed by **error category atom**. Values are lists of error records (shape varies by category).

```elixir
%{
  bad_options: [...],
  bad_tagline: [...],
  parsing_error: [...],
  inline_error: [...]
}
```

Multiple categories may coexist.

## Error categories

### `bad_options`

Invalid or misplaced `[param=value]` option lines.

Common cases:

| Error | Meaning |
|-------|---------|
| `optionline_must_be_followed_by_tagline` | Option line not immediately before a tag line |
| `{:unauthorized_parameters, names}` | Unknown parameter for the following tag |
| `{:parameter_errors, details, tag}` | Valid parameter name but invalid value |

Record example:

```elixir
{optionline_must_be_followed_by_tagline, {line, col_start, line, col_end}}
```

### `bad_tagline`

Malformed or unknown block tag lines.

Common cases:

| Error | Meaning |
|-------|---------|
| `:unknown_tag` | Unrecognised tag name |
| `{:parameter_errors, …}` | Inline parameters on the tag line failed validation |
| `{:maybe_forgot_colon_after_tag, tag}` | Warning during tokenization (short form ambiguity) |

Some `bad_tagline` situations still yield a usable `:para` node containing the raw line text.

### `parsing_error`

Structural errors from `Hoverscript.Parser.ParseTokens` (unclosed fenced blocks, etc.).

```elixir
[
  {:error, {line, col_start, line, col_end}, :expecting_closing_quote},
  {:error, :eof, :expecting_closing_slot}
]
```

Typical `:expecting_closing_*` atoms:

- `:expecting_closing_quote`
- `:expecting_closing_slot`
- `:expecting_closing_footnote`
- `:expecting_closing_verbatim`

### `inline_error`

Invalid inline formatting or special inline parameters.

```elixir
[
  {{:unclosed_tags, [:strong]}, {line, col_start, line, col_end}},
  {{:unauthorized_parameters, ["url"]}, "link", []}, {line, col, line, col}}
]
```

Common inline error tuples inside the record:

| Tuple | Meaning |
|-------|---------|
| `{:unclosed_tags, stack}` | Unclosed `**`, `//`, etc. |
| `{:closing_bad_tag, tag, stack, …}` | Mismatched closing marker |
| `{:unauthorized_parameters, names}` | Bad special-inline parameters |
| `{:dangling_options_text, …}` | `++text++` without opening `[:…]` |

## Partial AST behaviour

| Situation | Typical AST |
|-----------|-------------|
| Unknown tag line | `:para` with raw tag text in `joined_lines` |
| Unclosed quote/slot | Container node without proper `closing_tag`; content in `nested` |
| Inline failure | Block node with `inlines: [string: "…"]` fallback |
| Heading + invalid sibling | Valid heading tree; invalid lines in `nested` |

Always inspect both `errors` and `ast` when building error-reporting UX.

## Position tuples

Most errors include a position `{line, col_start, line, col_end}` (0-based line numbers). Inline errors may reference columns within `joined_lines`.

## Related API modules

| Module | Validates |
|--------|-----------|
| `Hoverscript.Parser.Options` | Option lines |
| `Hoverscript.Parser.Tags` | Tag parameters (block and inline) |
| `Hoverscript.Parser.Tagline` | Tag line syntax |
| `Hoverscript.Parser.Inline` | Inline markers and special inlines |

See also: [AST overview](../AST.html) · [Inline nodes](inlines.html)
