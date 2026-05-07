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


> This is paragraph 1.
> 
> This is paragraph 2 (separated by an empty line).
> 
> Line 1 with a break␣␣
> Line 2 after the break
> 
> Line 3<br>
> Line 4 after `<br>`

---

## Text Formatting

```md
*italic* or _italic_
**bold** or __bold__
***bold and italic*** or ___bold and italic___
~~strikethrough~~
`inline code`
```


> *italic* or _italic_
> 
> **bold** or __bold__
> 
> ***bold and italic***
> 
> ~~strikethrough~~
> 
> `inline code`

---

## Lists

```md
- Item 1
- Item 2
  - Subitem 2.1
  - Subitem 2.2


Alternatively using:

- dash -> (default)
* asterisks
° circle
~ tilde
+ plus
-> arrow right
<- arrow left
<3 heart
<X cross
<C check
```


> - Item 1
> - Item 2
>   - Subitem 2.1
>   - Subitem 2.2

**Alternatively using:**

> - dash -> (default)
>   * asterisks
> ° circle
>   ~ tilde
> + plus
>   -> arrow right
>     <- arrow left
>   <3 heart
> <X cross
> <C check

---

## Ordered List

```md
1. First item
2. Second item
   1. Subitem
   2. Subitem
```

> 1. First item
> 2. Second item
>     1. Subitem
>     2. Subitem


---

## Task Lists

(Supported by GitHub and many Markdown renderers.)

```md
- [ ] Open task
- [x] Completed task
- [ ] Another task
```


> - [ ] Open task
> - [x] Completed task
> - [ ] Another task

---

## Links

```md
Whitout tooltip text:
[Link text](https://example.com)

Whit tooltip text
[Link with title](https://example.com "Tooltip text")

Auto Url
<https://www.example.org>

Auto Mail
<mail@example.com>

```

> *Whitout tooltip text* <br>
> [Link text for example.com](https://example.com)
>
> *Example whit tooltip text* <br>
> [Link text for example.com with Tooltip](https://example.com "Tooltip text")
>
> *Auto Url* <br>
> <https://www.example.com>
>
> *Auto Mail* <br>
> <mail@example.com>


## Images

```md
![Alt text](image.png)

![Alt text with title](image.png "Image title")
```


---

## Quotes (Blockquotes)

```md
> This is a quote.
> It can span multiple lines.
> 
> Or lists:
> * List 1
> * List 2
> 
> 
> After list, go on in quoted area 
> Quote level 1 
>> Quote level 2 (nested) 
> 
> Add inline Code 
>> `Inline code`
>>> Up to depth of six
```

### Example
> This is a quote.
> It can span multiple lines.
> 
> Or lists:
> * List 1
> * List 2
> 
> 
> After list, go on in quoted area 
> Quote level 1 
>> Quote level 2 (nested) 
> 
> Add inline Code 
>> `Inline code`
>>> Up to depth of six


---

## Inline Code

```md
Use `single backticks` for inline code.
```

>
> Use `single backticks` for inline code.
>

## Code Blocks (Fenced Code Blocks)

Use three or more backticks to open a code block, optionally followed by a language identifier. If you open the block with more than three backticks, you must close it with the same number of backticks. 

The advantage becomes clear with your example (its opend with four backticks):

````md

```bash
echo "Code block with language (bash)"
ls -la
```

````

By opening the outer block with four backticks, you can include an inner block that uses three backticks without prematurely closing the outer block.


::da:important Concrete benefits
The inner code block remains visibly intact and syntactically correct (including language).
No escaping or modification of the inner code is required.
The parser can clearly distinguish how many backticks where used to open and needed to close.
::da:end

::da:alert  Attention
Improper use of Markdown can break the parser.
::da:end


### Exampels

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

---*

---_

---.

```

All three variants create a horizontal separator line.

### Examples

*hr-thin*


---


*hr-symbol*


---*


*hr-dashed*


---_


*hr-doted*

---.

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

### Examples


| Column 1 | Column 2 | Column 3 |
|----------|----------|----------|
| Value A  | Value B  | Value C  |
| 1        | 2        | 3        |


With Alignment:


| Left      | Centered   | Right     |
|:----------|:----------:|----------:|
| Text      | Text       | Text      |
| More text | More text  | More text |



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

### Example

<details>
  <summary>Expandable section</summary>

  Content that can be expanded or collapsed.
</details>

---

## Escaping Characters

If a character should **not** be interpreted as Markdown, it can be escaped with a backslash:

```md
\*this text is not italic\*
\# This is not a heading
\[square brackets\]
```


\*this text is not italic\*

\# This is not a heading

\[square brackets\]


---

## Practical Tips

- Use a clear structure with `#` (title) and `##` (sections) to keep documents organized.  
- Always place longer code examples inside code blocks.  
- Use tables sparingly – they can be a bit error‑prone when editing.  
- Simply edit the `.md` files and run your build script again to update the documentation.