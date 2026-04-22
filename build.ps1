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
function Get-Title($file) {
<#

.SYNOPSIS
    Extracts the main title from a Markdown file.

.DESCRIPTION
    The function reads the content of the specified Markdown file, looks for the first line that starts with a single '#' 
    (indicating a top-level heading), and returns the text of that heading as the title. 
    If no such line is found, it falls back to using the file name (without extension) as the title.
#>

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
    Extracts subtitle headings from a Markdown file.

.DESCRIPTION
    The function reads the content of the specified Markdown file and returns all second,third... -level headings (lines starting with '##').
#>
    param (
        [string]$File
    )

    $items = @()
    $inCodeBlock = $false

    foreach ($line in Get-Content $File) {

        if ($line -match '^\s*```') {
            $inCodeBlock = -not $inCodeBlock
            continue
        }

        if (-not $inCodeBlock -and $line -match '^(#{2,})\s+(.+)$') {
            $title = $matches[2].Trim()

            $items += [PSCustomObject]@{
                title = $title
                slug  = Get-Slug -text $title
            }
        }
    }

    return $items
}

function Get-CleanMarkdownContent($Path) {

    $content = Get-Content $Path -Raw

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

function Get-Slug($text) {
<#
.SYNOPSIS
    Converts a string into a URL-friendly slug. 

.DESCRIPTION
    The function takes a string input, converts it to lowercase, replaces German umlauts with their 
    ASCII equivalents, removes special characters, and replaces whitespace with hyphens.
#>

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
function Build-Tree {

    param (
        [Parameter(Mandatory)]
        [string]$BasePath,

        [string]$CurrentPath = $BasePath,
        [string]$ParentSlug = ""
    )

    $invalidChars = "[\(\)\[\]\{\}#?%&]"

    $items = New-Object System.Collections.Generic.List[object]

    $entries = Get-ChildItem -LiteralPath $CurrentPath -Force |
        Sort-Object @{Expression = { -not $_.PSIsContainer }}, Name

    foreach ($entry in $entries) {

        $relativePath = [System.IO.Path]::GetRelativePath($BasePath, $entry.FullName) -replace "\\","/"

        # -----------------------------
        # DIRECTORY
        # -----------------------------
        if ($entry.PSIsContainer) {

            if ($entry.Name -match $invalidChars) {
                Write-Warning "Folder '$($entry.FullName)' contains special characters that may cause problems in URLs."
            }

            $title = $entry.Name
            $indexFile = Join-Path $entry.FullName "index.md"

            if (Test-Path $indexFile) {
                $title = Get-Title $indexFile
            }

            $localSlug = Get-Slug $title
            $slug = if ($ParentSlug) { "$ParentSlug/$localSlug" } else { $localSlug }

            # Rekursion zuerst, damit wir children prüfen können
            $children = @()
            $children = Build-Tree -BasePath $BasePath -CurrentPath $entry.FullName -ParentSlug $slug

            # Ordner ohne Inhalt skippen
            if ($children.Count -eq 0 -and -not (Test-Path $indexFile)) {
                continue
            }

            $items.Add([PSCustomObject]@{
                title    = $title
                file     = "$relativePath/index.md"
                slug     = $slug
                children = $children
                type     = if (Test-Path $indexFile) { 3 } else { 2 }
            })

            continue
        }

        # -----------------------------
        # MARKDOWN FILE
        # -----------------------------
        if ($entry.Extension -ne ".md" -or $entry.Name -eq "index.md") {
            continue
        }

        $title = Get-Title $entry.FullName

        $content = Get-CleanMarkdownContent $entry.FullName 

        $localSlug = Get-Slug $title
        $slug = if ($ParentSlug) { "$ParentSlug/$localSlug" } else { $localSlug }
        $children = @()
        $children = Get-SubTitles $entry.FullName

        $items.Add([PSCustomObject]@{
            title    = $title
            file     = $relativePath
            slug     = $slug
            text     = $content
            children = $children
            type     = 1
        })
    }

    return $items
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


# Clean up the build directory
Write-Host "Cleaning up build directory..." -ForegroundColor Cyan
Remove-Item $outMd -Recurse -Force -ErrorAction Ignore | Out-Null
Remove-Item $outAppConfig   -Force -ErrorAction Ignore | Out-Null
Remove-Item $outNavIndex    -Force -ErrorAction Ignore | Out-Null
Remove-Item $outSearchIndex -Force -ErrorAction Ignore | Out-Null

New-Item -ItemType Directory -Path $outMd | Out-Null


# --------------------------------------------------
# SCAN SRC and Build Tree Structure
# --------------------------------------------------
Write-Host "Scanning source directory and building tree structure..." -ForegroundColor Cyan
$tree = Build-Tree -BasePath $src

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
$nav |
    ConvertTo-Json -Depth 20 |
    Set-Content $outNavIndex -Encoding UTF8

# --------------------------------------------------
# WRITE Search-Index
# --------------------------------------------------
$searchIndex = ,@(Flatten-SearchIndex $tree)

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