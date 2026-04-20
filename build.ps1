param (
    [string] $ini
)

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
    $slug = $slug -replace "[^a-z0-9\s\-/]", ""   # allow /
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

        [string]$CurrentPath = $BasePath
    )

    $items = @()

    $entries = Get-ChildItem -LiteralPath $CurrentPath | Sort-Object {
        if ($_.PSIsContainer) { 1 } else { 0 }
    }, Name

    foreach ($entry in $entries) {

        # -----------------------------
        # DIRECTORY
        # -----------------------------
        if ($entry.PSIsContainer) {

            $invalidChars = "[\(\)\[\]\{\}#?%&]"
            if ($entry.Name -match $invalidChars) {
        
                Write-Warning "Folder '$($entry.FullName)' contains special characters that may cause problems in URLs. Consider renaming the folder."
            }

            $children = Build-Tree -BasePath $BasePath -CurrentPath $entry.FullName

            # Ordner ohne Markdown komplett ignorieren
            if ($children.Count -eq 0) {
                continue
            }

            $relativePath = [System.IO.Path]::GetRelativePath($BasePath, $entry.FullName)
            $relativePath = $relativePath -replace "\\","/"

            $indexFile = Join-Path $entry.FullName "index.md"

            if (Test-Path $indexFile) {

                $title = Get-Title $indexFile
                $slug  = Get-Slug $title

                $items += [PSCustomObject]@{
                    title    = $title
                    file     = "$relativePath/index.md"
                    slug     = $slug
                    children = @($children)
                    type     = 3
                }

            }
            else {

                # virtueller Ordner
                $title = $entry.Name
                $slug  = Get-Slug $title

                $items += [PSCustomObject]@{
                    title    = $title
                    file     = "$relativePath/index.md"
                    slug     = $slug
                    children = @($children)
                    type     = 2
                }
            }
        }

        # -----------------------------
        # MARKDOWN FILE
        # -----------------------------
        elseif ($entry.Extension -eq ".md") {

            if ($entry.Name -eq "index.md") {
                continue
            }

            $relativePath = [System.IO.Path]::GetRelativePath($BasePath, $entry.FullName)
            $relativePath = $relativePath -replace "\\","/"

            $title = Get-Title $entry.FullName
            $slug  = Get-Slug $title

            $items += [PSCustomObject]@{
                title    = $title
                file     = $relativePath
                slug     = $slug
                children = Get-SubTitles $entry.FullName
                type     = 1
            }
        }
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

            $children = $node.children | Where-Object { $_.type -ge 2 }
            if ($children.Count -gt 0) {
                Process-Tree -Nodes $node.children -CurrentPath $folder
            }
        }
    }
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
# Application Configruation
$appConfig = Join-Path $build "app.json"

# Output paths for generated Markdown files and navigation structure
$outMd = Join-Path $build $buildConf.environment.markdownFolder
$outSidebar = Join-Path $build $buildConf.environment.navigationFile


# Clean up the build directory
Write-Host "Cleaning up build directory..." -ForegroundColor Cyan
Remove-Item -Recurse -Force $outMd -ErrorAction Ignore | Out-Null
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
$tree |
    ConvertTo-Json -Depth 20 |
    Set-Content $outSidebar -Encoding UTF8

# --------------------------------------------------
# WRITE APPLICATION CONFIGURATION
# --------------------------------------------------
Write-Host "Writing application configuration to JSON..." -ForegroundColor Cyan
($buildConf | ConvertTo-Json -Depth 5) -replace "\\\\","/" | 
    Set-Content $appConfig -Encoding UTF8 
 
# --------------------------------------------------
# Build complete
# --------------------------------------------------
Write-Host "Build process completed successfully." -ForegroundColor Green
Start-Sleep -Seconds 5
exit