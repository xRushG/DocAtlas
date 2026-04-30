# Generally Markdown Help

A quick reference for the most important Markdown elements used in this project.

---

## Headings

```md
# Heading 1
## Heading 2
### Heading 3
#### Heading 4
##### Heading 5
###### Heading 6
```

---

## Paragraphs & Line Breaks

- New paragraph: leave **one empty line** between paragraphs  
- Manual line break: use **two spaces at the end of the line** or `<br>`

```md
This is paragraph 1.

This is paragraph 2 (separated by an empty line).

Line 1 with a break␣␣
Line 2 after the break

Line 3<br>
Line 4 after `<br>`
```

---

## Text Formatting

```md
*italic* or _italic_
**bold** or __bold__
***bold and italic***

~~strikethrough~~

`inline code`
```

---

## Lists

### Unordered Lists

```md
- Item 1
- Item 2
  - Subitem 2.1
  - Subitem 2.2

* Alternatively using asterisks
```

### Ordered Lists

```md
1. First item
2. Second item
   1. Subitem
   2. Subitem
```

---

## Links & Images

### Links

```md
[Link text](https://example.com)

[Link with title](https://example.com "Tooltip text")
```

### Images

```md
![Alt text](image.png)

![Alt text with title](image.png "Image title")
```

---

## Quotes (Blockquotes)

```md
> This is a quote.
> It can span multiple lines.

> Quote level 1
>> Quote level 2 (nested)
```

---

## Code

### Inline Code

```md
Use `single backticks` for inline code.
```

### Code Blocks (Fenced Code Blocks)

Use three backticks before and after the block, optionally with a language identifier:

```text
This is a code block without syntax highlighting.
Multiple lines are possible.
```

```bash
echo "Code block with language (bash)"
ls -la
```

```json
{
  "name": "Example",
  "active": true
}
```

---

## Horizontal Rule

```md
---
***
___
```

All three variants create a horizontal separator line.

---

## Tables

```md
| Column 1 | Column 2 | Column 3 |
|----------|----------|----------|
| Value A  | Value B  | Value C  |
| 1        | 2        | 3        |
```

Alignment:

```md
| Left      | Centered   | Right     |
|:----------|:----------:|----------:|
| Text      | Text       | Text      |
| More text | More text  | More text |
```

---

## Task Lists

(Supported by GitHub and many Markdown renderers.)

```md
- [ ] Open task
- [x] Completed task
- [ ] Another task
```

---

## Inline HTML (for special cases)

Some renderers allow HTML directly inside Markdown (for example `<details>`):

```md
<details>
  <summary>Expandable section</summary>

  Content that can be expanded or collapsed.
</details>
```

> Note: HTML support depends on the renderer.

---

## Escaping Characters

If a character should **not** be interpreted as Markdown, it can be escaped with a backslash:

```md
\*this text is not italic\*
\# This is not a heading
\[square brackets\]
```

---

## (Optional) Formulas with LaTeX Syntax

Whether formulas are rendered depends on the renderer or plugin being used.

Common convention:

- Inline: `\( a^2 + b^2 = c^2 \)`
- Block:

```tex
\[
  E = mc^2
\]
```

---

## Practical Tips

- Use a clear structure with `#` (title) and `##` (sections) to keep documents organized.  
- Always place longer code examples inside code blocks.  
- Use tables sparingly – they can be a bit error‑prone when editing.  
- Simply edit the `.md` files and run your build script again to update the documentation.