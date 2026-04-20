# How to Use DocAtlas

This document describes how to use DocAtlas:

1. Build the documentation (`build.ps1`)
2. Update Marked.js (`updateMarked.ps1`)
3. Start the local HTTP server (`startServer.ps1`)

---

## 1. Generate Markdown Export & Search Index (`build.ps1`)

This script processes Markdown files from the `src` directory, copies them into the `docs` directory, and generates a JSON‑based search index.

### Parameters

- **Root**: Project root directory  
- **Depth**: JSON serialization depth for the search index

### Default Values

If no parameters are provided:

- **Root:** `$PSScriptRoot`
- **Depth:** `4`

### Paths

- **Source directory:** `src`
- **Target directory (Markdown):** `docs\md`
- **Search index file:** `docs\search.json`

### Process

- Sets default values for `Root` and `Depth` if not specified
- Defines source and destination paths
- Deletes the existing `docs\md` directory (if it exists)
- Creates a new target directory
- Iterates through all `.md` files in the `src` directory:
  - Copies each file to `docs\md`
  - Extracts the title from the first Markdown heading (`# ...`)
  - Fallback: file name without extension
  - Adds an entry to the search index:
    - `title`
    - `file`
- Serializes the search index as JSON
- Saves it as `docs\search.json`

### Purpose

Automatically prepares a static documentation structure including:

- exported Markdown files
- an easy‑to‑use JSON search index for frontend search or navigation

### Execution

From the project root (where `build.ps1` is located):

```powershell
.\build.ps1
```

After running the script you should have:

- `docs/md/...` → the copied Markdown files
- `docs/search.json` → JSON index used by the menu in `app.js`

**Tip:** Run `build.ps1` after every change in `src/*.md` so the updates are reflected in `docs`.

---

## 2. Update Marked.js (`updateMarked.ps1`)

This script downloads the latest (or a specified) version of `marked.min.js` and stores it in the project.

### Parameters

- **TargetDir**: Target directory for the file  
- **MarkedURL**: Download source (default: jsDelivr CDN)

### Default Values

If no parameters are provided:

- **Target directory:** `docs\lib` (relative to the script directory)
- **Source:** `https://cdn.jsdelivr.net/npm/marked/marked.min.js`

### Process

- Checks if the target directory exists and creates it if necessary
- Downloads the file using `Invoke-WebRequest`
- Saves the file as `marked.min.js`
- Outputs the full destination path as a status message

### Purpose

Allows easy updating of a local Marked.js version for web or documentation projects without manually integrating a CDN.

### Default Usage

From the project root:

```powershell
tools\updateMarked.ps1
```

- Target directory (default): `docs\lib`
- URL (default):  
  `https://cdn.jsdelivr.net/npm/marked/marked.min.js`

Result:

```
docs\lib\marked.min.js
```

is created or overwritten.

### Using a Specific Version

Example: download a specific version of Marked:

```powershell
tools\updateMarked.ps1 -MarkedURL "https://cdn.jsdelivr.net/npm/marked@11.2.0/marked.min.js"
```

### Using a Different Target Directory

```powershell
.\updateMarked.ps1 -TargetDir "C:\temp\marked-test"
```

This will create:

```
C:\temp\marked-test\marked.min.js
```

---

## 3. Start the Local HTTP Server (`startServer.ps1`)

The HTTP server allows you to test the documentation locally in a browser without issues related to `file://` and `fetch()`.

### Parameters

- **DocsRoot** → Directory that will be served (typically `docs`)
- **Port** → Port number (e.g. `8080`)

### Default Values

If no parameters are provided:

- **DocsRoot:** `docs` (relative to the script directory)
- **Port:** `8080`

### How It Works

- Starts a simple HTTP server using `System.Net.HttpListener`
- Listens on:

```
http://localhost:<Port>/
```

- Serves static files from the specified DocsRoot directory

### Supported MIME Types

Includes support for:

- HTML, CSS, JavaScript
- JSON
- Markdown (`.md` served as `text/plain`)
- Images (PNG, JPG, GIF, SVG)

### Request Handling

- `/` is automatically resolved to `index.html`
- URL paths are decoded and mapped to the filesystem
- Protection against path traversal (access outside DocsRoot is blocked)

### Response Behavior

- **200 OK** → File found and served
- **404 Not Found** → File does not exist
- **500 Internal Server Error** → Internal error occurred

### Runtime Behavior

- Server runs continuously in a loop
- Requests are handled synchronously
- Stop the server with **Ctrl + C**

---

## 4. Typical Workflow

1. **Edit Markdown files**

Write or update content in:

```
src/*.md
```

2. **Run the build**

```powershell
.\build.ps1
```

3. **(Optional) Update Marked.js**

Only required when testing or upgrading to a new version:

```powershell
.\updateMarked.ps1
```

4. **Start the HTTP server**

```powershell
.\docs\startServer.ps1 -Root .\docs -Port 8080
```

5. **Open the documentation in a browser**

```
http://localhost:8080
```

---

## 5. Troubleshooting

### Browser cannot load `search.json` or `.md`

- Check if the server is running (PowerShell window open, no errors)
- Verify that `build.ps1` was executed
- Ensure the following files exist:

```
docs/md/...
docs/search.json
```

### Errors in the browser console (F12)

**`Failed to fetch`**

- Server not reachable
- Check if the port is correct

**`pages.forEach is not a function`**

- `search.json` does not contain an array
- Re-run `build.ps1`

---

With these steps you should be able to operate DocAtlas from an empty project up to a fully running local documentation site.
