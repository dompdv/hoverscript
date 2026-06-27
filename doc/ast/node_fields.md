# Node fields by type

Every AST node is a plain map (`%{}`). **Which keys appear depends entirely on `type`.** There is no shared struct or schema module — this page is the authoritative field reference.

For examples and Hoverscript syntax, see [Block nodes](blocks.html), [List nodes](lists.html), and [Inline nodes](inlines.html).

## How to read the tables

| Symbol | Meaning |
|--------|---------|
| **✓** | Always present on this node type |
| **·** | Present only in some cases (see *When* column) |
| **—** | Not used for this node type |

The `stage` field is always present but is **parser bookkeeping** (which sub-state the incremental parser was in when the node closed). You can ignore it when consuming the AST unless you are debugging the parser.

## Field quick-reference matrix

Rows are fields; columns are block node types. ✓ = used, — = unused.

| Field | `:document` | `:literal` | `:para` | `:title` | `:heading` | `:sep` | `:verbatim` | `:quote` | `:footnote` | `:slot` | `:bullet_list` | `:ordered_list` | `:list` | `:num` |
|-------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `type` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `stage` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `line_number` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `children` | ✓ | — | — | — | — | — | — | — | — | — | — | — | — | — |
| `nested` | — | — | — | — | ✓ | — | — | ✓ | ✓ | ✓ | — | — | ✓ | ✓ |
| `items` | — | — | — | — | — | — | — | — | — | — | ✓ | ✓ | — | — |
| `blocks` | — | — | — | — | ✓ | — | — | — | — | — | — | — | ✓ | ✓ |
| `raw_lines` | — | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | — | — | ✓ | ✓ |
| `joined_lines` | — | — | ✓ | ✓ | ✓ | — | — | — | — | — | — | — | ✓ | ✓ |
| `inlines` | — | — | ✓ | ✓ | ✓ | — | — | — | — | — | — | — | ✓ | ✓ |
| `body` | — | — | · | ✓ | ✓ | · | · | · | · | · | — | — | ✓ | ✓ |
| `options` | — | — | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | — | — | ✓ | ✓ |
| `level` | — | — | — | — | ✓ | — | — | — | — | — | ✓ | ✓ | ✓ | ✓ |
| `closing_tag` | — | — | — | — | — | — | ✓ | ✓ | ✓ | ✓ | — | — | — | — |
| Tag metadata¹ | — | — | · | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | — | — | ✓ | ✓ |

