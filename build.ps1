param (
    [string] $ini
)

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
#  INI file preperation
#--------------------------------------------------
function Parse-IniFile {
<# 
.SYNOPSIS
    Parses a simple INI file

.DESCRIPTION
    The function reads the file line by line, removes block comments,
    recognises sections ([section]), key/value pairs (key="value" or
    key=value), and builds a nested hashtable
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    # -----------------------------------------------------------------
    # 1. Load file & strip block comments (/* … */)
    # -----------------------------------------------------------------
    if (-not (Test-Path -LiteralPath $Path)) {
        Throw "File not found: $Path"
    }

    $rawLines = Get-Content -LiteralPath $Path -Raw 
    # Remove multiline block comments (/* … */) – they may span several lines
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

            $key = $matches[1].Trim()
            $value = $matches[2].Trim()

            # Remove surrounding quotes if present
            if ($value -match '^"(.*)"$') {
                $value = $matches[1]
            }

            # Basic type conversion
            switch -regex ($value) {
                '^true$' { $value = $true }
                '^false$' { $value = $false }
                '^\d+$' { $value = [int]$value }
                '^\d+\.\d+$' { $value = [double]$value }
                '^\[\]$' { $value = @() }
                '^\[(.+)\]$' { 
                    # Split comma-separated values inside []
                    $value = ($matches[1] -split ',').ForEach({ $_.Trim() })
                }
            }

            $iniData[$currentSection][$key] = $value
        }
    }

    Write-Output ($iniData | ConvertTo-Json | ConvertFrom-Json)
}

function Prepare-DebugConfig{
<#
.SYNOPSIS
    Prepares the debug configuration.

.DESCRIPTION
    The function checks if the debug mode is enabled and, if so, ensures that the markdown folder path ends with a forward slash.
#>
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNull()]
        $config,
        [Parameter(Mandatory, Position = 1)]
        $SCRIPT_ROOT
    )

    $config.debug | Add-Member -Name outPath -Value (Join-Path $SCRIPT_ROOT "debug") -MemberType NoteProperty
    $config.debug | Add-Member -Name tree -Value "debug_tree.json" -MemberType NoteProperty
    $config.debug | Add-Member -Name navigation -Value "debug_nav.json" -MemberType NoteProperty
    $config.debug | Add-Member -Name globalSearchIndex -Value "debug_gsi.json" -MemberType NoteProperty
    $config.debug | Add-Member -Name searchIndexSufix -Value "debug_si_{0}.json" -MemberType NoteProperty

    return $config
}

function Check-ConfigValues {
<#
.SYNOPSIS
    Checks and corrects the configuration values.

.DESCRIPTION
    The function ensures that the navigation file and markdown folder paths end with a forward slash.
#>
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNull()]
        $config
    )
    if (-not $config.environment.markdownFolder.EndsWith('\')) {
        $config.environment.markdownFolder += '\'
    }

    return $config
}

