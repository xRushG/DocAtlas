param (
    [string] $ini
)
cls
if ($PSVersionTable.PSVersion.Major -lt 7) {

    Add-Type -AssemblyName PresentationFramework

    [System.Windows.MessageBox]::Show(
        "This script requires PowerShell 7 (pwsh).`nPlease run it in a PowerShell 7 session.",
        "Error",
        'OK',
        'Error'
    ) | Out-Null

    exit 1
}

#--------------------------------------------------
#  INI file preparation
#--------------------------------------------------
function Read-IniFile {
<#
.SYNOPSIS
    Parses a simple INI file.

.DESCRIPTION
    Reads the file line by line, strips block comments (/* ... */),
    recognises sections ([section]) and key/value pairs
    (key="value" or key=value), and builds a nested hashtable.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    # -----------------------------------------------------------------
    # 1. Load file and strip block comments (/* ... */)
    # -----------------------------------------------------------------
    if (-not (Test-Path -LiteralPath $Path)) {
        Throw "File not found: $Path"
    }

    $rawLines = Get-Content -LiteralPath $Path -Raw
    # Remove multiline block comments -- they may span several lines
    $noBlockComments = [regex]::Replace(
        $rawLines,
        '/\*.*?\*/',
        '',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    $lines = $noBlockComments -split "`r?`n" |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $lines = $lines | ForEach-Object {
        ($_ -replace '//.*$', '').Trim()
    } | Where-Object { $_ }

    $iniData = @{}
    $currentSection = $null

    switch -regex ($lines) {
        # -----------------------------------------------------------------
        # 2. Parse sections ([section])
        # -----------------------------------------------------------------
        '^\s*\[(.+?)\]\s*$' {
            $currentSection = $matches[1].Trim()
            if (-not $iniData.ContainsKey($currentSection)) {
                $iniData[$currentSection] = @{}
            }
            continue
        }

        # -----------------------------------------------------------------
        # 3. Parse key/value pairs (key="value" or key=value)
        # -----------------------------------------------------------------
        '^\s*([^=]+?)\s*=\s*(.+?)\s*$' {
            if (-not $currentSection) {
                Throw "Key/value pair found outside of any section: '$($_)'"
            }

            $key   = $matches[1].Trim()
            $value = $matches[2].Trim()

            # Remove surrounding quotes if present
            if ($value -match '^"(.*)"$') {
                $value = $matches[1]
            }

            # Basic type conversion
            switch -regex ($value) {
                '^true$'        { $value = $true }
                '^false$'       { $value = $false }
                '^\d+$'         { $value = [int]$value }
                '^\d+\.\d+$'   { $value = [double]$value }
                '^\[\]$'        { $value = @() }
                '^\[(.+)\]$'   {
                    # Split comma-separated values inside []
                    $value = ($matches[1] -split ',').ForEach({ $_.Trim() })
                }
            }

            $iniData[$currentSection][$key] = $value
        }
    }

    Write-Output ($iniData | ConvertTo-Json | ConvertFrom-Json)
}

function Set-DebugConfig {
<#
.SYNOPSIS
    Prepares the debug configuration.

.DESCRIPTION
    Attaches debug-specific output paths and file name defaults
    to the config object.
#>
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNull()]
        $config,
        [Parameter(Mandatory, Position = 1)]
        $SCRIPT_ROOT
    )

    $config.debug | Add-Member -Name outPath             -Value (Join-Path $SCRIPT_ROOT "debug") -MemberType NoteProperty
    $config.debug | Add-Member -Name tree_default        -Value "debug_tree.json"                -MemberType NoteProperty
    $config.debug | Add-Member -Name navigation          -Value "debug_nav.json"                 -MemberType NoteProperty
    $config.debug | Add-Member -Name globalSearchIndex   -Value "debug_gsi.json"                 -MemberType NoteProperty
    $config.debug | Add-Member -Name searchIndexSufix    -Value "debug_si_{0}.json"              -MemberType NoteProperty
    $config.debug | Add-Member -Name appConfig           -Value "debug_appConfig.json"           -MemberType NoteProperty

    return $config
}

function Optimize-ConfigValues {
<#
.SYNOPSIS
    Validates and normalises configuration values.

.DESCRIPTION
    Ensures that path values end with a forward slash,
    normalising both backslash and forward-slash variants.
#>
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNull()]
        $config
    )

    # FIX 3: Normalise trailing separator -- accept both \ and /
    $config.environment.htmlSrcFolder = $config.environment.htmlSrcFolder.TrimEnd('\', '/') + '/'

    return $config
}

# --------------------------------------------------
#  Markdown title, subtitle and slug helpers
# --------------------------------------------------
function Get-Title {
<#
.SYNOPSIS
    Extracts the main title from a Markdown file.

.DESCRIPTION
    Reads the file and returns the text of the first H1 heading.
    Falls back to the file name (without extension) if no H1 is found.
#>
    param (
        [Parameter(Mandatory)]
        $file
    )

    $title = Get-Content $file |
        Where-Object { $_ -match "^# " } |
        Select-Object -First 1

    if ($title) {
        return ($title -replace "^# ", "")
    }

    return [System.IO.Path]::GetFileNameWithoutExtension($file)
}


function Get-CleanMarkdownContent {
<#
.SYNOPSIS
    Strips Markdown syntax from content, returning plain text.

.DESCRIPTION
    Removes fenced code blocks, inline code, images, links, headings,
    blockquotes, emphasis markers, HTML tags, and DocAtlas custom directives
    so that the resulting text can be used for full-text search indexing.
#>
    param (
        [Parameter(Mandatory)]
        $content
    )

    # Remove fenced code blocks (multiline)
    $content = [regex]::Replace($content, '```[\s\S]*?```', '')

    # Remove inline code
    $content = [regex]::Replace($content, '`[^`]*`', '')

    # Remove images: ![alt](url)
    $content = [regex]::Replace($content, '!\[.*?\]\(.*?\)', '')

    # Convert links [text](url) -> text
    $content = [regex]::Replace($content, '\[([^\]]+)\]\([^)]+\)', '$1')

    # Remove headings (#, ##, etc.)
    $content = [regex]::Replace($content, '^\s*#+\s*', '', 'Multiline')

    # Remove blockquotes
    $content = [regex]::Replace($content, '^\s*>\s?', '', 'Multiline')

    # Remove emphasis markers (*, _, **)
    $content = [regex]::Replace($content, '(\*\*|\*|__|_)', '')

    # Remove HTML tags
    $content = [regex]::Replace($content, '<[^>]+>', '')

    # Remove DocAtlas custom directives
    $content = [regex]::Replace($content, '::da:\w+', '')
    $content = [regex]::Replace($content, '::da:end', '')

    return $content.Trim()
}

