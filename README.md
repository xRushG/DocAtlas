# DocAtlas

DocAtlas is a lightweight static documentation generator that turns a folder of Markdown files into a fully navigable documentation site — no database, no backend, no Node.js.

---

## Features

### Zero-dependency output
The generated site runs entirely in the browser. No server-side logic, no build tools required to view it. Drop the output folder onto any static file host or open it locally.

### Automatic navigation
DocAtlas mirrors your folder structure into a collapsible sidebar navigation. Folders become navigation groups, files become entries. Depth is configurable.

### Baked-in table of contents
Each folder automatically gets an index page with a table of contents listing all documents in that section. No manual maintenance needed.

### Slide-in full-text search
Powered by [MiniSearch](https://lucaong.github.io/minisearch/), the search index is built at compile time and searches across page titles, headings, and body content. Results open a slide-in panel that links directly to the matching section.

### Syntax highlighting
Code blocks are highlighted at runtime via [highlight.js](https://highlightjs.org/) with no additional setup.

### Dark / Light theme
A toggle button switches between themes. The preference is preserved across page loads.

### Configurable build
`build.ini` controls output paths, folder names, navigation depth, table of contents behaviour, logo assets, and more. All values flow through to the browser via a generated `app.json`.

### Built-in dev server
`startServer.ps1` spins up a local HTTP server to preview the build output directly in the browser.

---

## How It Works

Place Markdown files in the `src/` directory. Run `build.ps1`. The script scans the source tree, converts Markdown to HTML, generates navigation and search index, and writes everything to the configured output folder.

**Example source structure:**

```
src/
 ├ Your Projects/
 │  ├ Project A/
 │  │  └ Installation.md
 │  └ Project B/
 │     └ How To Start.md
 └ DocAtlas/
    └ _01_Markdown-CheatSheet.md
    └ _02_How-To-Use.md
```

**Generated output:**

```
html/                        ← configurable via build.ini (buildFolder)
 ├ sites/                    ← converted HTML files (sitesFolder)
 ├ css/                      ← stylesheets
 ├ lib/                      ← MiniSearch, highlight.js
 ├ assets/
 │  └ search-index.json      ← pre-built search index
 ├ app.js                    ← browser application
 ├ app.json                  ← generated runtime config
 └ index.html                ← entry point with baked-in navigation
```

---

## Usage

**Build the documentation:**

```powershell
.\build.ps1
```

**Start the local dev server:**

```powershell
.\startServer.ps1           # serves html/ on http://localhost:8080

```

---

## Configuration

All build behaviour is controlled by `build.ini`:

```ini
[environment]
buildFolder  = "html"         ; output root folder
sitesFolder  = "sites"        ; converted HTML files
cssFolder    = "css"
libFolder    = "lib"
assetsFolder = "assets"
searchIndexFile = "assets\search-index.json"

[navigation]
depth = 2                     ; sidebar navigation depth

[tableOfContents]
enabled = true
depth   = 2

[logo]
enabled = true
dark    = "assets/logo-dark.png"
light   = "assets/logo-light.png"
```

---

## Requirements

- PowerShell 7+
- A modern web browser

No additional dependencies are required.

---

## License

This project is licensed under the MIT License.

---

## Contributing

Contributions, improvements, and suggestions are welcome.  
Feel free to open an issue or submit a pull request.