# --------------------------------------------------
#  Markdown title, subtitles and slug helpers
# --------------------------------------------------
function Get-Title {
<#

.SYNOPSIS
    Extracts the main title from a Markdown file.

.DESCRIPTION
    The function reads the content of the specified Markdown file, looks for the first line that starts with a single '#' 
    (indicating a top-level heading), and returns the text of that heading as the title. 
    If no such line is found, it falls back to using the file name (without extension) as the title.
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

function Get-SubTitles {
<#
.SYNOPSIS
    Extracts subtitles (H2-H6) from a Markdown file and generates slugs for them.
.DESCRIPTION
    The function reads the content of the specified Markdown file, identifies lines that represent subtitles (starting
#>

    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$File,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$Slug
    )

    $items = @()
    $anchorCounts = @{}
    $lines = Get-Content $File

    $currentTitle = $null
    $currentLevel = $null
    $buffer       = New-Object System.Text.StringBuilder

    $inCodeBlock = $false

    function Flush-Section {
        param (
            [string] $ct,
            [string] $sl,
            [int] $cl,
            [string] $t
        )

        $baseAnchor = Get-Slug $ct

        if ($anchorCounts.ContainsKey($baseAnchor)) {
            $anchorCounts[$baseAnchor]++
            $anchor = "$baseAnchor-$($anchorCounts[$baseAnchor])"
        }
        else {
            $anchorCounts[$baseAnchor] = 1
            $anchor = $baseAnchor
        }

        return [PSCustomObject]@{
            title  = $ct
            slug   = $sl
            anchor = $anchor
            level  = $cl
            text   = Get-CleanMarkdownContent -content $t.trim()
        }
    }

    foreach ($line in $lines) {

        # Codeblock toogle
        if ($line -match '^\s*```') {
            $inCodeBlock = -not $inCodeBlock
        }

        # Headline detection (H2-H6)
        if (-not $inCodeBlock -and $line -match '^(#{2,6})\s+(.+)$') {
            $level = $matches[1].Length
            $title = $matches[2].Trim()

            # Save current section before starting a new one
            if ($currentTitle -and $level -le $currentLevel) {
                $items += Flush-Section -ct $currentTitle -sl $Slug -cl $currentLevel -t $buffer.ToString()
                $buffer.Clear() | Out-Null
            }

            $currentTitle = $title
            $currentLevel = $level

            continue
        }

        # Content buffering for the current section
        if ($currentTitle) {
            [void]$buffer.AppendLine($line)
        }
    }

    # save last section
    if (-not $currentTitle) { continue }
    $items += Flush-Section -ct $currentTitle -sl $Slug -cl $currentLevel -t $buffer.ToString()
    $buffer.Clear() | Out-Null

    return $items
}

function Get-CleanMarkdownContent {
    param (
        [Parameter(Mandatory)]
        $content
    )

    #$content = Get-Content $Path -Raw

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

    # Optional: remove HTML tags
    $content = [regex]::Replace($content, '<[^>]+>', '')

    return $content.Trim()
}

function Get-Slug {
<#
.SYNOPSIS
    Converts a string into a URL-friendly slug. 

.DESCRIPTION
    The function takes a string input, converts it to lowercase, replaces German umlauts with their 
    ASCII equivalents, removes special characters, and replaces whitespace with hyphens.
#>
 param (
    [Parameter(Mandatory)]
    $text
 )

    $slug = $text.ToLower()

    $slug = $slug -replace "ä","ae"
    $slug = $slug -replace "ö","oe"
    $slug = $slug -replace "ü","ue"
    $slug = $slug -replace "ß","ss"

    $slug = $slug -replace "\\", "/"              # normalize separators first
    $slug = $slug -replace "[^a-z0-9\s\-]", ""    # allow /
    $slug = $slug -replace "\s+", "-"             # spaces → dash

    return $slug.Trim("-")
}

# --------------------------------------------------
#  Copy files and indexing helpers
# -------------------------------------------------
function Copy-Files {
<#
.SYNOPSIS
    Copies files from a source directory to a destination directory.

.DESCRIPTION
    The function recursively copies all files from the source directory to the destination directory, maintaining the directory structure.
#>
    param(
        [string]$Source,
        [string]$Destination
    )

    $files = Get-ChildItem $Source -Recurse -File

    foreach ($file in $files) {

        $relative = $file.FullName.Substring($Source.Length).TrimStart("\","/")
        $dest = Join-Path $Destination $relative
        $destDir = Split-Path $dest

        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        }

        $null = Copy-Item $file.FullName $dest -Force
    }
}

function Create-Index {
<#
.SYNOPSIS
    Creates an index file for a directory.

.DESCRIPTION
    The function generates an index file containing a table of contents for the specified directory.
#>
    param(
        [string]$Folder,
        [array]$Children
    )

    $index = Join-Path $Folder $buildConf.tableOfContents.name

    if (Test-Path $index) {
        return
    }

    $title = Split-Path $Folder -Leaf

    $toc = @()
    $toc += "# $title"
    $toc += ""
    $toc += "## Inhaltsverzeichnis"
    $toc += ""

    foreach ($child in $Children) {

        if (-not $child.slug) { continue }

        $toc += "- [$($child.title)](#$($child.slug))"
    }

    $toc | Set-Content $index -Encoding UTF8
}


# --------------------------------------------------
#   Tree building and processing
# -------------------------------------------------
function Get-H1Content {

    param (
        [Parameter(Mandatory)]
        [string]$Content
    )

    $lines = $Content -split "`n"

    $inCodeBlock = $false
    $foundH1 = $false

    $buffer = New-Object System.Text.StringBuilder

    foreach ($line in $lines) {

        # Codeblock toggeln
        if ($line -match '^\s*```') {
            $inCodeBlock = -not $inCodeBlock
        }

        # H1 erkennen
        if (-not $inCodeBlock -and $line -match '^#\s+(.+)$') {
            $foundH1 = $true

            # H1 explizit in Content aufnehmen
            [void]$buffer.AppendLine($line)

            continue
        }

        # Erste Sub-Headline beendet den Bereich
        if ($foundH1 -and -not $inCodeBlock -and $line -match '^#{2,6}\s+') {
            break
        }

        # Content sammeln
        if ($foundH1) {
            [void]$buffer.AppendLine($line)
        }
    }

    return $buffer.ToString().Trim()
}

function Build-Tree {

    param(
        [Parameter(Mandatory)]
        [string]$BasePath
    )
    function Append-Tree {
        param (
            [Parameter(Mandatory)]
            [string]$BasePath,
            [string]$ParentSlug = ""
        )

        # Invalid url chars
        $invalidChars = "[\(\)\[\]\{\}#?%&]"

        $items = New-Object System.Collections.Generic.List[object]
        $entries = Get-ChildItem -LiteralPath $BasePath -Force |
            Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name

        foreach ($entry in $entries) {
            if (-not $entry.PSIsContainer -and $entry.Extension -ne '.md') {
                continue
            }

            if ($entry.PSIsContainer) {
                if ($entry.Name -match $invalidChars) {
                    Write-Warning "Folder '$($entry.FullName)' contains special characters that may cause problems in URLs."
                }

                $Content = ''
                $indexFile = Join-Path $entry.FullName "index.md"
                if (Test-Path $indexFile) {
                    $title = Get-Title $indexFile

                    $raw = Get-Content $indexFile -Raw
                    $content = Get-CleanMarkdownContent -content $raw
                    if ([string]::IsNullOrWhiteSpace($title.toSTring())) {
                        $title = $entry.Name
                        Write-Warning "Index file '$indexFile' missing H1 headline (# Title). This may break the search engine."
                    }
                    $localSlug = Get-Slug $title
                }
                else {
                    $title = $entry.Name
                    $localSlug = Get-Slug $title
                }
                
                $slug = if ($ParentSlug) { "$ParentSlug/$localSlug" } else { $localSlug }
                $children = Append-Tree -BasePath $entry.FullName -ParentSlug $slug

                if ($children.Count -eq 0 -and -not (Test-Path $indexFile)) {
                    continue
                }
                $items.Add([PSCustomObject]@{
                    File     = $indexFile

                    Title    = $title
                    Content  = $Content
                    Slug     = $slug
                    Children = $children
                })    
            }
            elseif ($entry.Extension -eq '.md') {

                $raw = Get-Content $entry.FullName -Raw
                $content = Get-CleanMarkdownContent -content $raw

                $title = Get-Title $entry.FullName
                $localSlug = Get-Slug $title
                $slug = if ($ParentSlug) { "$ParentSlug/$localSlug" } else { $localSlug }

                $items.Add([PSCustomObject]@{
                    File     = $entry.FullName

                    Title    = $title
                    Content  = $content 
                    Slug     = $slug
                    Children = $null
                })
            }
        }
        return $items

    }

    $indexFile = Join-Path $BasePath "index.md"

    $title = Split-Path $BasePath -Leaf
    $content = ""

    if (Test-Path $indexFile) {
        $raw = Get-Content $indexFile -Raw
        $content = Get-CleanMarkdownContent -content $raw
        $title = Get-Title $indexFile
    }

    $children = Append-Tree -BasePath $BasePath -ParentSlug ""

    return [PSCustomObject]@{
        File     = $indexFile
        Title    = $title
        Content  = $content
        Slug     = ""
        Children = $children
    }
}

function Process-Tree {
<# 
.SYNOPSIS
    Recursively processes a tree structure and creates index files for each directory.

.DESCRIPTION
    The function traverses the tree structure and creates index files for each directory, containing a table of contents.
#>
    param(
        [array]$Nodes,
        [string]$CurrentPath
    )

    foreach ($node in $Nodes) {
        $folder = Join-Path $CurrentPath $node.title
        $indexFile = Join-Path $folder $buildConf.tableOfContents.name
        if (-not (Test-Path $indexFile) -and $node.type -eq 2) {
            Create-Index -Folder $folder -Children $node.children
            $children = @()
            $children = $node.children | Where-Object { $_.type -ge 2 }
            if ($children.Count -gt 0) {
                Process-Tree -Nodes $node.children -CurrentPath $folder
            }
        }
    }
}

function Strip-Text {
    param($nodes)

    $result = @()

    foreach ($n in $nodes) {

        $obj = [PSCustomObject]@{
            title = $n.title
            file  = $n.file
            slug  = $n.slug
            type  = $n.type
        }

        if ($n.children) {
            $obj | Add-Member -Name children -Value (Strip-Text $n.children) -MemberType NoteProperty
        }

        $result += $obj
    }

    return $result
}

function Flatten-SearchIndex {
    param($nodes)

    $result = @()

    foreach ($n in $nodes) {

        if ($n.text) {
            $result += [PSCustomObject]@{
                title = $n.title
                slug  = $n.slug
                text  = $n.text
            }
        }

        # Unterüberschriften (H2/H3)
        if ($n.children) {

            foreach ($c in $n.children) {

                if ($c.slug) {
                    $result += [PSCustomObject]@{
                        title = $c.title
                        slug  = "$($n.slug)/$($c.slug)"
                        text  = $c.title
                    }
                }

                # falls deeper nesting existiert
                if ($c.children) {
                    $result += Flatten-SearchIndex $c.children
                }
            }
        }
    }

    return $result
}

# --------------------------------------------------
# Prepare build environment
# --------------------------------------------------
Write-Host "Preparing build environment..." -ForegroundColor Cyan

# Save the script's directory as the root for relative paths
$scriptRoot = $PSScriptRoot

# If no INI file is provided as a parameter, look for "build.ini" in the script's directory
if (-not $PSBoundParameters.ContainsKey("ini")) {
    $ini = join-path $scriptRoot "build.ini"
}

# Parse the INI file to get configuration settings
$ParseConf = Parse-IniFile -Path $ini
if ($ParseConf.debug.enabled) {
    Write-Host "Debug mode is enabled. Preparing debug configuration..." -ForegroundColor Yellow
}
$ParseConf = Prepare-DebugConfig -config $ParseConf -SCRIPT_ROOT $scriptRoot
$buildConf = $ParseConf | Check-ConfigValues

# Define source and build paths based on the configuration
# Source folder from which the content is read. Must be located inside the root directory
$src   = Join-Path $scriptRoot "src"

# Destination folder where the generated HTML will be written. Must be located inside the root directory
$build = Join-Path $scriptRoot "html"

# Output paths for generated Markdown files and navigation structure
$outAppConfig = Join-Path $build "app.json"
$outMd = Join-Path $build $buildConf.environment.markdownFolder
$outNavIndex= Join-Path $build $buildConf.environment.navigationIndex
$outSearchIndex = Join-Path $build $buildConf.environment.searchIndex
$outDebug = $buildConf.debug.outPath


# Clean up the build directory
Write-Host "Cleaning up build directory..." -ForegroundColor Cyan
Remove-Item $outMd -Recurse -Force -ErrorAction Ignore | Out-Null
Remove-Item $outDebug -Recurse -Force -ErrorAction Ignore | Out-Null
Remove-Item $outAppConfig   -Force -ErrorAction Ignore | Out-Null
Remove-Item $outNavIndex    -Force -ErrorAction Ignore | Out-Null
Remove-Item $outSearchIndex -Force -ErrorAction Ignore | Out-Null

New-Item -ItemType Directory -Path $outMd | Out-Null
if ($buildConf.debug.enabled) {
    Write-Host "Creating debug output directory..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $outDebug | Out-Null
}


# --------------------------------------------------
# SCAN SRC and Build Tree Structure
# --------------------------------------------------
Write-Host "Scanning source directory and building tree structure..." -ForegroundColor Cyan
$tree = Build-Tree -BasePath $src

if ($buildConf.debug.enabled) {
    Write-Host "Writing debug tree structure to JSON..." -ForegroundColor Yellow
    $tree | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $outDebug $buildConf.debug.tree) -Encoding UTF8
}

