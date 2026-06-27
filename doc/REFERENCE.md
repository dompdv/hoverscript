# Hoverscript Reference Guide

## Table of Contents

1. [Introduction](#introduction)
2. [Basic Concepts](#basic-concepts)
3. [Block Types](#block-types)
4. [Inline Formatting](#inline-formatting)
5. [Complete Examples](#complete-examples)


> **AST reference:** If you consume the parse tree from Elixir (`Hoverscript.Parser.Parse.parse/1`), see the [AST Reference](AST.html) for node shapes, nesting rules, and error behaviour.

> **Project build:** To assemble a directory of `.hvt` files with TOML data, imports, and EEx, see the [Project Build Guide](BUILD.html).


## Introduction

Hoverscript is a lightweight markup language designed for writing structured documents with clear, consistent syntax. It is inspired by Markdown and AsciiDoc but aims to be simpler and more regular.

Hoverscript documents consist of blocks (paragraphs, headings, lists, quotes, etc.) that can contain inline formatting (bold, italic, links, etc.).


## Basic Concepts


### Document Structure

A Hoverscript document is composed of sequential blocks. Each block can be:
- A paragraph (the default block type)
- A heading
- A list (bullet or numbered)
- A quote
- A code block (verbatim)
- A separator
- And more...

Blocks are separated by blank lines or by explicit block markers.


### Indentation

**Important**: Indentation has no semantic meaning in Hoverscript. It is completely ignored by the parser and used only for source code readability.

For example, these two documents are identical:


```hoverscript
:para This is a paragraph
:para Another paragraph
```



```hoverscript
:para This is a paragraph
     :para Another paragraph
```


Exception: In verbatim blocks, relative indentation is preserved for formatting purposes.


### Block Markers

A block marker is a line that starts with a colon (:) followed by a block type name.

Block markers can take three forms:

- Long form with parameters and body: `:blocktype:parameters/body`
- Short form with body: `:blocktype body`
- Lonely form (no body): `:blocktype` or `:blocktype:` or `:blocktype:/`

Examples:

```hoverscript
:para:center/This paragraph is centered
:para This paragraph uses default alignment
:para
```



### Block Parameters

Parameters can be specified in two ways:


##### Inline Parameters

Parameters appear in the block marker itself:

```hoverscript
:heading:level=2/My Title
:para:align=center/Centered text
```


Parameters can be named or positional (meaning depends on block type):

```hoverscript
:heading:2/My Title
:para:center/Centered text
```



##### Option Lines

Parameters can be specified on the line **immediately before** the block marker using square brackets:


```hoverscript
[level=2]
:heading My Title

[align=center]
:para Centered text
```


This is useful for keeping block markers clean and readable.


### Blank Lines

A blank line is a line containing only whitespace (spaces, tabs) or no characters at all.

Blank lines typically end blocks, but some blocks (like quotes and verbatim blocks) use explicit end markers.


### Continuation Lines

The special marker `:+` (with optional surrounding whitespace) is a continuation line. It is used primarily in lists to:
- Add multiple paragraphs to a list item
- Keep list items together without creating separate lists

Example:

```hoverscript
:* First item paragraph one
:+
Second paragraph of first item
:* Second item
```



### Line Breaks

To force a line break within a paragraph (like HTML's `<br>` tag), end the line with `::` (nothing should follow it).

Example:

```hoverscript
:para First line::
Second line::
Third line
```



## Block Types

Each block type below links to its AST representation in the [block nodes reference](ast/blocks.html).



### Paragraphs

**Markers**: `:para`, `:p`, or no marker (default)

Paragraphs are the default block type. Any text not preceded by a block marker is treated as a paragraph.

**Parameters**:
- `align`: left, right, center, justify (default: justify)
- `frame`: 0 (no frame, default) or 1 (draw a frame around the paragraph)

**Examples**:

Default paragraph (no marker needed):

```hoverscript
This is a simple paragraph.
It can span multiple lines.

This starts a new paragraph.
```


Explicit paragraph with center alignment:

```hoverscript
:para:center/This text is centered
```


Using option line:

```hoverscript
[align=right]
:para
This text is right-aligned
```



### Headings

**Markers**: `:heading`, `:h`, or `:=` (shortcut)

Headings have 6 levels (1-6), like HTML's h1 through h6.

**Parameters**:
- `level`: 1 to 6 (default: 1)

**Shortcut syntax**: The number of `=` signs indicates the level:
- `:=` → level 1 (h1)
- `:==` → level 2 (h2)
- `:===` → level 3 (h3)
- etc.

**Examples**:


```hoverscript
:= Main Document Title

:== Section Title

:=== Subsection Title

:heading:level=4/Another Way to Write a Heading

[level=5]
:h Yet Another Heading Style
```


**Multi-line headings**: Heading text continues until a blank line or another block marker:


```hoverscript
:== This is the beginning of a long heading
that continues on this line
and even this line

This is a new paragraph.
```



### Bullet Lists

**Markers**: `:list`, `:l`, or `:*` (shortcut)

Bullet lists support up to 3 nesting levels.

**Parameters**:
- `level`: 1, 2, or 3 (default: 1)

**Shortcut syntax**:
- level 1
- level 2
- level 3

**Examples**:

Simple bullet list:

```hoverscript
:* First item
:* Second item
:* Third item
```


Nested bullet list:

```hoverscript
:* Top level item
:** Nested item one
:** Nested item two
:* Another top level item
```


Multi-line list items:

```hoverscript
:* This item has multiple lines
of content that continues here
:* This is a separate item
```


List item with multiple paragraphs:

```hoverscript
:* First paragraph of the item
:+
Second paragraph of the same item
:+
Third paragraph
:* Next item
```



### Numbered Lists

**Markers**: `:num`, `:n`, or `:.` (shortcut)

Numbered lists support up to 3 nesting levels and can have custom starting numbers.

**Parameters**:
- `level`: 1, 2, or 3 (default: 1)
- `counter`: starting number as string (default: "1")

**Shortcut syntax**:
- `:.` → level 1
- `:..` → level 2
- `:...` → level 3

**Examples**:

Simple numbered list:

```hoverscript
:. First item
:. Second item
:. Third item
```


Nested numbered list:

```hoverscript
:. Main step one
:.. Sub-step one
:.. Sub-step two
:. Main step two
```


Custom starting number:

```hoverscript
[counter=5]
:num Continue numbering from 5
:num This will be 6
:num This will be 7
```


Mixed nesting (bullets and numbers):

```hoverscript
:* Overview
:.. First detailed step
:.. Second detailed step
:* Summary
```


**Important**: Blank lines between list items create separate lists!

Wrong (creates two separate lists):

```hoverscript
:. Item 1

:. Item 2
```


This outputs:
1. Item 1
1. Item 2

Correct (use continuation line):

```hoverscript
:. Item 1
:+
:. Item 2
```



### Quote Blocks

**Markers**: `:quote`, `:q`

Quote blocks are fenced blocks that require explicit start and end markers. They can be nested and identified with names.

**Parameters**:
- `name`: optional identifier for matching start/end markers in nested quotes

**Syntax**:
- Start: `:quote` or `:quote:name/`
- End: `:quote` or `:quote:name/` (must match the start marker)

**Examples**:

Simple quote:

```hoverscript
:quote
This is a quoted text.
It can span multiple lines.
:quote
```


Named quote:

```hoverscript
:quote:source1/
Text from source 1
:quote:source1/
```


Nested quotes:

```hoverscript
:quote:outer/
This is the outer quote.

  :quote:inner/
  This is a nested quote inside.
  :quote:inner/

Back to the outer quote.
:quote:outer/
```


Quote with option line:

```hoverscript
[name=aristotle]
:quote
To be or not to be...
:quote
```



### Footnotes

**Marker**: `:footnote`

Footnotes are fenced blocks similar to quotes but designed for reference notes.

**Parameters**:
- `ref`: optional reference identifier

**Syntax**:
- Start: `:footnote` or `:footnote:ref/`
- End: `:footnote:/`

Footnotes cannot be nested.

**Examples**:


```hoverscript
:footnote:note1/
This is a footnote explaining something in detail.
:footnote:/

:footnote
Another footnote without an explicit reference.
:footnote:/
```



### Verbatim Blocks (Code Blocks)

**Marker**: `:verbatim`

Verbatim blocks display preformatted text, typically for code. Content is shown exactly as written, with no inline parsing.

**Parameters**:
- `name`: optional identifier for matching start/end markers
- `type`: optional type designation
- `lang`: language for syntax highlighting (html, js, elixir, etc.)

**Syntax**:
- Start: `:verbatim` or `:verbatim:name/`
- End: `:verbatim` or `:verbatim:name/`

**Examples**:

Simple code block:

```hoverscript
```

function hello() {
  console.log("Hello, world!");
}

```hoverscript
```


With language specification:

```hoverscript
[lang=elixir]
```

defmodule Hello do
  def world, do: :ok
end

```hoverscript
```


Named verbatim block (useful if content contains `:verbatim`):

```hoverscript
:verbatim:code1/
This code contains :verbatim markers
that would otherwise end the block.
:verbatim:code1/
```


**Important**: Inside verbatim blocks:
- No inline formatting is processed
- Relative indentation is preserved
- EEx tags are not processed


### Separators

**Marker**: `:separator`, `:sep`

Separators create horizontal rules between sections.

**Parameters**:
- `type`: line (default), stars, asterism, dinkus

**Examples**:


```hoverscript
:sep

:sep:line/

:separator:stars/

[type=asterism]
:sep
```



### Titles

**Marker**: `:title`

Title blocks are special display blocks, typically for document titles or special announcements.

**Parameters**:
- `align`: center (default), left, right

**Examples**:


```hoverscript
:title My Document Title

[align=left]
:title Left-aligned Title
```



### Slots

**Marker**: `:slot`

Slots are generic container blocks for special purposes.

**Parameters**:
- `name`: optional slot identifier

**Examples**:


```hoverscript
:slot:sidebar/
Content for a sidebar
:slot

[name=callout]
:slot
Important information
:slot
```



## Inline Formatting

> **AST:** Parsed inline structure is stored in the `inlines` field — see [Inline nodes](ast/inlines.html).


Inline formatting applies to text within blocks. Formatting markers use doubled characters.


### Basic Formatting

- Emphasis (italic): `//text//`
- Strong (bold): `**text**`
- Underline: `__text__`
- Strikeout: `~~text~~`
- Superscript: `^^text^^`
- Subscript: `,,text,,`

**Examples**:


```hoverscript
This is //italic text// and this is **bold text**.

You can __underline__ text or ~~strike it out~~.

Use ^^superscript^^ for exponents like x^^2^^ or ,,subscript,, for H,,2,,O.
```



### Nested Formatting

Formatting can be nested, allowing combinations like bold italic text.

**Rule**: You cannot nest the same formatting type within itself.

**Examples**:

Valid nesting:

```hoverscript
**Bold with //italic inside// it**

//Italic with __underline__ and **bold**//
```


Invalid (won't work as expected):

```hoverscript
**Bold with **more bold** inside**
```


Complex nesting example:

```hoverscript
When //the sky ,,low,, and **heavy**// __weighs__ like a lid
```


This produces: italic text containing subscript and bold, plus underlined text.


### EEx Template Tags

Hoverscript supports EEx (Embedded Elixir) template syntax for dynamic content:


```hoverscript
Dear <%= @user.name %>,

Your balance is <%= @account.balance %>.
```


EEx tags are preserved during parsing and can be evaluated later.


### Special Inlines

Special inlines have the form: 

```hoverscript
[:inline_type:parameters]++text++` or `[:inline_type:parameters]` if no text is needed.
```


**Examples**:


```hoverscript
See [:image:diagram1] for details.

Click [:link:https://example.com]++here++ for more information.

This needs a citation[:footnote:ref1].

Images: `[:image:name]` or `[:img:name]`
Footnotes: `[:footnote:ref]`
Links: `[:link:url]++link text++`
```



## Complete Examples


### Simple Document


```hoverscript
:= Getting Started with Hoverscript

:== Introduction

Hoverscript is easy to learn. Here's what you need to know:

:* It uses clear, consistent syntax
:* Blocks are separated by blank lines
:* Inline formatting uses doubled characters

:== Basic Formatting

You can make text **bold** or //italic//.

:sep

:== Lists

Numbered lists are simple:

:. First step
:. Second step
:. Third step

That's it!
```



### Advanced Document


```hoverscript
[align=center]
:title Advanced Hoverscript Techniques

:== Code Examples

Here's some Elixir code:

[lang=elixir]
```

defmodule MyApp do
  def hello(name) do
    IO.puts("Hello, #{name}!")
  end
end

```hoverscript

:== Nested Lists and Quotes

:* Main points:
:** Sub-point one
:** Sub-point two with //emphasis//
:* Another main point

:quote:einstein/
Imagination is more important than knowledge.
:quote:einstein/

:== Inline Formatting

You can combine **bold and //italic//** text.

Chemical formulas work too: H,,2,,O or E = mc^^2^^.
```



## Tips and Best Practices

- Use blank lines to separate blocks clearly
- Indent your source for readability (the parser ignores it)
- Use shortcuts (`:=`, `:*`, `:.`) for common blocks
- Name your quotes and verbatim blocks when nesting them
- Use continuation lines (`:+`) to keep list items together
- Use option lines for complex parameters to keep markers clean
- Remember: indentation is for humans, not the parser!

:sep


## Quick Reference


### Block Markers


```hoverscript
:para or :p          Paragraph
:heading or :h or := Heading (use =, ==, === for levels)
:list or :l or :*    Bullet list (use *, **, *** for levels)
:num or :n or :.     Numbered list (use ., .., ... for levels)
:quote or :q         Quote block (needs end marker)
:footnote            Footnote block (needs end marker)
:verbatim            Code block (needs end marker)
:sep                 Horizontal separator
:title               Title block
:slot                Slot container
```



### Inline Formatting


```hoverscript
//text//     Italic
**text**     Bold
__text__     Underline
~~text~~     Strikeout
^^text^^     Superscript
,,text,,     Subscript
::           Line break (at end of line)
<%= %>       EEx template
[:tag]++txt++  Special inline (image, link, footnote)
```


:sep

