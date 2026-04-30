# DocAtlas MarkDown Help

## Overview
DocAtlas extends ordinary Markdown with **semantic boxes** (call‑outs).  
A box is defined by a simple prefix and is turned into a styled HTML block when rendered.

---

## Syntax

```md
::da:<type> <Title>
Your content here…
::da:end
```

*`<type>`* – one of the supported box‑types (see the list below)  
*`<Title>`* – the heading that will appear on the box (required for a proper rendering)

**Example**

```md
::da:info Info Box
This is an *Info* box.
::da:end
```

---

## Available Box Types

Below you’ll find the corrected examples. Each example now includes the required **title** right after the type name, so the heading is displayed correctly.

### Alert

```md
::da:alert My Alert Title
This is an **Alert** box (critical, immediate attention required).
::da:end
```

::da:alert My Alert Title
This is an **Alert** box (critical, immediate attention required).
::da:end

### Important

```md
::da:important My Important Title
This is an **Important** box (key information).
::da:end
```

::da:important My Important Title
This is an **Important** box (key information).
::da:end


### Warning

```md
::da:warning My Warning Title
This is a **Warning** box (caution advised).
::da:end
```

::da:warning My Warning Title
This is a **Warning** box (caution advised).
::da:end

### Question

```md
::da:question My Question Title
This is a **Question** box (open question or thought‑prompt).
::da:end
```

::da:question My Question Title
This is a **Question** box (open question or thought‑prompt).
::da:end

### Tip

```md
::da:tip My Tip Title
This is a **Tip** box (useful hint).
::da:end
```

::da:tip My Tip Title
This is a **Tip** box (useful hint).
::da:end

### Info

```md
::da:info My Info Title
This is an **Info** box (neutral information).
::da:end
```

::da:info My Info Title
This is an **Info** box (neutral information).
::da:end

### Danger

```md
::da:danger My Danger Title
This is a **Danger** box (error, risk, possible damage).
::da:end
```

::da:danger My Danger Title
This is a **Danger** box (error, risk, possible damage).
::da:end

### Success

```md
::da:success My Success Title
This is a **Success** box (successful state).
::da:end
```

::da:success My Success Title
This is a **Success** box (successful state).
::da:end

### Note

```md
::da:note My Note Title
This is a **Note** box (additional remark).
::da:end
```

::da:note My Note Title
This is a **Note** box (additional remark).
::da:end

### Example

```md
::da:example My Example Title
This is an **Example** box (illustration / use‑case).
::da:end
```

::da:example My Example Title
This is an **Example** box (illustration / use‑case).
::da:end

---

## Tips & Gotchas

| Rule | Why it matters | How to apply |
|------|----------------|--------------|
| **Marker must start at column 1** | The parser only recognises `::da:` when it is the first characters on a line. | No preceding spaces or other characters. |
| **Title is mandatory** | Without a title the heading is omitted, making the box look “broken”. | Write `::da:<type> <Title>` on the opening line. |
| **Content follows directly** | Anything after the opening line is treated as the box’s body. | Put your text (or other Markdown) on the next line(s). |
| **Multiline content is allowed** | Boxes can contain paragraphs, lists, code fences, etc. | Just continue writing; close with `::da:end` on its own line. |
| **Consistent closing** | The parser stops at the first `::da:end`. | Ensure you have exactly one closing tag per box. |

---

### Quick reference

```text
::da:alert   Alert
::da:important Important
::da:warning  Warning
::da:question Question
::da:tip      Tip
::da:info     Info
::da:danger   Danger
::da:success  Success
::da:note     Note
::da:example  Example
```

Use any of the lines above as a template, replace the body with your own content, and finish with `::da:end`.
