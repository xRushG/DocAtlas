<#
.SYNOPSIS
    DocAtlas Markdown parser module.

.DESCRIPTION
    Provides the Markdown-to-HTML pipeline used by the DocAtlas build system.
    Exports the main converter (Convert-DocAtlasMarkDown) together with the
    slug, anchor and media-name helpers that are shared with the rest of the
    build script.

    Exported functions
    ------------------
    Convert-DocAtlasMarkDown   – Converts a .md file to an HTML fragment.
    Get-Slug                   – Produces a URL-safe slug from a string.
    Get-UniqueAnchor           – Returns a deduplicated anchor ID for a heading.
    Get-SanitizedMediaName     – Returns a URL-safe path for a media asset.
    Get-MediaRegistry          – Returns the current media-path mapping table.
#>

Set-StrictMode -Version Latest

# ==============================================================================
# MODULE-LEVEL CONSTANTS
# Defined once at load time; read by parser helpers at runtime.
# ==============================================================================

$script:DaTypes = @{
    'alert'     = @{ class = 'md-alert-box';     icon = '🚨' }
    'important' = @{ class = 'md-important-box'; icon = '❕' }
    'warning'   = @{ class = 'md-warning-box';   icon = '⚠️' }
    'question'  = @{ class = 'md-question-box';  icon = '❔' }
    'tip'       = @{ class = 'md-tip-box';       icon = '💡' }
    'info'      = @{ class = 'md-info-box';      icon = '📖' }
    'danger'    = @{ class = 'md-danger-box';    icon = '⛔' }
    'success'   = @{ class = 'md-success-box';   icon = '✅' }
    'note'      = @{ class = 'md-note-box';      icon = '📝' }
    'example'   = @{ class = 'md-example-box';   icon = '📦' }
}

$script:MdPatterns = [ordered]@{
    '^###### (.+)' = 6
    '^##### (.+)'  = 5
    '^#### (.+)'   = 4
    '^### (.+)'    = 3
    '^## (.+)'     = 2
    '^# (.+)'      = 1
}

