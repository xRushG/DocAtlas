# How to Use DocAtlas

This document explains how to use **DocAtlas**, including the build process, configuration files, search functionality, syntax highlighting, and helper update scripts.

DocAtlas is a lightweight static documentation tool that builds a documentation website from Markdown files.

Main features:

- Markdown‑based documentation
- Automatic navigation generation
- Full‑text search
- Client‑side syntax highlighting
- Copy buttons for code blocks
- Local development server
- Static output (no backend required)

---

# Project Structure

A typical DocAtlas project looks like this:

```
project-root/
│
├─ src/                        # Markdown documentation source
│
├─ html/                    
│   ├─ md/					   # SRC documentation sites and generated index files
│   ├─ assets/
│   │   ├─ navigation.json	   # generated navigation
│   │   ├─ search-index.json   # generated search index
│   │   └─ other files         # LOGOs...
│   ├─ lib/
│   ├─ app.js				   # javascript code
│   ├─ app.json 			   # Runtime configuration for the frontend
│   └─ index.html
│
├─ tools/                      # Helper scripts for library updates
│   ├─ updateHighlight-css.ps1
│   ├─ updateHighlight-js.ps1
│   ├─ updateMarked-js.ps1
│   └─ updateMiniSearch-js.ps1
│
├─ build.ps1                   # Documentation build script
├─ build.ini                   # Build configuration -> is building ports for app.json
├─ startServer.ps1			   # local PowerShell 7 web service helper
```

---

# 1. Configuration

DocAtlas uses two configuration files:

## build.ini

`build.ini` defines build‑time settings used by the PowerShell build script.

Typical configuration includes:

- markdown source directory
- output directory
- navigation generation settings
- search index settings
- table of contents options

The build script reads this file when generating the documentation site.

---

## app.json

`app.json` contains configuration used by the frontend application.

Typical settings include:

- navigation file location
- search index file location
- markdown folder path
- theme settings
- logo configuration
- custom stylesheet support

Example responsibilities:

```
environment paths
navigation settings
search index location
UI options
```

---

# 2. Build the Documentation (`build.ps1`)

The build script scans the Markdown files inside the `src` directory and generates the static documentation site.

### Run the build

From the project root:

```powershell
.\build.ps1
```

### What the build script does

The build process performs the following steps:

1. Reads configuration from `build.ini`
2. Scans the `src` directory for Markdown files
3. Builds a hierarchical documentation tree
4. Copies Markdown files into the output directory
5. Generates automatic `index.md` files where needed
6. Generates the navigation structure
7. Builds the full‑text search index

### Output

After the build you will have:

```
html/md/
html/assets/navigation.json
html/assets/search-index.json
```

---

# 3. Search Functionality

DocAtlas includes a built‑in **client‑side full‑text search** powered by **MiniSearch**.

The search bar is located in the sidebar and searches across:

- page titles
- Markdown headings
- documentation content

### Search Index

The search index is generated automatically during the build process:

```
html/assets/search-index.json
```

The index contains:

```
title
slug
text
```

Search results link directly to the relevant page.

---

# 4. Syntax Highlighting

DocAtlas uses **Highlight.js** for client‑side syntax highlighting of Markdown code blocks.

Example Markdown:

````markdown
```powershell
Get-Service
```
````

Supported languages include:

- PowerShell
- Bash
- JSON
- YAML
- Batch
- JavaScript
- HTML
- CSS

---

# 5. Code Copy Buttons

Every code block automatically receives a **Copy button**.

Features:

- one‑click copy
- clipboard integration
- visual feedback ("Copied!")

Example layout:

```
POWERSHELL                     [Copy]

Get-Service
```

---

# 6. Local HTTP Server (`startServer.ps1`)

A small PowerShell HTTP server is included for local testing.

This avoids issues caused by opening files directly with:

```
file://
```

### Start the server

```powershell
.\startServer.ps1 -Root .\html -Port 8080
```

### Default settings

| Parameter | Default |
|-----------|--------|
| DocsRoot | html |
| Port | 8080 |

### Open in browser

```
http://localhost:8080
```

---

# 7. Updating Frontend Libraries

DocAtlas includes helper scripts in the **tools** directory to update client‑side libraries.

These scripts download the latest versions from the CDN.

---

## Update Highlight.js CSS

```
tools/updateHighlight-css.ps1
```

Downloads the latest Highlight.js stylesheet used for syntax highlighting.

---

## Update Highlight.js JavaScript

```
tools/updateHighlight-js.ps1
```

Downloads the Highlight.js runtime library used for syntax highlighting.

---

## Update Marked.js

```
tools/updateMarked-js.ps1
```

Updates the **Marked.js** Markdown renderer.

Marked.js converts Markdown into HTML inside the browser.

---

## Update MiniSearch

```
tools/updateMiniSearch-js.ps1
```

Updates the **MiniSearch** library used for full‑text search.

---

# 8. Typical Workflow

### 1. Edit documentation

Write or update Markdown files in:

```
src/
```

---

### 2. Run the build

```
.\build.ps1
```

---

### 3. Start the local server

```
.\startServer.ps1 -Root .\html -Port 8080
```

---

### 4. Open the documentation

```
http://localhost:8080
```

---

### 5. Test

Verify that the following features work correctly:

- navigation
- search results
- syntax highlighting
- copy buttons for code blocks

---

# 9. Troubleshooting

### Search does not work

Check if the search index exists:

```
html/assets/search-index.json
```

Then rebuild the documentation:

```
.\build.ps1
```

---

### Navigation does not load

Verify that the navigation index exists:

```
html/assets/navigation.json
```

---

### Syntax highlighting missing

Ensure these files exist in the library directory:

```
highlight.min.js
highlight.css
```

---

### Browser console errors

Open the developer tools:

```
F12
```

Look for errors such as:

- missing files
- JSON parsing errors
- fetch failures

---

Using these steps you can build, preview, and maintain a complete documentation website with **DocAtlas**.
:::