function Get-Slug {
<#
.SYNOPSIS
    Converts a string into a URL-friendly slug.

.DESCRIPTION
    Lowercases the input, replaces German umlauts with ASCII equivalents,
    strips special characters, and replaces whitespace with hyphens.
#>
    param (
        [Parameter(Mandatory)]
        $text
    )

    $slug = $text.ToLower()

    $slug = $slug -replace "ä", "ae"
    $slug = $slug -replace "ö", "oe"
    $slug = $slug -replace "ü", "ue"
    $slug = $slug -replace "ß", "ss"

    $slug = $slug -replace "\\", "/"           # Normalise path separators
    $slug = $slug -replace "[^a-z0-9\s\-/]", "" # Keep letters, digits, spaces, hyphens, slashes
    $slug = $slug -replace "\s+", "-"           # Spaces to hyphens

    return $slug.Trim("-")
}

# --------------------------------------------------
#  File copy and indexing helpers
# --------------------------------------------------
function Copy-Files {
<#
.SYNOPSIS
    Recursively copies files from source to destination,
    preserving the directory structure.
#>
    param(
        [string]$Source,
        [string]$Destination
    )

    $files = Get-ChildItem $Source -Recurse -File

    foreach ($file in $files) {

        $relative = $file.FullName.Substring($Source.Length).TrimStart("\", "/")
        $dest     = Join-Path $Destination $relative
        $destDir  = Split-Path $dest

        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        }

        $null = Copy-Item $file.FullName $dest -Force
    }
}

# --------------------------------------------------
#  Tree building and processing
# --------------------------------------------------
function Build-Tree {
<#
.SYNOPSIS
    Builds the root node of the documentation tree.

.DESCRIPTION
    Reads the top-level index file from BasePath, extracts its title and
    section data, then recursively collects all child pages and folders
    via Write-Tree. Returns a single root PSCustomObject that represents
    the entire documentation hierarchy.

.PARAMETER BasePath
    Absolute path to the root of the Markdown source directory.
#>
    param(
        [Parameter(Mandatory)]
        [string]$BasePath
    )

    $IndexFileName = $buildConf.tableOfContents.name?.Trim() ?? "index.md"
    $indexFile     = Join-Path $BasePath $IndexFileName

    $global:UsedSlugs = @{}

    $title   = "Home"
    $Content = @()

    if (Test-Path $indexFile) {
        $raw     = Get-Content $indexFile -Raw
        $Content = Split-MarkdownSections -Markdown $raw -Slug ""
        $title   = Get-Title $indexFile
    }

    $children = Write-Tree -BasePath $BasePath -ParentSlug ""

    return [PSCustomObject]@{
        IndexFile = $indexFile
        Title     = $title
        Content   = $Content
        Slug      = ""
        Children  = $children
    }
}

function Write-Tree {
<#
.SYNOPSIS
    Recursively traverses a directory and builds a flat list of page nodes.

.DESCRIPTION
    Iterates over every entry in BasePath. Directories become group nodes
    whose slug is derived from their index file title (or folder name when
    no index file exists). Markdown files become leaf nodes. Each node
    carries its slug, title, content sections (from Split-MarkdownSections),
    and optional children. Duplicate slugs cause the build to abort.

.PARAMETER BasePath
    Directory to scan for Markdown files and sub-folders.

.PARAMETER ParentSlug
    Slug of the parent node, prepended to child slugs to form full paths.
#>
    param (
        [Parameter(Mandatory)]
        [string]$BasePath,
        [string]$ParentSlug = ""
    )

    $invalidChars  = "[\(\)\[\]\{\}#?%&]"
    $IndexFileName = $buildConf.tableOfContents.name?.Trim() ?? "index.md"

    $items   = New-Object System.Collections.Generic.List[object]
    $entries = Get-ChildItem -LiteralPath $BasePath -Force |
        Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name

    foreach ($entry in $entries) {

        if (-not $entry.PSIsContainer -and $entry.Extension -ne '.md') {
            continue
        }

        if ($entry.PSIsContainer) {

            if ($entry.Name -match $invalidChars) {
                Write-Warning "Folder '$($entry.FullName)' contains special characters that may cause URL problems."
            }

            $Content       = @()
            $indexFileName = $buildConf.tableOfContents.name?.Trim() ?? "index.md"
            $indexFile     = Join-Path $entry.FullName $indexFileName

            if (Test-Path $indexFile) {
                $title = Get-Title $indexFile

                if ([string]::IsNullOrWhiteSpace($title.ToString())) {
                    $title = $entry.Name
                }

                $localSlug = Get-Slug $title

                $slug    = if ($ParentSlug) { "$ParentSlug/$localSlug" } else { $localSlug }
                $raw     = Get-Content $indexFile -Raw
                $Content = Split-MarkdownSections -Markdown $raw -Slug $slug
            }
            else {
                $title     = $entry.Name
                $localSlug = Get-Slug $title
                $slug      = if ($ParentSlug) { "$ParentSlug/$localSlug" } else { $localSlug }
            }

            if ($global:UsedSlugs.ContainsKey($slug)) {
                Write-Error "Duplicate slug detected: '$slug' (File/Folder: $($entry.FullName))"
                Read-Host -Prompt "Press Enter to continue"
                exit
            }

            $children = Write-Tree -BasePath $entry.FullName -ParentSlug $slug

            if ($children.Count -eq 0 -and -not (Test-Path $indexFile)) {
                continue
            }

            $items.Add([PSCustomObject]@{
                IndexFile = $indexFile
                Title     = $title
                Content   = $Content
                Slug      = $slug
                Children  = $children
            })
        }
        elseif ($entry.Extension -eq '.md') {

            $raw   = Get-Content $entry.FullName -Raw
            $title = Get-Title $entry.FullName

            $localSlug = Get-Slug $title
            $slug      = if ($ParentSlug) { "$ParentSlug/$localSlug" } else { $localSlug }

            if ($global:UsedSlugs.ContainsKey($slug)) {
                Write-Error "Duplicate slug detected: '$slug' (File/Folder: $($entry.FullName))"
                Read-Host -Prompt "Press Enter to continue"
                exit
            }

            $Content = Split-MarkdownSections -Markdown $raw -Slug $slug

            $items.Add([PSCustomObject]@{
                File    = $entry.FullName
                Title   = $title
                Content = $Content
                Slug    = $slug
            })
        }
    }

    return $items
}