$script:EscapeChars = @{
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

$script:InlinePatterns = [ordered]@{
    '!\[(.*?)\]\((.*?)\)'                                                    = '<img src="$2" alt="$1">'
    '\[(.*?)\]\((.*?)\)'                                                     = '<a href="$2">$1</a>'
    '<(https?://[^\s>]+)>'                                                   = '<a href="$1">$1</a>'
    '<([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})>'                   = '<a href="mailto:$1">$1</a>'
    '(?<!\*|_)(\*\*\*|___)(.+?)\1(?!\*|_)'                                  = '<strong><em>$2</em></strong>'
    '(?<!\*|_)(\*\*|__)(.+?)\1(?!\*|_)'                                     = '<strong>$2</strong>'
    '(?<!\*|_)(\*|_)(.+?)\1(?!\*|_)'                                        = '<em>$2</em>'
    '(?<!~)~~(.+?)~~(?!~)'                                                   = '<del>$1</del>'
    '␣␣'                                                                     = '<br>'
    '^\s{0,3}([-]{3}[_])\s*$'                                               = '<hr class="hr-dashed">'
    '^\s{0,3}([-]{3}[*])\s*$'                                               = '<hr class="hr-symbol">'
    '^\s{0,3}([-]{3}[.])\s*$'                                               = '<hr class="hr-dotted">'
    '^\s{0,3}([-]{3})\s*$'                                                  = '<hr class="hr-thin">'
}

# ==============================================================================
# SHARED PARSER STATE
# Reset by Convert-DocAtlasMarkDown before each file; written/read by helpers.
# ==============================================================================

$script:MediaRegistry   = @{}
$script:Output          = $null
$script:InBaseBox       = $false
$script:BoxBuffer       = $null
$script:ParagraphBuffer = $null
$script:UsedAnchors     = $null
$script:InTable         = $false
$script:TableBuffer     = $null
$script:TableHeader     = $null
$script:TableAlign      = @()

# ==============================================================================
# PUBLIC: SLUG AND ANCHOR UTILITIES
# ==============================================================================

function Get-Slug {
<#
.SYNOPSIS
    Converts a string into a URL-friendly slug.

.DESCRIPTION
    Lowercases the input, replaces German umlauts with ASCII equivalents,
    strips special characters, and replaces whitespace with hyphens.

.PARAMETER Text
    The string to slugify.

.EXAMPLE
    Get-Slug "Über uns"
    # Returns: "ueber-uns"
#>
    param (
        [Parameter(Mandatory)]
        [string]$Text
    )

    $slug = $Text.ToLower()
    $slug = $slug -replace 'ä', 'ae'
    $slug = $slug -replace 'ö', 'oe'
    $slug = $slug -replace 'ü', 'ue'
    $slug = $slug -replace 'ß', 'ss'
    $slug = $slug -replace '\\', '/'
    $slug = $slug -replace '[^a-z0-9\s\-/]', ''
    $slug = $slug -replace '\s+', '-'

    return $slug.Trim('-')
}

function Get-UniqueAnchor {
<#
.SYNOPSIS
    Returns a deduplicated anchor ID for a heading.

.DESCRIPTION
    If BaseAnchor has not been seen before it is returned as-is and registered
    in UsedAnchors. On subsequent calls for the same base value a numeric suffix
    (-1, -2, …) is appended so that every anchor in a document is unique.
    The UsedAnchors hashtable is mutated in place.

.PARAMETER BaseAnchor
    The raw (already-slugified) anchor string derived from a heading.

.PARAMETER UsedAnchors
    Hashtable that tracks how many times each base anchor has appeared.

.EXAMPLE
    $seen = @{}
    Get-UniqueAnchor -BaseAnchor 'intro' -UsedAnchors $seen   # 'intro'
    Get-UniqueAnchor -BaseAnchor 'intro' -UsedAnchors $seen   # 'intro-1'
#>
    param (
        [Parameter(Mandatory)]
        [string]$BaseAnchor,

        [Parameter(Mandatory)]
        [hashtable]$UsedAnchors
    )

    if ($UsedAnchors.ContainsKey($BaseAnchor)) {
        $UsedAnchors[$BaseAnchor]++
        return "$BaseAnchor-$($UsedAnchors[$BaseAnchor])"
    }

    $UsedAnchors[$BaseAnchor] = 0
    return $BaseAnchor
}

function Get-SanitizedMediaName {
<#
.SYNOPSIS
    Returns a URL-safe path for a media asset and registers the mapping.

.DESCRIPTION
    Replaces underscores, spaces, and other URL-hostile characters in the
    filename portion of the path with hyphens, lower-cases the result, and
    appends -01/-02/... when the sanitized name would collide with an
    already-registered entry in the same directory.

    The mapping is stored in the module-level MediaRegistry so both the
    Markdown parser (Apply-Inline) and the file-copy step
    (Publish-MarkdownFiles) produce consistent names.

.PARAMETER Path
    Original relative path as it appears in Markdown source
    (e.g. "img/Install_NSPIR_01.png").

.PARAMETER DebugJsonPath
    Optional path to write the current registry state as a JSON file.

.EXAMPLE
    Get-SanitizedMediaName -Path "img/My File (1).png"
    # Returns: "img/my-file-1.png"
#>
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$DebugJsonPath = $null
    )

    $Path = $Path -replace '\\', '/'

    if ($script:MediaRegistry.ContainsKey($Path)) {
        return $script:MediaRegistry[$Path]
    }

    $lastSlash = $Path.LastIndexOf('/')
    $dir  = if ($lastSlash -ge 0) { $Path.Substring(0, $lastSlash + 1) } else { '' }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $ext  = [System.IO.Path]::GetExtension($Path).ToLower()

    $safe = $name -replace '[_\s\(\)\[\]&#+%!@$\^]', '-'
    $safe = ($safe -replace '-+', '-').Trim('-').ToLower()

    $candidate = $dir + $safe + $ext

    $counter = 0
    while ($script:MediaRegistry.ContainsValue($candidate) -and
           ($script:MediaRegistry.Keys | Where-Object { $script:MediaRegistry[$_] -eq $candidate -and $_ -ne $Path })) {
        $counter++
        $candidate = $dir + $safe + ('-{0:D2}' -f $counter) + $ext
    }

    $script:MediaRegistry[$Path] = $candidate

    if ($DebugJsonPath) {
        $script:MediaRegistry | ConvertTo-Json | Set-Content $DebugJsonPath -Encoding UTF8
    }

    return $candidate
}