¹ Tag metadata: `tag`, `tag_name`, `tag_expr`, `raw_line`, `optionline` — see [Tag-opened nodes](#tag-opened-nodes).

### Where to find child nodes

| Node type | Child container | Contains |
|-----------|-----------------|----------|
| `:document` | `children` | Top-level blocks only (see [nesting rules](#nesting-rules)) |
| `:heading` | `nested` | Section body: paragraphs, lists, sub-headings, … |
| `:quote`, `:footnote`, `:slot` | `nested` | Any block allowed inside the container |
| `:bullet_list`, `:ordered_list` | `items` | Item nodes (`:list` or `:num`) |
| `:list`, `:num` | `nested` | Sub-list containers at deeper levels |
| `:list`, `:num` | `blocks` | Continuation paragraphs after `:+` lines |

---

## Shared concepts

### Text pipeline (nodes with prose)

For nodes that carry readable text (`:para`, `:title`, `:heading`, `:list`, `:num`):

1. **`body`** — text from the opening tag line (empty string or absent for implicit paragraphs).
2. **`raw_lines`** — accumulated source line tokens `[{:line, n, text}, …]`; used for error positions and layout round-trips.
3. **`joined_lines`** — single string built from `body` + `raw_lines` (stage 4); **this is the canonical plain-text source**.
4. **`inlines`** — keyword list parsed from `joined_lines` (stage 5); **prefer this for rendering formatted text**.

Always render from `inlines` when present; fall back to `joined_lines`, not `body`, for multi-line content.

### Tag-opened nodes

When a block starts with an explicit tag line (`:para`, `:heading`, `:quote`, …), the node inherits fields from `Hoverscript.Parser.Tagline`:

| Field | Type | Purpose |
|-------|------|---------|
| `tag` | atom | Resolved tag atom (`:para`, `:heading`, …) |
| `tag_name` | string | Tag name as written (`"para"`, `":=="`, `"**"`, …) |
| `tag_expr` | string | Normalized tag prefix (`":para:left/"`, `":=="`, …) |
| `raw_line` | string | Full original source line |
| `optionline` | map or `nil` | `[param=value]` line merged into this tag, if any; shape `%{string: "...", options: …}` |

**Implicit paragraphs** (plain text lines without a tag) omit tag metadata and set `tag_expr: ""`, `options: %{}`, `optionline: nil`.

### Nesting rules

Not every block is a direct sibling in `document.children`:

- **Headings** build an outline tree: following blocks stay in `heading.nested` until a heading of **equal or higher** level (lower number) appears.
- **List containers** (`:bullet_list`, `:ordered_list`) hold items in `items`; sub-lists live in `item.nested`.
- **Fenced containers** (`:quote`, `:footnote`, `:slot`, `:verbatim`) hold inner blocks in `nested` (or `raw_lines` for verbatim).

Walk `children`, `nested`, `items`, and `blocks` recursively to find all nodes of a given type.

### Internal parser node (not in final AST)

`:continued_list_of_blocks` exists only while parsing `:+` continuation lines. When the list item closes, its `blocks` are copied onto the parent `:list` / `:num` node and the wrapper is discarded. **You will never see this type in a finished AST.**

---

## `:document`

Root node returned by `Hoverscript.Parser.Parse.parse/1`.

| Field | Presence | Purpose |
|-------|----------|---------|
| `type` | ✓ | Always `:document` |
| `stage` | ✓ | Always `:children` |
| `line_number` | ✓ | Always `0` |
| `children` | ✓ | Ordered list of top-level block nodes |

No text fields. No `options`. Inline pass walks `children` recursively.

---

## `:literal`

Placeholder for non-content source lines (blank lines, orphaned option/continuation lines).

| Field | Presence | Purpose |
|-------|----------|---------|
| `type` | ✓ | Always `:literal` |
| `stage` | ✓ | Always `:line` |
| `line_number` | ✓ | Source line |
| `raw_lines` | ✓ | One token, e.g. `{:blankline, n, ""}` or `{:optionline, n, …}` |

No `joined_lines`, no `inlines`. Filter out when counting content blocks.

---

## `:para`

Paragraph block — explicit (`:para`, `:p`) or implicit (plain text line).

| Field | Presence | Purpose |
|-------|----------|---------|
| `type` | ✓ | Always `:para` |
| `stage` | ✓ | Always `:lines` when complete |
| `line_number` | ✓ | First line of the paragraph |
| `options` | ✓ | Tag parameters; `%{}` for implicit paragraphs |
| `raw_lines` | ✓ | Continuation lines (may be empty for single-line tagged para) |
| `joined_lines` | ✓ | Full paragraph text |
| `inlines` | ✓ | Parsed inline formatting (stage 5) |
| `body` | · | First-line text when opened with a tag |
| `tag`, `tag_name`, `tag_expr`, `raw_line` | · | Present when opened with a tag line |
| `optionline` | ✓ | `nil` or the merged option line map |

### `options` keys

| Key | Default | Values |
|-----|---------|--------|
| `align` | `"justify"` | `"left"`, `"right"`, `"center"`, `"justify"` |
| `frame` | — | `0` or `1` when set |

---

## `:title`

Document title block (`:title`). Structurally similar to `:para` but always tag-opened and never nested inside headings.

| Field | Presence | Purpose |
|-------|----------|---------|
| `type` | ✓ | Always `:title` |
| `stage` | ✓ | Always `:lines` |
| `line_number` | ✓ | First line |
| `options` | ✓ | Tag parameters |
| `body` | ✓ | First-line title text |
| `raw_lines` | ✓ | Additional title lines |
| `joined_lines` | ✓ | Full title text |
| `inlines` | ✓ | Parsed formatting |
| Tag metadata | ✓ | Always present |

### `options` keys

| Key | Default | Values |
|-----|---------|--------|
| `align` | `"center"` | `"left"`, `"right"`, `"center"` |

Appears as a direct `document.children` entry, not inside `heading.nested`.

---

## `:heading`

Section heading with outline nesting (`:=`, `:==`, `:heading`, `:h`).

| Field | Presence | Purpose |
|-------|----------|---------|
| `type` | ✓ | Always `:heading` |
| `stage` | ✓ | `:lines` while collecting title text, then `:nested` when complete |
| `line_number` | ✓ | Heading line |
| `level` | ✓ | Outline depth 1–6 (mirrors `options.level`) |
| `options` | ✓ | `%{level: n}` |
| `body` | ✓ | Title text from tag line |
| `raw_lines` | ✓ | Soft-wrapped title continuation lines |
| `joined_lines` | ✓ | Full heading title (may span multiple source lines) |
| `inlines` | ✓ | Parsed title formatting |
| `nested` | ✓ | **Section body** — all blocks until a same-or-higher-level heading |
| `blocks` | ✓ | Always `[]` on headings (reserved; continuations use list items instead) |
| Tag metadata | ✓ | Always present |

### Nesting behaviour

After the title lines are collected, the parser switches to stage `:nested`. Every following block (paragraph, list, sub-heading, …) is appended to `nested` until:

- a heading with `level <= current level` closes this section, or
- end of file.

**Consequence:** a sequence like `:= Title` / `:== Section` / paragraph produces **one** top-level `:heading` in `document.children`, not three siblings.

---

## `:sep`

Horizontal rule (`:sep`, `:separator`). Leaf node.

| Field | Presence | Purpose |
|-------|----------|---------|
| `type` | ✓ | Always `:sep` |
| `stage` | ✓ | Always `:none` |
| `line_number` | ✓ | Separator line |
| `options` | ✓ | Separator style |
| `raw_lines` | ✓ | `[{:sep, n, body}]` |
| Tag metadata | · | Present when using explicit tag |

### `options` keys

| Key | Default | Values |
|-----|---------|--------|
| `type` | `"line"` | `"line"`, `"stars"`, `"asterism"`, `"dinkus"` |

No `joined_lines`, no `inlines`.

---

## `:verbatim`

Fenced code block. Content is **literal** — no inline parsing.

| Field | Presence | Purpose |
|-------|----------|---------|
| `type` | ✓ | Always `:verbatim` |
| `stage` | ✓ | Always `:lines` |
| `line_number` | ✓ | Opening tag line |
| `options` | ✓ | Block metadata |
| `raw_lines` | ✓ | **Body lines** as `{:line, n, text}` tuples (preserved verbatim) |
| `closing_tag` | ✓ | Parsed closing `:verbatim` tag map (same shape as tag-opened metadata) |
| Tag metadata | ✓ | Opening tag fields |

### `options` keys

| Key | Default | Purpose |
|-----|---------|---------|
| `name` | `:default_verbatim` | Named block identifier for matching open/close |
| `lang` | — | `"html"`, `"js"`, `"elixir"`, … for syntax highlighting |
| `type` | — | Additional type hint when set |

No `joined_lines`, no `inlines`. Read body text from `raw_lines` line tuples.

---

## `:quote`, `:footnote`, `:slot`

Fenced containers. Inner blocks live in `nested`; closing marker stored in `closing_tag`.

| Field | `:quote` | `:footnote` | `:slot` |
|-------|----------|-------------|---------|
| `type` | ✓ | ✓ | ✓ |
| `stage` | ✓ `:nested` | ✓ `:nested` | ✓ `:nested` |
| `line_number` | ✓ | ✓ | ✓ |
| `options` | ✓ | ✓ | ✓ |
| `nested` | ✓ inner blocks | ✓ inner blocks | ✓ inner blocks |
| `closing_tag` | ✓ | ✓ | ✓ |
| `raw_lines` | ✓ opening line | ✓ opening line | ✓ opening line |
| Tag metadata | ✓ | ✓ | ✓ |

No text on the container itself — no `joined_lines` / `inlines` on these nodes.

### `options` keys

| Type | Key | Default | Purpose |
|------|-----|---------|---------|
| `:quote` | `name` | `:default_quote` | Quote identifier; same name closes the block |
| `:footnote` | `ref` | `nil` | Optional footnote reference id |
| `:slot` | `name` | `nil` | Slot identifier |

---

## `:bullet_list` and `:ordered_list`

List **containers**. Individual entries are item nodes in `items`.

| Field | Presence | Purpose |
|-------|----------|---------|
| `type` | ✓ | `:bullet_list` or `:ordered_list` |
| `stage` | ✓ | Always `:items` |
| `line_number` | ✓ | First item line |
| `level` | ✓ | Nesting depth 1–3 |
| `items` | ✓ | Ordered list of `:list` or `:num` nodes |

No text fields on the container. No `options` map on the container (level comes from the first item's tag).

A blank line between items in the source ends the current container and starts a new sibling container at the same document level.

---

## `:list` and `:num`

List **items** (bullet `:list` / `:l` / `:*`; numbered `:num` / `:n` / `:.`).

| Field | Presence | Purpose |
|-------|----------|---------|
| `type` | ✓ | `:list` or `:num` |
| `stage` | ✓ | Final stage is `:blocks` or `:nested` depending on what follows the item text |
| `line_number` | ✓ | Item tag line |
| `level` | ✓ | Item depth 1–3 |
| `options` | ✓ | Tag parameters including `level` |
| `body` | ✓ | First-line item text |
| `raw_lines` | ✓ | Soft-wrapped continuation lines within the item |
| `joined_lines` | ✓ | Full item text |
| `inlines` | ✓ | Parsed item formatting |
| `nested` | ✓ | Sub-list containers (`:bullet_list` or `:ordered_list`); empty list if none |
| `blocks` | ✓ | Continuation blocks from `:+` lines (`:para`, `:literal`, …); empty list if none |
| Tag metadata | ✓ | Always present |

### `options` keys

| Key | On | Purpose |
|-----|-----|---------|
| `level` | both | Item depth (1–3) |
| `counter` | `:num` only | Starting counter (`integer` on first item, `string` on later items) |

### Item parsing stages (why `blocks` and `nested` coexist)

1. **Title lines** → `body`, `raw_lines`, `joined_lines`
2. **`:+` continuation** → paragraphs appended to `blocks` (via internal `:continued_list_of_blocks`)
3. **Deeper list marker** → sub-list container appended to `nested`

Both `nested` and `blocks` can be non-empty on the same item.

---

## Checklist (`:checklist`, `:cl`)

The tag is recognized by the tag-line parser and has parameter definitions in `Hoverscript.Parser.Tags`, but **checklist blocks are not yet wired into `Hoverscript.Parser.ParseTokens`**. Parsing `:cl` currently produces a `:bad_tagline` error. No AST node type exists yet.

---

## Inline content (`inlines` field)

Not a block node — a keyword list stored **on** text-bearing block nodes after stage 5.

| Parent `type` | Inline parsing |
|---------------|----------------|
| `:para`, `:title`, `:heading` | On `joined_lines` |
| `:list`, `:num` | On item `joined_lines` |
| `:verbatim`, `:sep`, `:literal` | No |
| Containers (`:quote`, …) | No (inlines live on inner nodes) |

See [Inline nodes](inlines.html) for the keyword-list structure.

---

## Related

- [AST overview](../AST.html) — pipeline, traversal, module index
- [Block nodes](blocks.html) — examples per block type
- [List nodes](lists.html) — nesting and continuations
- [Errors](errors.html) — partial AST and error map
