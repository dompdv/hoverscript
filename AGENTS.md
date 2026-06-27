# Hoverscript Project Context

## Project Overview

Hoverscript is an Elixir-based parser and processor for **Hoverscript**, a lightweight markup language designed to be simpler and more regular than Markdown. The project provides a complete parsing pipeline that transforms Hoverscript documents into an Abstract Syntax Tree (AST) and can output to various formats including HTML and formatted text.

## Architecture

### Core Pipeline

The system follows a 5-stage parsing pipeline:

1. **Tokenize Lines** - Identifies line types (blank, option, tag, normal text)
2. **Check Options** - Validates option line parameters against following taglines
3. **Validate Tags** - Checks tag names and syntax for errors
4. **Build AST** - Creates nested document structure using a stack-based incremental parser
5. **Process Inlines** - Parses text formatting within blocks

Returns: `{:ok, ast}` or `{:error, accumulated_errors, ast}` with detailed error information including line/column positions.

### Directory Structure

```
lib/
├── hoverscript.ex              # Main module entry point
├── parser/                   # All parsing-related modules
│   ├── parse.ex              # Pipeline orchestrator (Hoverscript.Parser.Parse)
│   ├── parse_tokens.ex       # Stack-based incremental parser (Hoverscript.Parser.ParseTokens)
│   ├── tagline.ex            # Tag line parser (Hoverscript.Parser.Tagline)
│   ├── options.ex            # Option line parser (Hoverscript.Parser.Options)
│   ├── tags.ex               # Parameter tables & validation (Hoverscript.Parser.Tags)
│   ├── inline.ex             # Inline formatting processor (Hoverscript.Parser.Inline)
│   └── layout.ex             # AST to formatted text (Hoverscript.Parser.Layout)
└── converter/                # Format conversion modules
    └── to_html.ex            # AST to HTML converter (Hoverscript.Converter.ToHtml)

doc/
└── doc_en.hvt                # Complete Hoverscript language specification (334 lines)

examples/
├── hvscript_example.hvt      # Comprehensive feature demonstration
├── small_example.hvt         # Quick test file
├── heading_example.hvt       # Heading usage
├── bullets_example.hvt       # List examples
└── errors_example.hvt        # Error handling tests

test/
├── test_helper.exs
└── hoverscript_test.exs
```

## Module Naming Convention

**Important**: All parser modules use `Hoverscript.Parser.*` namespace and all converter modules use `Hoverscript.Converter.*` namespace.

### Parser Modules
- `Hoverscript.Parser.Parse` - Main entry point
- `Hoverscript.Parser.ParseTokens` - Core AST builder
- `Hoverscript.Parser.Tagline` - Tag syntax parser
- `Hoverscript.Parser.Options` - Option line parser
- `Hoverscript.Parser.Tags` - Validation rules
- `Hoverscript.Parser.Inline` - Inline formatting
- `Hoverscript.Parser.Layout` - Text formatter

### Converter Modules
- `Hoverscript.Converter.ToHtml` - HTML output

## Hoverscript Language Specification

### File Extension
`.hvt` (hoverscript files)

### Block Types

1. **Paragraphs** - `:para`, `:p`
   - Parameters: `align` (left/right/center/justify), `frame`
   - Default: justify alignment

2. **Headings** - `:heading`, `:h`, `:=`
   - Parameters: `level` (1-6)
   - Shortcut: `===` for h2, `====` for h3, etc.

3. **Bullet Lists** - `:list`, `:l`, `:*`
   - Parameters: `level` (1-3)
   - Up to 3 nesting levels
   - Shortcut: `*` for bullet items

4. **Numbered Lists** - `:num`, `:n`, `:.`
   - Parameters: `level` (1-3), `counter`
   - Up to 3 nesting levels with counter support
   - Shortcut: `.` for numbered items

5. **Quotes** - `:quote`, `:q`
   - Parameters: `name` (optional identifier)
   - Nestable blocks

6. **Footnotes** - `:footnote`
   - Parameters: `ref` (optional reference)
   - Nestable reference blocks

7. **Verbatim/Code** - `:verbatim`
   - Parameters: `name`, `type`, `lang` (html/js/elixir)
   - Code blocks with syntax highlighting support

8. **Separators** - `:sep`
   - Parameters: `type` (line/stars/asterism/dinkus)
   - Horizontal rules with various styles

9. **Titles** - `:title`
   - Parameters: `align` (center/left/right)
   - Special display blocks

10. **Slots** - `:slot`
    - Parameters: `name`
    - Container blocks

11. **Checklists** - `:checklist`, `:cl`
    - Parameters: `checked` (boolean)
    - Todo/checklist items

### Inline Formatting

- `//text//` - Emphasis (italics)
- `__text__` - Underline
- `**text**` - Strong (bold)
- `~~text~~` - Strikeout
- `^^text^^` - Superscript
- `,,text,,` - Subscript
- `::` at end of line - Line break
- `<% %>` - EEx template tags (for dynamic content)
- `[:tag:options]++text++` - Special inlines (images, links, footnotes)