function Get-MediaRegistry {
<#
.SYNOPSIS
    Returns the current media-path mapping table.

.DESCRIPTION
    Exposes the module-internal MediaRegistry hashtable so that callers
    (e.g. the build script's debug output or file-copy step) can read the
    complete original-path → sanitized-path mapping without accessing module
    internals directly.

.EXAMPLE
    Get-MediaRegistry | ConvertTo-Json | Set-Content registry.json
#>
    return $script:MediaRegistry
}

# ==============================================================================
# PRIVATE: PARSER HELPERS
# These functions share state via $script: variables that are initialised by
# Convert-DocAtlasMarkDown before each file is processed.
# ==============================================================================

function Escape-Html {
<#
.SYNOPSIS
    Escapes the three characters that would break raw text inside HTML.
#>
    param ([Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text)

    return $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
}

function Apply-Inline {
<#
.SYNOPSIS
    Applies all inline Markdown transformations to a single line of text.

.DESCRIPTION
    Processes (in order): escape sequences, inline code, images, links,
    bold/italic/strikethrough, and custom HR variants. Inline-code spans and
    escape placeholders are protected before pattern substitution so they are
    not double-processed.

.PARAMETER Line
    Raw Markdown text for one line.
#>
    param ([Parameter(Mandatory)][string]$Line)

    # 1. Escaped characters — replace with placeholders to protect from further processing
    $escapeMap = @{}
    $j = 0
    foreach ($escaped in $script:EscapeChars.Keys) {
        $escapedRegex = [regex]::Escape($escaped)
        if ($Line -match $escapedRegex) {
            $key             = "%%ESC$j%%"
            $escapeMap[$key] = $script:EscapeChars[$escaped]
            $Line            = $Line -replace $escapedRegex, [regex]::Escape($key)
            $j++
        }
    }

    # 2. Inline code — protect from inline pattern substitutions
    $codeMap = @{}
    $i       = 0
    $Line    = [regex]::Replace($Line, '\`(.*?)\`', {
        param($m)
        $key           = "%%CODE$i%%"
        $codeMap[$key] = "<code>$(Escape-Html $m.Groups[1].Value)</code>"
        $i++
        return $key
    })

    # 3. Images — resolved before emphasis patterns so underscores in
    #    filenames are not mistaken for italic markers.
    $Line = [regex]::Replace($Line, '!\[(.*?)\]\((.*?)\)', {
        param($m)
        $alt = $m.Groups[1].Value
        $url = Get-SanitizedMediaName -Path $m.Groups[2].Value
        return "<img src=`"$url`" alt=`"$alt`">"
    })

    # 4. Apply remaining inline patterns (links, bold, italic, HR variants, etc.)
    foreach ($p in $script:InlinePatterns.Keys) {
        if ($p -eq '!\[(.*?)\]\((.*?)\)') { continue }
        $Line = $Line -replace $p, $script:InlinePatterns[$p]
    }

    # 5. Restore inline-code placeholders
    foreach ($k in $codeMap.Keys) { $Line = $Line.Replace($k, $codeMap[$k]) }

    # 6. Restore escape placeholders
    foreach ($k in $escapeMap.Keys) { $Line = $Line.Replace($k, $escapeMap[$k]) }

    return $Line
}

function Apply-Heading {
<#
.SYNOPSIS
    Renders a Markdown heading as an HTML element with a unique anchor ID.

.DESCRIPTION
    Slugifies the heading text with Get-Slug, deduplicates the result with
    Get-UniqueAnchor, and wraps the inline-processed text in the appropriate
    <hN id="…"> tag. Anchor IDs are guaranteed to match the href values
    produced by Split-MarkdownSections.

.PARAMETER Level
    Heading level (1–6).

.PARAMETER Text
    Raw heading text (without the leading # characters).
#>
    param (
        [Parameter(Mandatory)][int]   $Level,
        [Parameter(Mandatory)][string]$Text
    )

    $baseAnchor = Get-Slug $Text
    $anchor     = Get-UniqueAnchor -BaseAnchor $baseAnchor -UsedAnchors $script:UsedAnchors
    $innerHtml  = Apply-Inline $Text

    return "<h$Level id=`"$anchor`">$innerHtml</h$Level>"
}

function Add-OutputLine {
<#
.SYNOPSIS
    Appends a line to the active output target.

.DESCRIPTION
    Routes the line to the DocAtlas-box buffer while inside a ::da: block,
    or to the main output list otherwise.

.PARAMETER Line
    HTML line to append.
#>
    param ([Parameter(Mandatory)][AllowNull()]
    [AllowEmptyString()][string]$Line)

    if ($script:InBaseBox) {
        $script:BoxBuffer.Add($Line)
    }
    else {
        $script:Output.Add($Line)
    }
}

function Flush-Paragraph {
<#
.SYNOPSIS
    Wraps accumulated paragraph lines in a <p> tag and emits them.

.DESCRIPTION
    Joins all lines in the paragraph buffer with a space, wraps the result in
    a <p> tag, and passes it to Add-OutputLine. HR lines collected into the
    buffer are emitted unwrapped. Clears the buffer afterwards.
#>
    if ($script:ParagraphBuffer.Count -eq 0) { return }

    $joined = $script:ParagraphBuffer -join ' '

    if ($joined -match '<hr class=.+') {
        Add-OutputLine $joined
        $script:ParagraphBuffer.Clear()
        return
    }

    Add-OutputLine "<p>$joined</p>"
    $script:ParagraphBuffer.Clear()
}

function Get-ListCssClass {
<#
.SYNOPSIS
    Maps a list marker character to its CSS class name.

.PARAMETER Marker
    The marker string as it appears in the Markdown source
    (e.g. "-", "->", "*", "°").
#>
    param ([Parameter(Mandatory)][string]$Marker)

    switch ($Marker) {
        '-'  { return 'list-dash' }
        '->' { return 'list-arrow-right' }
        '<-' { return 'list-arrow-left' }
        '*'  { return 'list-star' }
        '°'  { return 'list-circle' }
        '~'  { return 'list-tilde' }
        '+'  { return 'list-plus' }
        '<3' { return 'list-heart' }
        '<X' { return 'list-cross' }
        '<C' { return 'list-check' }
        default { return 'list-dash' }
    }
}

function Flush-Table {
<#
.SYNOPSIS
    Renders the buffered table rows as a complete HTML table element.

.DESCRIPTION
    Emits a <table> with an optional <thead> (populated from the stored header
    row and alignment hints) followed by a <tbody> for all data rows. Clears
    all table state afterwards. Does nothing if no table is currently open.
#>
    if (-not $script:InTable -or $script:TableBuffer.Count -eq 0) { return }

    $script:Output.Add('<table>')

    if ($script:TableHeader) {
        $script:Output.Add('<thead><tr>')

        for ($i = 0; $i -lt $script:TableHeader.Count; $i++) {
            $align = if ($script:TableAlign.Count -gt $i) { $script:TableAlign[$i] } else { 'left' }
            $script:Output.Add("<th class=`"td-align-$align`">$(Apply-Inline $script:TableHeader[$i])</th>")
        }

        $script:Output.Add('</tr></thead>')
    }

    $script:Output.Add('<tbody>')

    foreach ($row in $script:TableBuffer) {
        $cells = ($row -split '\s*\|\s*') | Where-Object { $_ -ne '' }

        $script:Output.Add('<tr>')

        for ($i = 0; $i -lt $cells.Count; $i++) {
            $align = if ($script:TableAlign.Count -gt $i) { $script:TableAlign[$i] } else { 'left' }
            $script:Output.Add("<td class=`"td-align-$align`">$(Apply-Inline $cells[$i])</td>")
        }

        $script:Output.Add('</tr>')
    }

    $script:Output.Add('</tbody></table>')

    $script:TableBuffer.Clear()
    $script:TableHeader = $null
    $script:InTable     = $false
}

# ==============================================================================
# PUBLIC: MAIN CONVERTER
# ==============================================================================

function Convert-DocAtlasMarkDown {
<#
.SYNOPSIS
    Converts a single DocAtlas-flavoured Markdown file to an HTML fragment.

.DESCRIPTION
    Implements a custom line-by-line Markdown parser that handles:

      • Headings H1–H6 with unique anchor IDs
      • Fenced code blocks (``` … ```) with optional language hint
      • Tables (GitHub-Flavored Markdown style) with alignment
      • Blockquotes (nested, up to 6 levels)
      • Ordered and unordered lists with custom markers and checkbox items
      • DocAtlas callout boxes  ::da:<type> [title] … ::da:end
      • Inline formatting: bold, italic, bold-italic, strikethrough
      • Links, auto-links, images
      • Escape sequences (\*, \_, etc.)
      • Custom HR variants (---_, ---*, ---., ---)

    The output is a bare HTML fragment (no <html>/<body> wrapper) written to
    OutputFile in UTF-8 encoding.

.PARAMETER InputFile
    Path to the source .md file.

.PARAMETER OutputFile
    Path where the resulting .html fragment will be written.

.EXAMPLE
    Convert-DocAtlasMarkDown -InputFile "src/docs/intro.md" `
                             -OutputFile "html/sites/intro.html"
#>
    param (
        [Parameter(Mandatory)]
        [string]$InputFile,

        [Parameter(Mandatory)]
        [string]$OutputFile
    )

    # ── Initialise shared parser state ────────────────────────────────
    $script:Output          = [System.Collections.Generic.List[string]]::new()
    $script:InBaseBox       = $false
    $script:BoxBuffer       = [System.Collections.Generic.List[string]]::new()
    $script:ParagraphBuffer = [System.Collections.Generic.List[string]]::new()
    $script:UsedAnchors     = @{}
    $script:InTable         = $false
    $script:TableBuffer     = [System.Collections.Generic.List[string]]::new()
    $script:TableHeader     = $null
    $script:TableAlign      = @()

    # ── Local per-file state ──────────────────────────────────────────
    $lines       = Get-Content $InputFile -Encoding UTF8
    $TOCLIST     = $false
    $inCodeBlock = $false
    $codeFence   = 0
    $codeLang    = ''
    $inList      = $false
    $listStack   = [System.Collections.Stack]::new()
    $tagOpen     = ''
    $tagClose    = ''
    $inQuote     = $false
    $quoteStack  = [System.Collections.Stack]::new()
    $currentType = $null

    foreach ($line in $lines) {

        if ($line -match '::DA:TOC') {
            $TOCLIST = $true
            continue
        }

        # ── Code block ──────────────────────────────────────────────
        if ($line -match '^(`{3,})\s*([\w-]+)?\s*$') {
            Flush-Paragraph
            $fence = $Matches[1]
            $lang  = $Matches[2]

            if (-not $inCodeBlock) {
                $inCodeBlock = $true
                $codeFence   = $fence.Length
                $codeLang    = $lang

                if ($codeLang) {
                    Add-OutputLine "<pre><code class=`"language-$codeLang`">"
                }
                else {
                    Add-OutputLine '<pre><code>'
                }
            }
            else {
                if ($fence.Length -ge $codeFence) {
                    $inCodeBlock = $false
                    $codeFence   = 0
                    Add-OutputLine '</code></pre>'
                }
                else {
                    Add-OutputLine (Escape-Html $line)
                }
            }
            continue
        }

        if ($inCodeBlock) {
            Add-OutputLine (Escape-Html $line)
            continue
        }

        # ── Table ────────────────────────────────────────────────────
        if ($line -match '^\s*\|(.+)\|\s*$') {
            Flush-Paragraph
            $cells = $Matches[1].Split('|') | ForEach-Object { $_.Trim() }

            if ($script:InTable -and ($cells -match '^[:]{0,1}-{3,}[:]{0,1}$')) {
                $script:TableAlign = @()
                foreach ($cell in $cells) {
                    $c = $cell.Trim()
                    if     ($c -match '^:-{3,}:$')  { $script:TableAlign += 'center' }
                    elseif ($c -match '^-{3,}:$')   { $script:TableAlign += 'right' }
                    else                             { $script:TableAlign += 'left' }
                }
                continue
            }

            if (-not $script:InTable) {
                $script:InTable     = $true
                $script:TableHeader = $cells
                continue
            }

            $script:TableBuffer.Add($cells -join '|')
            continue
        }
        else {
            if ($script:InTable) {
                Flush-Table
                $script:InTable = $false
            }
        }

        # ── Blockquote ───────────────────────────────────────────────
        if ($line -match '^\s*(>{1,6})(.*)$') {
            $level = $Matches[1].Length
            $line  = $Matches[2]

            if (-not $inQuote) {
                Flush-Paragraph
                $inQuote = $true
            }

            $current = $quoteStack.Count

            while ($current -gt $level) {
                Flush-Paragraph
                Add-OutputLine '</blockquote>'
                $quoteStack.Pop() | Out-Null
                $current--
            }

            while ($current -lt $level) {
                Add-OutputLine '<blockquote>'
                $quoteStack.Push($true)
                $current++
            }
        }
        else {
            if ($inQuote) {
                Flush-Paragraph
                while ($quoteStack.Count -gt 0) {
                    Add-OutputLine '</blockquote>'
                    $quoteStack.Pop() | Out-Null
                }
                $inQuote = $false
            }
        }

        # ── DocAtlas callout box ─────────────────────────────────────
        if (-not $inCodeBlock -and -not $script:InBaseBox -and
            $line -match '^::da:(\w+)(?:\s+(.*))?$') {

            Flush-Paragraph
            $type  = $Matches[1]
            $title = $Matches[2]

            if ($script:DaTypes.ContainsKey($type)) {
                $script:InBaseBox = $true
                $currentType      = $type
                $script:BoxBuffer.Clear()

                if ($title) {
                    $script:BoxBuffer.Add(
                        "<div class=`"md-box-title`">$($script:DaTypes[$type].icon) $(Apply-Inline $title)</div>"
                    )
                }
            }
            continue
        }

        if (-not $inCodeBlock -and $line -match '^::da:end$') {
            Flush-Paragraph

            if ($script:InBaseBox -and $currentType) {
                $meta = $script:DaTypes[$currentType]
                $script:Output.Add("<div class=`"md-box $($meta.class)`">")
                $script:Output.Add('<div class="md-box-content">')
                foreach ($l in $script:BoxBuffer) { $script:Output.Add($l) }
                $script:Output.Add('</div></div>')

                $script:InBaseBox = $false
                $currentType      = $null
                $script:BoxBuffer.Clear()
            }
            continue
        }

        # ── List ─────────────────────────────────────────────────────
        if ($line -match '^(\s*)([-*+~°]|->|<-|<3|<X|<C|[0-9]\.)\s+(.*)') {
            Flush-Paragraph

            $indent  = $Matches[1].Length
            $marker  = $Matches[2]
            $content = $Matches[3]

            # Checkbox items
            if ($content -match '^\[(x| )\]\s+(.*)$') {
                $checked = if ($Matches[1] -eq 'x') { ' checked=""' } else { '' }
                $class   = if ($Matches[1] -eq 'x') { 'list-checkbox-done' } else { 'list-checkbox' }
                $inner   = Apply-Inline $Matches[2]

                if (-not $inList) {
                    Add-OutputLine '<ul>'
                    $listStack.Push($indent)
                    $inList = $true
                }

                Add-OutputLine "<li class=`"$class`"><input disabled=`"`" type=`"checkbox`"$checked> $inner</li>"
                continue
            }

            $content = Apply-Inline $content

            if ($marker -match '[0-9]\.') {
                $tagOpen  = '<ol>'
                $tagClose = '</ol>'
                $class    = 'list-num'
            }
            else {
                if ($TOCLIST) {
                    $tagOpen = '<ul class="da-toc-list">'
                    $TOCLIST = $false
                }
                else {
                    $tagOpen = '<ul>'
                }
                $tagClose = '</ul>'
                $class    = Get-ListCssClass $marker
            }

            if (-not $inList) {
                Add-OutputLine $tagOpen
                $listStack.Push($indent)
                $inList = $true
            }

            while ($listStack.Count -gt 0 -and $indent -lt $listStack.Peek()) {
                Add-OutputLine $tagClose
                $listStack.Pop() | Out-Null
            }

            if ($listStack.Count -eq 0 -or $indent -gt $listStack.Peek()) {
                Add-OutputLine $tagOpen
                $listStack.Push($indent)
            }

            Add-OutputLine "<li class=`"$class`">$content</li>"
            continue
        }
        else {
            if ($inList) {
                while ($listStack.Count -gt 0) {
                    Add-OutputLine $tagClose
                    $listStack.Pop() | Out-Null
                }
                $inList = $false
            }
        }

        # ── Headings H1–H6 ───────────────────────────────────────────
        $handled = $false

        foreach ($pattern in $script:MdPatterns.Keys) {
            if ($line -match $pattern) {
                Flush-Paragraph
                Add-OutputLine (Apply-Heading -Level $script:MdPatterns[$pattern] -Text $Matches[1])
                $handled = $true
                break
            }
        }

        if ($handled) { continue }

        # ── Blank line ───────────────────────────────────────────────
        if ($line.Trim() -eq '') {
            Flush-Paragraph
            continue
        }

        $script:ParagraphBuffer.Add((Apply-Inline $line))
    }

    # ── Flush remaining state ─────────────────────────────────────────
    Flush-Paragraph
    Flush-Table

    if ($inList) {
        while ($listStack.Count -gt 0) {
            Add-OutputLine $tagClose
            $listStack.Pop() | Out-Null
        }
    }

    # Close any unclosed ::da: box
    if ($script:InBaseBox -and $currentType) {
        $meta = $script:DaTypes[$currentType]
        $script:Output.Add("<div class=`"md-box $($meta.class)`">")
        $script:Output.Add('<div class="md-box-content">')
        foreach ($l in $script:BoxBuffer) { $script:Output.Add($l) }
        $script:Output.Add('</div></div>')
    }

    Set-Content $OutputFile $script:Output -Encoding UTF8
}

# ==============================================================================
# MODULE EXPORTS
# ==============================================================================

Export-ModuleMember -Function @(
    'Convert-DocAtlasMarkDown',
    'Get-Slug',
    'Get-UniqueAnchor',
    'Get-SanitizedMediaName',
    'Get-MediaRegistry'
)