function Get-UniqueAnchor {
<#
.SYNOPSIS
    Returns a deduplicated anchor ID for a heading.

.DESCRIPTION
    If BaseAnchor has not been seen before it is returned as-is and
    registered in UsedAnchors. On subsequent calls for the same base value
    a numeric suffix (-1, -2, …) is appended so that every anchor in a
    document is unique. The UsedAnchors hashtable is mutated in place.

.PARAMETER BaseAnchor
    The raw (already-slugified) anchor string derived from a heading.

.PARAMETER UsedAnchors
    Hashtable that tracks how many times each base anchor has appeared.
#>
    param(
        [string]$BaseAnchor,
        [hashtable]$UsedAnchors
    )

    if ($UsedAnchors.ContainsKey($BaseAnchor)) {
        $UsedAnchors[$BaseAnchor]++
        return "$BaseAnchor-$($UsedAnchors[$BaseAnchor])"
    }
    else {
        $UsedAnchors[$BaseAnchor] = 0
        return $BaseAnchor
    }
}

function Split-MarkdownSections {
<#
.SYNOPSIS
    Splits a Markdown document into per-heading sections.

.DESCRIPTION
    Walks through the document line by line, tracking code-fence state to
    avoid treating headings inside code blocks as section delimiters.
    Each heading starts a new section; the content accumulated since the
    previous heading is cleaned (via Get-CleanMarkdownContent) and stored.
    Returns an array of PSCustomObjects with Id, Level, Slug, Anchor, Href,
    Headline, and Content properties used later for search indexing and
    navigation.

.PARAMETER Markdown
    The raw Markdown text of the file.

.PARAMETER Slug
    The page-level slug that prefixes in-page anchor hrefs.
#>
    param(
        [Parameter(Mandatory)]
        [string]$Markdown,
        [Parameter(Mandatory)]
        $Slug
    )

    $sections     = @()
    $usedAnchors  = @{}

    $currentHeader = $null
    $currentLevel  = $null

    $buffer = New-Object System.Text.StringBuilder
    $id     = 0

    $lines     = $Markdown -split "`r?`n"
    $codeBlock = $false

    foreach ($line in $lines) {

        if ($line -match '^```') {
            $codeBlock = -not $codeBlock
        }

        if (-not $codeBlock -and $line -match '^(#{1,6})\s+(.*)') {

            if ($currentHeader) {
                $baseAnchor = Get-Slug $currentHeader
                $anchor     = Get-UniqueAnchor -BaseAnchor $baseAnchor -UsedAnchors $usedAnchors
                $href       = if ($id -eq 1) { $Slug } else { "$($Slug)::$($anchor)" }

                $sections += [PSCustomObject]@{
                    Id       = $id
                    Level    = $currentLevel
                    Slug     = $Slug
                    Anchor   = $anchor
                    Href     = $href
                    Headline = $currentHeader
                    Content  = Get-CleanMarkdownContent -Content $($buffer.ToString().Trim())
                }
                $buffer.Clear() | Out-Null
            }

            $currentLevel  = $matches[1].Length
            $currentHeader = $matches[2].Trim()
            $id++
        }

        $buffer.AppendLine($line) | Out-Null
    }

    # Flush last section
    if ($currentHeader) {
        $baseAnchor = Get-Slug $currentHeader
        $anchor     = Get-UniqueAnchor -BaseAnchor $baseAnchor -UsedAnchors $usedAnchors
        $href       = if ($id -eq 1) { $Slug } else { "$($Slug)::$($anchor)" }

        $sections += [PSCustomObject]@{
            Id       = $id
            Level    = $currentLevel
            Slug     = $Slug
            Anchor   = $anchor
            Href     = $href
            Headline = $currentHeader
            Content  = Get-CleanMarkdownContent -content $($buffer.ToString().Trim())
        }
    }

    return $sections
}