**Nesting**: Formatting can be nested (except same tag within itself).

### Special Syntax

#### Tag Lines
Three formats supported:
- **Long tags**: `:tag:options/body` (e.g., `:para:left/Some text`)
- **Short tags**: `:tag body` (e.g., `:para Some text`)
- **Lonely tags**: `:tag` or `:tag:` or `:tag:/` (no body)

#### Option Lines
Format: `[param=value, param2=value2]`
- Must appear directly before a tagline
- Provides parameters for the following block
- Example: `[level=2]` before `:heading`

#### Continuation Lines
- `:+` - Continues list items or other blocks
- Preserves indentation context

#### Shortcuts
- `=`, `==`, `===`, etc. - Heading shortcuts (level based on count)
- `*` - Bullet list item
- `.` - Numbered list item

## AST Node Structure

Each node in the AST is a map containing:

```elixir
%{
  type:           :para | :heading | :list | :quote | etc.
  stage:          :lines | :blocks | :nested | etc.
  line_number:    integer() - source line number
  raw_lines:      list() - optional: original line tokens
  options:        map() - optional: tag parameters
  body:           string() - optional: immediate text content
  joined_lines:   string() - optional: concatenated text
  inlines:        list() - optional: parsed inline formatting
  level:          integer() - optional: for headings/lists (1-6 or 1-3)
  blocks:         list() - optional: child blocks
  items:          list() - optional: for lists
  children:       list() - optional: for document root
  nested:         list() - optional: nested structures
}
```

## Parser Implementation Details

### Stack-Based Incremental Parser (parse_tokens.ex)

The core parser (`Hoverscript.Parser.ParseTokens`) uses a stack-based approach:

**Main Loop**: `pinc(tokens, state, stage, stack)`
- `tokens` - lines to parse
- `state` - type of node currently being built
- `stage` - sub-state within the current node
- `stack` - context stack (nested nodes)

**Central Function**: `run(tokens, state, stage, stack)`
Returns:
- `{:run, shift, acc}` - Consume tokens, accumulate
- `{:ignore, shift}` - Skip tokens
- `{:start, shift, new_state, new_stage, line}` - Create new node, push to stack
- `{:end, shift, accumulator}` - Complete node, pop stack
- `{:end_stage, shift, next_stage, accumulator}` - Move to next stage

### Error Handling

Errors are accumulated throughout parsing and returned with:
- Error type
- Line and column positions (start and end)
- Descriptive messages

Common error types:
- `:bad_options` - Invalid option syntax or parameters
- `:inline_error` - Invalid inline formatting
- `:optionline_must_be_followed_by_tagline`
- `:unauthorized_parameters`
- `:parameter_errors`

## Usage Examples

### Basic Parsing
```elixir
{:ok, ast} = Hoverscript.Parser.Parse.parse(hoverscript_text)
```

### Convert to HTML
```elixir
html = Hoverscript.Converter.ToHtml.to_html(ast)
```

### Format back to Hoverscript
```elixir
formatted_text = Hoverscript.Parser.Layout.layout(ast)
# With options:
formatted_text = Hoverscript.Parser.Layout.layout(ast, %{width: 80, column: 8, step: 2})
```

### Layout Options
- `width` (default: 100) - Maximum text width
- `column` (default: 10) - Width of left tag column
- `step` (default: 3) - Indentation spaces per level

## Common Development Tasks

### Adding a New Tag

1. **Update tagline.ex**: Add tag to `@tags` map
2. **Update tags.ex**: Add parameter definition to `@parameters_table`
3. **Create validation function**: Implement `check_<tag>_parameters/2`
4. **Update parse_tokens.ex**: Implement `start/2`, `run/4`, and `update/4` for the tag
5. **Update to_html.ex**: Add HTML conversion for the tag
6. **Update layout.ex**: Add layout formatting for the tag

### Adding a New Inline Format

1. **Update inline.ex**: Add token regex and parsing logic
2. **Update to_html.ex**: Add HTML conversion for inline
3. **Update layout.ex**: Handle layout for inline

### Testing

Run tests:
```bash
mix test
```

Compile project:
```bash
mix compile
```

## Dependencies

- **floki** - HTML parsing/generation

## Key Files for Reference

- **Language Spec**: `doc/doc_en.hvt` - Complete language specification (authoritative source)
- **Main Parser**: `lib/parser/parse_tokens.ex` (772 lines) - Core parsing logic
- **Tag Definitions**: `lib/parser/tags.ex` - All tag parameters and validation
- **Examples**: `examples/hvscript_example.hvt` - Comprehensive feature demonstration

## Development Notes

- File naming: Use `.hvt` suffix for Hoverscript files
- Module organization: Keep parsing logic in `parser/`, converters in `converter/`
- Error messages: Include line/column information for all parsing errors
- Verbatim blocks: Special handling - no inline parsing within them
- EEx support: `<% %>` tags are preserved for template processing
- Indentation: Important for list nesting and continuation lines