if ($null -eq $tree) {
    exit
}
exit
# --------------------------------------------------
# COPY SOURCE FILES
# --------------------------------------------------
Write-Host "Copying source files to build directory..." -ForegroundColor Cyan
Copy-Files -Source $src -Destination $outMd

# --------------------------------------------------
# GENERATE INDEX FILES
# --------------------------------------------------
Write-Host "Generating index files..." -ForegroundColor Cyan
Process-Tree -Nodes $tree -CurrentPath $outMd


# --------------------------------------------------
# WRITE NAVIGATION
# --------------------------------------------------
Write-Host "Writing navigation structure to JSON..." -ForegroundColor Cyan
$nav = ,@(Strip-Text $tree)

if ($buildConf.debug.enabled) {
    Write-Host "Writing debug navigation structure to JSON..." -ForegroundColor Yellow
    $nav | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $outDebug $buildConf.debug.navigation) -Encoding UTF8
}

$nav |
    ConvertTo-Json -Depth 20 |
    Set-Content $outNavIndex -Encoding UTF8

# --------------------------------------------------
# WRITE Search-Index
# --------------------------------------------------
$searchIndex = ,@(Flatten-SearchIndex $tree)

if ($buildConf.debug.enabled) {
    Write-Host "Writing debug search index to JSON..." -ForegroundColor Yellow
    $searchIndex | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $outDebug $buildConf.debug.globalSearchIndex) -Encoding UTF8
}

$searchIndex |
    ConvertTo-Json -Depth 5 |
    Set-Content $outSearchIndex -Encoding UTF8

# --------------------------------------------------
# WRITE APPLICATION CONFIGURATION
# --------------------------------------------------
Write-Host "Writing application configuration to JSON..." -ForegroundColor Cyan
($buildConf | ConvertTo-Json -Depth 5) -replace "\\\\","/" | 
    Set-Content $outAppConfig -Encoding UTF8 
 
# --------------------------------------------------
# Build complete
# --------------------------------------------------
Write-Host "Build process completed successfully." -ForegroundColor Green
Start-Sleep -Seconds 5
exit