function Build-Navigation {
<#
.SYNOPSIS
    Converts the page tree into a flat navigation list.

.DESCRIPTION
    Recursively flattens the tree returned by Build-Tree into an ordered
    array of navigation entries. Each entry contains the page title, href
    slug, nesting level, source file path, and a pre-rendered HTML snippet
    for the sidebar. File paths are made relative to the src directory and
    backslashes are normalised to forward slashes.

.PARAMETER nodes
    Array of tree nodes (from Build-Tree / Write-Tree).

.PARAMETER currentLevel
    Nesting depth of the current call; used to calculate absolute nav levels.
#>
    param(
        [Parameter(Mandatory)]
        $nodes,
        $currentLevel = 0
    )

    $result = @()
    foreach ($n in $nodes) 
    {
        if ($n.content) {
            foreach ($c in $n.Content) {
                $level = ($c.Level) + $currentLevel

                $result += [PSCustomObject]@{
                    title = $c.Headline
                    href  = $c.Href
                    level = $level
                    file  = $n.File -replace [regex]::Escape("$scriptRoot\src\"), ''
                    html  = ('<div class="nav-item" data-href="{0}" data-level="{1}" data-file="{2}">{3}</div>' -f $c.Href, $level, (($n.File -replace [regex]::Escape("$scriptRoot\src\"), '') -replace '\\', '/'), $c.Headline)
                }
            }
        }
        elseif ($n.children) {
            $level = $currentLevel + 1

                $result += [PSCustomObject]@{
                    title = $n.title
                    href  = $n.slug
                    level = $level
                    file  = $n.IndexFile -replace [regex]::Escape("$scriptRoot\src\"), ''
                    html = ('<div class="nav-item" data-href="{0}" data-level="{1}" data-file="{2}">{3}</div>' -f $n.slug, $level, (($n.IndexFile -replace [regex]::Escape("$scriptRoot\src\"), '') -replace '\\', '/'), $n.title)
                }
            $result += Build-Navigation $n.children -currentLevel $level
        }
    }

    return $result
}

function Build-TableOfContents {
<#
.SYNOPSIS
    Generates a Markdown table-of-contents block for a page.

.DESCRIPTION
    Starting from the entry at StartIndex, collects all subsequent entries
    whose level is deeper than the anchor entry (up to the configured depth
    limit) and formats them as an indented Markdown link list prefixed with
    the ::DA:TOC directive. The result is written back to the index file
    so it can be processed by the normal Markdown converter.

.PARAMETER Entries
    The flat navigation list produced by Build-Navigation.

.PARAMETER StartIndex
    Index of the TableOfContent placeholder entry within Entries.
#>
    param(
        [array]$Entries,
        [int]$StartIndex
    )

    $Depth = $buildConf.tableOfContents.depth ?? 2

    $result    = @()
    $result   += "::DA:TOC"
    $headline  = $buildConf.tableOfContents.Headline
    $result   += "# $($headline.Trim())`n"
    $result   += "`n"

    $baseLevel = $Entries[$StartIndex].level

    for ($i = $StartIndex + 1; $i -lt $Entries.Count; $i++) {

        $entry = $Entries[$i]

        if ($entry.level -le $baseLevel) { break }

        $relLevel = $entry.level - $baseLevel

        if ($relLevel -gt $Depth) { continue }

        $indent  = "  " * ($relLevel - 1)
        $result += "$indent- [$($entry.title)](#$($entry.href))"
    }

    return $result
}

function Build-SearchIndex {
<#
.SYNOPSIS
    Builds a flat search index from the documentation tree.

.DESCRIPTION
    Recursively walks the tree and collects one entry per heading section.
    Leaf page entries carry the cleaned plain-text content of each section;
    folder group entries carry an empty text field. The resulting array is
    serialised to JSON and consumed by MiniSearch in the browser.

.PARAMETER nodes
    Array of tree nodes (from Build-Tree / Write-Tree).
#>
    param(
        [Parameter(Mandatory)]
        $nodes
    )

    $result = @()

    foreach ($n in $nodes) {
        if ($n.content) {

            foreach ($c in $n.Content) {
                $result += [PSCustomObject]@{
                    title = $c.Headline
                    href  = $c.Href
                    text  = $c.Content
                }
            }
        }
        elseif ($n.children) {
            $result += [PSCustomObject]@{
                title = $n.title
                href  = $n.slug
                text  = ""
            }
            $result += Build-SearchIndex $n.children
        }
    }

    return $result
}

function Publish-MarkdownFiles {
<#
.SYNOPSIS
    Converts Markdown source files to HTML in the build directory.

.DESCRIPTION
    Mirrors the directory structure from Source into Destination.
    Each .md file is converted to HTML via Convert-DocAtlasMarkDown;
    all other files (images, attachments, etc.) are copied as-is.
    Output files always use the .html extension, even when the source
    is not a Markdown file.

.PARAMETER Source
    Root of the Markdown source tree (single file or directory).

.PARAMETER Destination
    Root of the output directory where HTML files are written.
#>
    param (
        [string]$Source,
        [string]$Destination
    )

    if (!(Test-Path $Destination)) {
        New-Item -ItemType Directory -Path $Destination | Out-Null
    }

    Get-ChildItem $Source -Recurse | ForEach-Object {

        $relative = $_.FullName.Substring($Source.Length)
        if ([string]::IsNullOrWhiteSpace($relative)) {
            $relative = $_.Name
        }

        $target    = Join-Path $Destination $relative
        $target    = [System.IO.Path]::ChangeExtension($target, ".html")
        $targetDir = Split-Path $target

        if (!(Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir | Out-Null
        }

        # Skip directories
        if ($_.PSIsContainer) { return }

        if ($_.Extension -eq ".md") {
            # Convert Markdown to HTML
            Convert-DocAtlasMarkDown -InputFile $_.FullName -OutputFile $target
        }
        else {
            # Copy all other files as-is (images, etc.)
            Copy-Item $_.FullName -Destination $target -Force
        }
    }
}


function Convert-DocAtlasMarkDown {
<#
.SYNOPSIS
    Converts a single DocAtlas-flavoured Markdown file to an HTML fragment.

.DESCRIPTION
    Implements a custom line-by-line Markdown parser that handles headings,
    fenced code blocks, tables, blockquotes, ordered and unordered lists
    (including checkboxes and custom markers), DocAtlas info/warning/alert
    boxes (::da:<type> … ::da:end), inline formatting (bold, italic,
    strikethrough, links, images), and escape sequences. The output is a
    bare HTML fragment (no <html>/<body> wrapper) written to OutputFile in
    UTF-8 encoding.

.PARAMETER InputFile
    Path to the source .md file.

.PARAMETER OutputFile
    Path where the resulting .html fragment will be written.
#>
    param (
        [string]$InputFile,
        [string]$OutputFile
    )

    # ==============================
    # CONFIG
    # ==============================

    $daTypes = @{
        'alert'     = @{ class = "md-alert-box";     icon = "🚨" }
        'important' = @{ class = "md-important-box"; icon = "❕" }
        'warning'   = @{ class = "md-warning-box";   icon = "⚠️" }
        'question'  = @{ class = "md-question-box";  icon = "❔" }
        'tip'       = @{ class = "md-tip-box";       icon = "💡" }
        'info'      = @{ class = "md-info-box";      icon = "📖" }
        'danger'    = @{ class = "md-danger-box";    icon = "⛔" }
        'success'   = @{ class = "md-success-box";   icon = "✅" }
        'note'      = @{ class = "md-note-box";      icon = "📝" }
        'example'   = @{ class = "md-example-box";   icon = "📦" }
    }

    <#$mdPatterns = [ordered]@{
        '^###### (.+)' = { "<h6>$($matches[1])</h6>" }
        '^##### (.+)'  = { "<h5>$($matches[1])</h5>" }
        '^#### (.+)'   = { "<h4>$($matches[1])</h4>" }
        '^### (.+)'    = { "<h3>$($matches[1])</h3>" }
        '^## (.+)'     = { "<h2>$($matches[1])</h2>" }
        '^# (.+)'      = { "<h1>$($matches[1])</h1>" }
    }#>
    # The $mdPatterns hashtable is kept for the dispatch loop; actual HTML is built in Apply-Heading.
    $mdPatterns = [ordered]@{
        '^###### (.+)' = 6
        '^##### (.+)'  = 5
        '^#### (.+)'   = 4
        '^### (.+)'    = 3
        '^## (.+)'     = 2
        '^# (.+)'      = 1
    }

    $escapeChars = @{
        '\*' = '*'
        '\_' = '_'
        '\#' = '#'
        '\[' = '['
        '\]' = ']'
        '\(' = '('
        '\)' = ')'
        '\`' = '`'
        '\\' = '\'
        '\>' = '>'
        '\-' = '-'
        '\+' = '+'
        '\.' = '.'
        '\!' = '!'
    }

    # Escapes the three characters that would break raw text inside HTML.
    function Escape-Html([string]$text) {
        return $text.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;")
    }

    # Order matters!
    $inlinePatterns = [ordered]@{
        '!\[(.*?)\]\((.*?)\)' = '<img src="$2" alt="$1">'
        '\[(.*?)\]\((.*?)\)'  = '<a href="$2">$1</a>'

        '<(https?://[^\s>]+)>' = '<a href="$1">$1</a>'
        '<([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})>' = '<a href="mailto:$1">$1</a>'

        '(?<!\*|_)(\*\*\*|___)(.+?)\1(?!\*|_)' = '<strong><em>$2</em></strong>'
        '(?<!\*|_)(\*\*|__)(.+?)\1(?!\*|_)'    = '<strong>$2</strong>'
        '(?<!\*|_)(\*|_)(.+?)\1(?!\*|_)'       = '<em>$2</em>'
        '(?<!~)~~(.+?)~~(?!~)'                 = '<del>$1</del>'

        '␣␣' = '<br>'

        '^\s{0,3}([-]{3}[_])\s*$' = '<hr class="hr-dashed">'
        '^\s{0,3}([-]{3}[*])\s*$' = '<hr class="hr-symbol">'
        '^\s{0,3}([-]{3}[.])\s*$' = '<hr class="hr-dotted">'
        '^\s{0,3}([-]{3})\s*$'    = '<hr class="hr-thin">'
    }

    # ==============================
    # STATE
    # ==============================

    $TOCLIST = $false

    # Tracks used heading anchors within this file to avoid duplicates
    $usedHeadingAnchors = @{}

    $lines  = Get-Content $InputFile -Encoding UTF8
    $output = New-Object System.Collections.Generic.List[string]

    $inCodeBlock = $false
    $codeLang    = ""
    $codeFence   = 0

    $inList    = $false
    $listStack = New-Object System.Collections.Stack

    $inQuote    = $false
    $quoteStack = New-Object System.Collections.Stack

    $inBaseBox   = $false
    $currentType = $null
    $boxBuffer   = New-Object System.Collections.Generic.List[string]

    $inTable      = $false
    $tableBuffer  = New-Object System.Collections.Generic.List[string]
    $tableHeader  = $null

    $paragraphBuffer = New-Object System.Collections.Generic.List[string]

    # Applies all inline Markdown transformations to a single line of text:
    # escaped characters, inline code, links, images, bold/italic/strikethrough, and custom HR variants.
    # Returns the transformed HTML string.
    function Apply-Inline($rowLine) {
        $line = $rowLine

        # 1. Escaped characters -- replace with placeholders to protect from further processing
        $escapeMap = @{}
        $j = 0
        foreach ($escaped in $escapeChars.Keys) {
            $escapedRegex = [regex]::Escape($escaped)
            if ($line -match $escapedRegex) {
                $key             = "%%ESC$j%%"
                $escapeMap[$key] = $escapeChars[$escaped]
                $line            = $line -replace $escapedRegex, [regex]::Escape($key)
                $j++
            }
        }

        # 2. Inline code -- protect from inline pattern substitutions
        $codeMap = @{}
        $i       = 0
        $line    = [regex]::Replace($line, '\`(.*?)\`', {
            param($m)
            $key          = "%%CODE$i%%"
            $codeMap[$key] = "<code>$(Escape-Html $m.Groups[1].Value)</code>"
            $i++
            return $key
        })

        # 3. Apply inline patterns (links, bold, italic, etc.)
        foreach ($p in $inlinePatterns.Keys) {
            $line = $line -replace $p, $inlinePatterns[$p]
        }

        # 4. Restore inline-code placeholders
        foreach ($k in $codeMap.Keys) {
            $line = $line.Replace($k, $codeMap[$k])
        }

        # 5. Restore escape placeholders
        foreach ($k in $escapeMap.Keys) {
            $line = $line.Replace($k, $escapeMap[$k])
        }

        return $line
    }

    # Renders a heading as an HTML <hN> element with an id attribute whose value
    # is guaranteed to match the href produced by Split-MarkdownSections.
    # Uses the same Get-Slug + Get-UniqueAnchor logic as Split-MarkdownSections
    # so that anchor IDs in the HTML always match the href values in the search/nav index.
    function Apply-Heading {
        param(
            [int]   $Level,
            [string]$Text
        )

        $baseAnchor = Get-Slug $Text
        $anchor     = Get-UniqueAnchor -BaseAnchor $baseAnchor -UsedAnchors $usedHeadingAnchors
        $innerHtml  = Apply-Inline $Text

        return "<h$Level id=`"$anchor`">$innerHtml</h$Level>"
    }

    # Appends a line to the active output target: the box buffer when inside
    # a ::da: box, or the main output list otherwise.
    function Add-Line {
        param($line)

        if ($inBaseBox) {
            $boxBuffer.Add($line)
        }
        else {
            $output.Add($line)
        }
    }

    # Wraps accumulated paragraph lines in a <p> tag and emits them, then clears
    # the buffer. HR lines that were collected into the buffer are emitted unwrapped.
    function Flush-Paragraph {

        if ($paragraphBuffer.Count -eq 0) { return }

        $joined = ($paragraphBuffer -join " ")

        if ($joined -match "<hr class=.+") {
            Add-Line $joined
            $paragraphBuffer.Clear()
            return
        }
		
#$joined = ($paragraphBuffer -join " ")
        Add-Line "<p>$joined</p>"
        $paragraphBuffer.Clear()
    }

    # Maps a list marker character (-, *, +, ->, etc.) to its CSS class name.
    function Get-ListClass($marker) {
        switch ($marker) {
            '-'  { return "list-dash" }
            '->' { return "list-arrow-right" }
            '<-' { return "list-arrow-left" }
            '*'  { return "list-star" }
            '°'  { return "list-circle" }
            '~'  { return "list-tilde" }
            '+'  { return "list-plus" }
            '<3' { return "list-heart" }
            '<X' { return "list-cross" }
            '<C' { return "list-check" }
            default { return "list-dash" }
        }
    }

    # Renders the buffered table rows as a complete <table> element and appends
    # it to the output. Clears all table state afterwards.
    function Flush-Table {

        if (-not $inTable -or $tableBuffer.Count -eq 0) { return }

        $output.Add("<table>")

        if ($tableHeader) {
            $output.Add("<thead><tr>")

            for ($i = 0; $i -lt $tableHeader.Count; $i++) {
                $align = if ($tableAlign.Count -gt $i) { $tableAlign[$i] } else { "left" }
                $class = "class=`"td-align-$align`""
                $output.Add("<th $class>$(Apply-Inline $tableHeader[$i])</th>")
            }

            $output.Add("</tr></thead>")
        }

        $output.Add("<tbody>")

        foreach ($row in $tableBuffer) {
            $cells = $row -split "\s*\|\s*"
            $cells = $cells | Where-Object { $_ -ne "" }

            $output.Add("<tr>")

            for ($i = 0; $i -lt $cells.Count; $i++) {
                $align = if ($tableAlign.Count -gt $i) { $tableAlign[$i] } else { "left" }
                $class = "class=`"td-align-$align`""
                $output.Add("<td $class>$(Apply-Inline $cells[$i])</td>")
            }

            $output.Add("</tr>")
        }

        $output.Add("</tbody></table>")

        $tableBuffer.Clear()
        $tableHeader = $null
        $inTable     = $false
    }

    foreach ($line in $lines) {

        if ($line -match "::DA:TOC") {
            $TOCLIST = $true
            continue
        }

        # ==========================
        # Code block
        # ==========================
        if ($line -match '^(`{3,})\s*([\w-]+)?\s*$') {

            Flush-Paragraph
            $fence = $matches[1]
            $lang  = $matches[2]

            if (-not $inCodeBlock) {
                $inCodeBlock = $true
                $codeFence   = $fence.Length
                $codeLang    = $lang

                if ($codeLang) {
                    Add-Line "<pre><code class=`"language-$codeLang`">"
                }
                else {
                    Add-Line "<pre><code>"
                }
            }
            else {
                if ($fence.Length -ge $codeFence) {
                    $inCodeBlock = $false
                    $codeFence   = 0
                    Add-Line "</code></pre>"
                }
                else {
                    Add-Line (Escape-Html $line)
                }
            }

            continue
        }

        if ($inCodeBlock) {
            Add-Line (Escape-Html $line)
            continue
        }

        # ==========================
        # Table detection
        # ==========================

        if ($line -match '^\s*\|(.+)\|\s*$') {

            Flush-Paragraph

            $cells = $matches[1].Split('|') | ForEach-Object { $_.Trim() }

            # Detect separator row: |---|---|
            if ($inTable -and $cells -match '^[:]{0,1}-{3,}[:]{0,1}$') {

                $tableAlign = @()

                foreach ($cell in $cells) {
                    $c = $cell.Trim()
                    if ($c -match '^:-{3,}:$')  { $tableAlign += "center" }
                    elseif ($c -match '^-{3,}:$') { $tableAlign += "right"  }
                    else                          { $tableAlign += "left"   }
                }

                continue
            }

            if (-not $inTable) {
                $inTable     = $true
                $tableHeader = $cells
                continue
            }

            $tableBuffer.Add($cells -join "|")
            continue
        }
        else {
            if ($inTable) {
                Flush-Table
                $inTable = $false
            }
        }

        # ==========================
        # Blockquote
        # ==========================

        if ($line -match '^\s*(>{1,6})(.*)$') {

            $level = $matches[1].Length
            $line  = $matches[2]

            if (-not $inQuote) {
                Flush-Paragraph
                $inQuote = $true
            }

            $current = $quoteStack.Count

            # Close deeper levels
            while ($current -gt $level) {
                Flush-Paragraph
                Add-Line "</blockquote>"
                $quoteStack.Pop() | Out-Null
                $current--
            }

            # Open deeper levels
            while ($current -lt $level) {
                Add-Line "<blockquote>"
                $quoteStack.Push($true)
                $current++
            }
        }
        else {
            if ($inQuote) {
                Flush-Paragraph

                while ($quoteStack.Count -gt 0) {
                    Add-Line "</blockquote>"
                    $quoteStack.Pop() | Out-Null
                }

                $inQuote = $false
            }
        }

        # ==========================
        # Custom DocAtlas box
        # ==========================

        if (-not $inCodeBlock -and -not $inBaseBox -and $line -match '^::da:(\w+)(?:\s+(.*))?$') {

            $inBaseBox = $true
            Flush-Paragraph

            $type  = $matches[1]
            $title = $matches[2]

            if ($daTypes.ContainsKey($type)) {
                $inBaseBox   = $true
                $currentType = $type
                $boxBuffer.Clear()

                if ($title) {
                    $title = Apply-Inline $title
                    $boxBuffer.Add("<div class=`"md-box-title`">$($daTypes[$type].icon) $title</div>")
                }
            }

            continue
        }

        if (-not $inCodeBlock -and $line -match '^::da:end$') {

            Flush-Paragraph

            if ($inBaseBox -and $currentType) {
                $meta = $daTypes[$currentType]

                $output.Add("<div class=`"md-box $($meta.class)`">")
                $output.Add("<div class=`"md-box-content`">")

                foreach ($l in $boxBuffer) { $output.Add($l) }

                $output.Add("</div></div>")

                $inBaseBox   = $false
                $currentType = $null
                $boxBuffer.Clear()
            }

            continue
        }

        # ==========================
        # List
        # ==========================

        if ($line -match '^(\s*)([-*+~°]|->|<-|<3|<X|<C|[0-9]\.)\s+(.*)') {

            Flush-Paragraph

            $indent  = $matches[1].Length
            $marker  = $matches[2]
            $content = $matches[3]

            # Checkbox -- handle before Apply-Inline
            if ($content -match '^\[(x| )\]\s+(.*)$') {
                $checked = if ($matches[1] -eq 'x') { ' checked=""' } else { '' }
                $class   = if ($matches[1] -eq 'x') { 'list-checkbox-done' } else { 'list-checkbox' }
                $inner   = Apply-Inline $matches[2]

                if (-not $inList) {
                    Add-Line "<ul>"
                    $listStack.Push($indent)
                    $inList = $true
                }

                Add-Line "<li class=`"$class`"><input disabled=`"`" type=`"checkbox`"$checked> $inner</li>"
                continue
            }

            $content = Apply-Inline $content

            if ($marker -match "[0-9]\.") {
                $tagOpen  = "<ol>"
                $tagClose = "</ol>"
                $class    = "list-num"
            }
            else {
                if ($TOCLIST) {
                    $tagOpen  = "<ul class=""da-toc-list"">"
                    $TOCLIST  = $false
                }
                else {
                    $tagOpen = "<ul>"
                }
                $tagClose = "</ul>"
                $class    = Get-ListClass $marker
            }

            if (-not $inList) {
                Add-Line $tagOpen
                $listStack.Push($indent)
                $inList = $true
            }

            while ($listStack.Count -gt 0 -and $indent -lt $listStack.Peek()) {
                Add-Line $tagClose
                $listStack.Pop() | Out-Null
            }

            if ($listStack.Count -eq 0 -or $indent -gt $listStack.Peek()) {
                Add-Line $tagOpen
                $listStack.Push($indent)
            }

            Add-Line "<li class=`"$class`">$content</li>"
            continue
        }
        else {
            if ($inList) {
                while ($listStack.Count -gt 0) {
                    Add-Line $tagClose
                    $listStack.Pop() | Out-Null
                }
                $inList = $false
            }
        }

        # ==========================
        # Headings (H1-H6)
        # ==========================
        $handled = $false

        foreach ($pattern in $mdPatterns.Keys) {
            if ($line -match $pattern) {
                Flush-Paragraph

                $level   = $mdPatterns[$pattern]       # value is now the heading level (int)
                $text    = $matches[1]
                $html    = Apply-Heading -Level $level -Text $text
                Add-Line $html

                $handled = $true
                break
            }
        }

        if ($handled) { continue }

        if ($line.Trim() -eq "") {
            Flush-Paragraph
            continue
        }

        $paragraphBuffer.Add((Apply-Inline $line))
    }

    Flush-Paragraph
    Flush-Table

    if ($inList) {
        while ($listStack.Count -gt 0) {
            Add-Line $tagClose
            $listStack.Pop() | Out-Null
        }
    }

    # Close any unclosed box
    if ($inBaseBox -and $currentType) {
        $meta = $daTypes[$currentType]

        $output.Add("<div class=`"md-box $($meta.class)`">")
        $output.Add("<div class=`"md-box-content`">")

        foreach ($l in $boxBuffer) { $output.Add($l) }

        $output.Add("</div></div>")
    }

    Set-Content $OutputFile $output -Encoding UTF8
}

# --------------------------------------------------
# Prepare build environment
# --------------------------------------------------
Write-Host "Preparing build environment..." -ForegroundColor Cyan

# Save the script directory as root for all relative paths
$scriptRoot = $PSScriptRoot

# If no INI file was passed, fall back to build.ini next to the script
if (-not $PSBoundParameters.ContainsKey("ini")) {
    $ini = Join-Path $scriptRoot "build.ini"
}

# Parse the INI file
$ParseConf = Read-IniFile -Path $ini
if ($ParseConf.debug.enabled) {
    Write-Host "Debug mode is enabled. Preparing debug configuration..." -ForegroundColor Red
}
$ParseConf = Set-DebugConfig -config $ParseConf -SCRIPT_ROOT $scriptRoot
$buildConf = $ParseConf | Optimize-ConfigValues

# Source and build paths
$src   = Join-Path $scriptRoot "src"
$build = Join-Path $scriptRoot "html"

# Output file paths
$outAppConfig   = Join-Path $build "app.json"
$outHtml          = Join-Path $build $buildConf.environment.htmlSrcFolder
$outSearchIndex = Join-Path $build $buildConf.environment.searchIndex
$outDebug       = $buildConf.debug.outPath
$outIndexHTML   = Join-Path $build "index.html"

# Clean up the build directory
Write-Host "Cleaning up build directory..." -ForegroundColor Cyan
Remove-Item $outHtml        -Recurse -Force -ErrorAction Ignore | Out-Null
Remove-Item $outDebug       -Recurse -Force -ErrorAction Ignore | Out-Null
Remove-Item $outAppConfig   -Force   -ErrorAction Ignore | Out-Null
Remove-Item $outSearchIndex -Force   -ErrorAction Ignore | Out-Null
Remove-Item $outIndexHTML   -Force   -ErrorAction Ignore | Out-Null

New-Item -ItemType Directory -Path $outHtml | Out-Null

if ($buildConf.debug.enabled) {
    Write-Host "[Debug] Creating debug output directory..." -ForegroundColor Gray
    Write-Host "$("   " * 2)'$outDebug'" -ForegroundColor DarkMagenta
    New-Item -ItemType Directory -Path $outDebug | Out-Null
}

# --------------------------------------------------
# Scan source and build tree structure
# --------------------------------------------------
Write-Host "Scanning source directory and building tree structure..." -ForegroundColor Cyan
$tree = Build-Tree -BasePath $src

if ($buildConf.debug.enabled) {
    Write-Host "[Debug]  $("   " * 1) Writing tree structure to JSON..." -ForegroundColor Gray
    $tree | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $outDebug $buildConf.debug.tree_default) -Encoding UTF8
    Write-Host "[Debug] $("   " * 2) Build tree structure complete." -ForegroundColor DarkGreen
}

if ($null -eq $tree) {
    Write-Error "No valid Markdown files found in the source directory. Build aborted."
    Read-Host -Prompt "Press Enter to exit"
    exit
}

# --------------------------------------------------
# Copy source files to build directory
# --------------------------------------------------
Write-Host "Copying source files to build directory..." -ForegroundColor Cyan
Publish-MarkdownFiles -Source $src -Destination $outHtml

if ($buildConf.debug.enabled) {
    Write-Host "[Debug]  $("   " * 1) Source files copied to" -ForegroundColor Gray
    Write-Host "$("   " * 2) '$outHtml'" -ForegroundColor DarkMagenta
}

# --------------------------------------------------
# Write navigation structure
# --------------------------------------------------
Write-Host "Writing navigation structure to JSON..." -ForegroundColor Cyan
$nav = ,@(Build-Navigation $tree)

if ($buildConf.debug.enabled) {
    Write-Host "[Debug] $("   " * 1) Writing debug navigation structure to JSON..." -ForegroundColor Gray
    $nav | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $outDebug $buildConf.debug.navigation) -Encoding UTF8
    Write-Host "[Debug] $("   " * 2) Debug navigation structure complete." -ForegroundColor Gray
}


if ($buildConf.debug.enabled) {
    Write-Host "[Debug] $("   " * 1) Navigation files generated." -ForegroundColor DarkGreen
}

# --------------------------------------------------
# Generate Table of Contents files
# --------------------------------------------------
if ($buildConf.tableOfContents.enabled) {
    Write-Host "Generating table of contents files..." -ForegroundColor Cyan
    $tocCollection = $nav[0]

    for ($i = 0; $i -lt $tocCollection.Count; $i++) {

        if ($tocCollection[$i].file -like "*TableOfContent.html") {

            $indexhtml      = Join-Path $outHtml $tocCollection[$i].file
            $indexPlacement = $indexhtml | Split-Path
            $indexmd        = [System.IO.Path]::ChangeExtension($indexhtml, ".md")

            if ($buildConf.debug.enabled) {
                Write-Host "[Debug] $("   " * 1) Writing table of contents:" -ForegroundColor Gray
                Write-Host "$("   " * 2) '$indexmd'" -ForegroundColor DarkMagenta
            }

            Build-TableOfContents -Entries $tocCollection -StartIndex $i |
                Set-Content $indexmd -Encoding UTF8

            if ($buildConf.debug.enabled) {
                Write-Host "[Debug] $("   " * 1) Publishing table of contents:" -ForegroundColor DarkGreen
                Write-Host "$("   " * 2) '$indexhtml'" -ForegroundColor DarkMagenta
            }

            Publish-MarkdownFiles -Source $indexmd -Destination $indexPlacement

            if ($buildConf.debug.enabled) {
                Write-Host "[Debug] $("   " * 1) Table of contents generated." -ForegroundColor DarkGreen
            }
        }
    }

    if ($buildConf.debug.enabled) {
        Write-Host "[Debug] Table of contents files generated." -ForegroundColor DarkGreen
    }
}

# --------------------------------------------------
# Write search index
# --------------------------------------------------
Write-Host "Writing search index to JSON..." -ForegroundColor Cyan
$searchIndex = ,@(Build-SearchIndex $tree)

if ($buildConf.debug.enabled) {
    Write-Host "[Debug] $("   " * 1) Writing debug search index to JSON..." -ForegroundColor Gray
    $searchIndex | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $outDebug $buildConf.debug.globalSearchIndex) -Encoding UTF8
    Write-Host "[Debug] $("   " * 2) Debug search index complete." -ForegroundColor Gray
}

$searchIndex |
    ConvertTo-Json -Depth 5 |
    Set-Content $outSearchIndex -Encoding UTF8

if ($buildConf.debug.enabled) {
    Write-Host "[Debug] $("   " * 1) Search index files generated." -ForegroundColor DarkGreen
}

# --------------------------------------------------
# Write application configuration
# --------------------------------------------------
Write-Host "Writing application configuration to JSON..." -ForegroundColor Cyan
$appConfig = @{}

# Copy every config section except 'debug' -- the browser should never see debug settings.
foreach ($prop in $buildConf.PSObject.Properties) {
    if ($prop.Name -ne 'debug') {
        $appConfig[$prop.Name] = $prop.Value
    }
}

if ($buildConf.debug.enabled) {
    Write-Host "[Debug] $("   " * 1) Writing debug application configuration to JSON..." -ForegroundColor Gray
    $appConfig | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $outDebug $buildConf.debug.appConfig) -Encoding UTF8
    Write-Host "[Debug] $("   " * 2) Debug application configuration complete." -ForegroundColor Gray
}

# Double backslashes produced by ConvertTo-Json are normalised to forward slashes
# so that paths in app.json are valid URL components on all platforms.
($appConfig | ConvertTo-Json -Depth 5) -replace "\\\\", "/" |
    Set-Content $outAppConfig -Encoding UTF8

if ($buildConf.debug.enabled) {
    Write-Host "[Debug] $("   " * 1) Application configuration files generated." -ForegroundColor DarkGreen
}

# --------------------------------------------------
# Build index.html from template
# --------------------------------------------------
function Build-NavGroupedHtml {
<#
.SYNOPSIS
    Renders the flat navigation list as nested HTML for the sidebar.

.DESCRIPTION
    Walks the flat Items array starting at StartIdx, grouping consecutive
    items into collapsible nav-group/nav-children div structures whenever a
    deeper nesting level follows. Returns the generated HTML string and the
    index of the first item that was not consumed, allowing the caller to
    continue processing.

.PARAMETER Items
    The flat navigation list produced by Build-Navigation.

.PARAMETER StartIdx
    Index into Items at which to begin rendering.

.PARAMETER MinLevel
    Minimum nav level that belongs to the current nesting context; items
    shallower than this level cause the recursion to stop.
#>
    param([array]$Items, [int]$StartIdx, [int]$MinLevel)

    $sb  = [System.Text.StringBuilder]::new()
    $idx = $StartIdx

    while ($idx -lt $Items.Count -and $Items[$idx].level -ge $MinLevel) {
        $item       = $Items[$idx]
        $cssLevel   = $item.level - 1
        $nextDeeper = ($idx + 1 -lt $Items.Count) -and ($Items[$idx + 1].level -gt $item.level)

        if ($nextDeeper) {
            [void]$sb.AppendLine('<div class="nav-group">')
            [void]$sb.AppendLine("  <div class=`"nav-item nav-level-$cssLevel`" data-href=`"$($item.href)`" data-file=`"$($item.file)`">$($item.title)</div>")
            [void]$sb.AppendLine('  <div class="nav-children">')
            $child = Build-NavGroupedHtml $Items ($idx + 1) ($item.level + 1)
            [void]$sb.Append($child.Html)
            $idx = $child.NextIdx
            [void]$sb.AppendLine('  </div>')
            [void]$sb.AppendLine('</div>')
        } else {
            [void]$sb.AppendLine("  <div class=`"nav-item nav-level-$cssLevel`" data-href=`"$($item.href)`" data-file=`"$($item.file)`">$($item.title)</div>")
            $idx++
        }
    }

    return @{ Html = $sb.ToString(); NextIdx = $idx }
}

Write-Host "Building index.html from template..." -ForegroundColor Cyan
$tmplPath   = Join-Path $scriptRoot "res\index.html.tmpl"
$tmplContent = Get-Content $tmplPath -Raw -Encoding UTF8

$navItems = @($nav[0] | Where-Object { $_.level -gt 1 })
$navHtml  = (Build-NavGroupedHtml $navItems 0 2).Html
$tmplContent = $tmplContent -replace '<div id="da-navigation-div"></div>', "<div id=`"da-navigation-div`">`n`t`t`t`t$navHtml`n`t`t`t</div>"

Set-Content $outIndexHTML $tmplContent -Encoding UTF8

if ($buildConf.debug.enabled) {
    Write-Host "[Debug] $("   " * 1) index.html written to '$outIndexHTML'." -ForegroundColor DarkGreen
}

# --------------------------------------------------
# Build complete
# --------------------------------------------------
Write-Host "Build process completed successfully." -ForegroundColor Green

if (-not $buildConf.debug.enabled) {
    Start-Sleep -Seconds 5
}
exit