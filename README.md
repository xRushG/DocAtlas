# DocAtlas

DocAtlas is a lightweight static documentation tool for building structured technical documentation from Markdown files.  
It generates a navigable documentation site with hierarchical navigation, automatic index pages, and full‑text search.

The project is designed to be simple, fast, and completely static. No database, no backend, and no complex build tools are required.

---

## Features

- Markdown‑based documentation
- Automatic navigation generation
- Hierarchical URLs based on folder structure
- Automatic index pages with table of contents
- Full‑text search
- Static HTML output
- Works completely offline
- Dark / Light theme support
- Simple PowerShell build process

---

## How It Works

DocAtlas scans a source directory containing Markdown files and builds a documentation site from it.

Example structure:

```
src/
 ├ Your Projects/
 │  ├ /Project A/
 │  │  └ Installation.md
 │  └ /Project B/
 │     └ Hwo To Do.md
 └ DocAtlas/
    └ _01_Markdown-CheatSheet.md
    └ _02_how-to-use-doku-tool.md
```

During the build process the tool automatically generates:

- a navigation structure
- index pages with table of contents
- a full‑text search index
- static Markdown output for the web viewer

---

## Build Process

The build script scans the `src` directory and generates the final documentation site inside the `html` directory.

Generated files include:

```
html/
 ├ md/
 ├ assets/navigation.json
 ├ assets/search-index.json
 ├ app.json
 └ index.html
```

---

## Usage

Run the build script:

```
.\build.ps1
```

This will:

1. Scan the documentation source directory
2. Build the navigation tree
3. Generate index pages
4. Build the search index
5. Copy all Markdown files to the output directory

---

## Documentation Structure

Each folder can contain:

```
index.md        → Folder overview page
*.md            → Documentation pages
```

Folders automatically become navigation nodes.

Example:

```
md/
 ├ Your Projects/
 │  ├ /Project A/
 │  │  └ index.md
 │  │  └ Installation.md
 │  └ /Project B/
 │     └ index.md
 │     └ Hwo To Do.md
```

Resulting URL structure:

```
#Your_Projects/Project A
#Your_Projects/Project A/Installation
```

---

## Search

DocAtlas provides a built‑in full‑text search.

The build process generates a search index which allows searching:

- page titles
- headings
- content text

Results link directly to the relevant section in the documentation.

---

## Requirements

- PowerShell
- Modern web browser

No additional dependencies are required.

---

## License

This project is licensed under the MIT License.

---

## Contributing

Contributions, improvements, and suggestions are welcome.

If you find a bug or want to add a feature, feel free to open an issue or submit a pull request.

---

## Project Goals

DocAtlas was created to provide a simple and maintainable documentation solution for technical teams and infrastructure projects.

The focus is on:

- simplicity
- maintainability
- fast static builds
- minimal dependencies
- long‑term usability