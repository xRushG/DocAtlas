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
#  INI file preperation
#--------------------------------------------------
function Read-IniFile {
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

function Set-DebugConfig {
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
    $config.debug | Add-Member -Name tree_default -Value "debug_tree.json" -MemberType NoteProperty
    $config.debug | Add-Member -Name navigation -Value "debug_nav.json" -MemberType NoteProperty
    $config.debug | Add-Member -Name globalSearchIndex -Value "debug_gsi.json" -MemberType NoteProperty
    $config.debug | Add-Member -Name searchIndexSufix -Value "debug_si_{0}.json" -MemberType NoteProperty
    $config.debug | Add-Member -Name appConfig -Value "debug_appConfig.json" -MemberType NoteProperty

    return $config
}

function Optimize-ConfigValues {
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

# --------------------------------------------------
#   Tree building and processing
# -------------------------------------------------
function Build-Tree {

    param(
        [Parameter(Mandatory)]
        [string]$BasePath
    )
    $IndexFileName = $buildConf.tableOfContents.name?.Trim() ?? "index.md"
    $indexFile = Join-Path $BasePath $IndexFileName

    $global:UsedSlugs = @{}

    $title = "Home"

    #$FullContent = ""
    $Content = @()

    if (Test-Path $indexFile) {
        $raw = Get-Content $indexFile -Raw
        #$FullContent = Get-CleanMarkdownContent -content $raw
        $Content = Split-MarkdownSections -Markdown $raw -Slug ""
        $title = Get-Title $indexFile
    }

    $children = Write-Tree -BasePath $BasePath -ParentSlug ""

    return [PSCustomObject]@{
        IndexFile    = $indexFile

        Title        = $title
        #$FullContent = $FullContent
        Content  = $Content

        Slug     = ""
        Children = $children
    }
}

function Write-Tree {
    param (
        [Parameter(Mandatory)]
        [string]$BasePath,
        [string]$ParentSlug = ""
    )

    # Invalid url chars
    $invalidChars = "[\(\)\[\]\{\}#?%&]"
    $IndexFileName = $buildConf.tableOfContents.name?.Trim() ?? "index.md"

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

            #$FullContent = ''
            $Content = @()

            $indexFileName = $buildConf.tableOfContents.name?.Trim() ?? "index.md"
            $indexFile = Join-Path $entry.FullName $indexFileName

            if (Test-Path $indexFile) {
                $title = Get-Title $indexFile

                $raw = Get-Content $indexFile -Raw
                #$FullContent = Get-CleanMarkdownContent -content $raw
                $Content = Split-MarkdownSections -Markdown $raw -Slug $slug

                if ([string]::IsNullOrWhiteSpace($title.toSTring())) {
                    $title = $entry.Name
                }
                $localSlug = Get-Slug $title
            }
            else {
                $title = $entry.Name
                $localSlug = Get-Slug $title
            }
            
            $slug = if ($ParentSlug) { "$ParentSlug/$localSlug" } else { $localSlug }
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

                Title    = $title
                #FullContent  = $FullContent
                Content = $Content
                Slug     = $slug
                Children = $children
            })    
        }
        elseif ($entry.Extension -eq '.md') {

            $raw = Get-Content $entry.FullName -Raw

            $title = Get-Title $entry.FullName

            $localSlug = Get-Slug $title
            $slug = if ($ParentSlug) { "$ParentSlug/$localSlug" } else { $localSlug }

            if ($global:UsedSlugs.ContainsKey($slug)) {
                Write-Error "Duplicate slug detected: '$slug' (File/Folder: $($entry.FullName))"
                Read-Host -Prompt "Press Enter to continue"
                exit
            }

            #$FullContent = Get-CleanMarkdownContent -content $raw
            $Content = Split-MarkdownSections -Markdown $raw -Slug $Slug

            $items.Add([PSCustomObject]@{
                File     = $entry.FullName

                Title    = $title
                #FullContent  = $FullContent
                Content = $Content
                Slug     = $slug
            })
        }
    }
    return $items

}

function Get-UniqueAnchor {
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
    param(
        [Parameter(Mandatory)]
        [string]$Markdown,
        [Parameter(Mandatory)]
        $Slug
    )

    $sections = @()
    $usedAnchors = @{}

    $currentHeader = $null
    $currentLevel = $null

    $buffer = New-Object System.Text.StringBuilder
    $id = 0

    $lines = $Markdown -split "`r?`n"
    $codeBlock = $false
    foreach ($line in $lines) {

        if ($line -match '^```') {
            $codeBlock = -not $codeBlock
        }

        if (-not $codeBlock -and $line -match '^(#{1,6})\s+(.*)') {

            if ($currentHeader) {
                $baseAnchor = Get-Slug $currentHeader
 
                $anchor = Get-UniqueAnchor -BaseAnchor $baseAnchor -UsedAnchors $usedAnchors
                $href = if ($id -eq 1) { $Slug } else { "$($Slug)::$($anchor)" }

                $sections += [PSCustomObject]@{
                    Id      = $id
                    Level   = $currentLevel
                    Slug    = $Slug
                    Anchor  = $anchor
                    Href    = $href
                    Headline = $currentHeader
                    Content  =  Get-CleanMarkdownContent -Content $($buffer.ToString().Trim())
                }
                $buffer.Clear() | Out-Null
            }

            $currentLevel  = $matches[1].Length
            $currentHeader = $matches[2].Trim()
            $id++
        }

        $buffer.AppendLine($line) | Out-Null
    }

    if ($currentHeader) {

        $baseAnchor = Get-Slug $currentHeader

        $anchor = Get-UniqueAnchor -BaseAnchor $baseAnchor -UsedAnchors $usedAnchors
        $href = if ($id -eq 1) { $Slug } else { "$($Slug)::$($anchor)" }

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
    param(
        [Parameter(Mandatory)]
        $nodes,
        $currentLevel = 0
    )
    $result = @()

    foreach ($n in $nodes) {
        if ($n.content) {
            foreach ($c in $n.Content) {
                $level = ($c.Level) + $currentLevel

                
                    $result += [PSCustomObject]@{
                        title = $c.Headline
                        href  = $c.Href
                        level = $level
                        file  = $n.File -replace [regex]::Escape("$scriptRoot\src\"), ''
                    }
                
            }
        }
        elseif ($n.children) {

            $level = $currentLevel + 1

            
                $result += [PSCustomObject]@{
                    title = $n.title
                    href  = $n.slug
                    level = $level
                    file = $n.IndexFile -replace [regex]::Escape("$scriptRoot\src\"), ''
                }
                $result += Build-Navigation $n.children -currentLevel $level
            
        }
    }

    return $result
}

function Build-TableOfContents {
    param(
        [array]$Entries,
        [int]$StartIndex
    )

    $Depth = $buildConf.tableOfContents.depth ?? 2

    $result = @()
	$test = $buildConf.tableOfContents.Headline
    $result += "# $($test.Trim())`n"
    $result += "`n"

    $baseLevel = $Entries[$StartIndex].level

    for ($i = $StartIndex + 1; $i -lt $Entries.Count; $i++) {

        $entry = $Entries[$i]

        if ($entry.level -le $baseLevel) {
            break
        }

        $relLevel = $entry.level - $baseLevel

        if ($relLevel -gt $Depth) {
            continue
        }

        $indent = "  " * ($relLevel - 1)

        $line = "$indent- [$($entry.title)](#$($entry.href))"
        $result += $line
    }

    return $result
}

function Build-SearchIndex {
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
                    text = $c.Content
                }
            }
        }
        elseif ($n.children) {
            $result += [PSCustomObject]@{
                title = $n.title
                href  = $n.slug
                text = $c.Content
            }
            $result += Build-SearchIndex $n.children
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
$ParseConf = Read-IniFile -Path $ini
if ($ParseConf.debug.enabled) {
    Write-Host "Debug mode is enabled. Preparing debug configuration..." -ForegroundColor RED
}
$ParseConf = Set-DebugConfig -config $ParseConf -SCRIPT_ROOT $scriptRoot
$buildConf = $ParseConf | Optimize-ConfigValues

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
    Write-Host "[Debug] Creating debug output directory..." -ForegroundColor Gray
    Write-Host "$("   " * 2)'$outDebug'" -ForegroundColor DarkMagenta
    New-Item -ItemType Directory -Path $outDebug | Out-Null
}

# --------------------------------------------------
# SCAN SRC and Build Tree Structure
# --------------------------------------------------
Write-Host "Scanning source directory and building tree structure..." -ForegroundColor Cyan
$tree = Build-Tree -BasePath $src

if ($buildConf.debug.enabled) {
    Write-Host "[Debug]  $("   " * 1) Writing tree structure to JSON..." -ForegroundColor Gray
    $tree | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $outDebug $buildConf.debug.tree_default) -Encoding UTF8
    Write-Host "[Debug] $("   " * 2) Build tree structure complete." -ForegroundColor DarkGreen
}

if ($null -eq $tree) {
    Write-Error "No valid Markdown files found in the source directory. Build process aborted." -ForegroundColor DarkRed
    Read-Host -Prompt "Press Enter to exit"
    exit
}

# --------------------------------------------------
# COPY SOURCE FILES
# --------------------------------------------------
Write-Host "Copying source files to build directory..." -ForegroundColor Cyan
Copy-Files -Source $src -Destination $outMd

if ($buildConf.debug.enabled) {
    Write-Host "[Debug]  $("   " * 1) Source files copied to" -ForegroundColor Gray
    Write-Host "$("   " * 2) '$outMD'" -ForegroundColor DarkMagenta
}

# --------------------------------------------------
# WRITE NAVIGATION
# --------------------------------------------------
Write-Host "Writing navigation structure to JSON..." -ForegroundColor Cyan
$nav = ,@(Build-Navigation $tree)

if ($buildConf.debug.enabled) {
    Write-Host "[Debug] $("   " * 1) Writing debug navigation structure to JSON..." -ForegroundColor Gray
    $nav | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $outDebug $buildConf.debug.navigation) -Encoding UTF8
    Write-Host "[Debug] $("   " * 2) Debug navigation structure complete." -ForegroundColor Gray

}

$nav |
    ConvertTo-Json -Depth 20 |
    Set-Content $outNavIndex -Encoding UTF8

if ($buildConf.debug.enabled) {
    Write-Host "[Debug] $("   " * 1) Navigation files generated." -ForegroundColor DarkGreen
}

# --------------------------------------------------
# GENERATE INDEX FILES (Table of Contents)
# --------------------------------------------------
if ($buildConf.tableOfContents.enabled) {
    Write-Host "Generating table of content files..." -ForegroundColor Cyan
    $tocCollection = $nav[0]
    for ($i = 0; $i -lt $tocCollection.Count; $i++) {

        if ($tocCollection[$i].file -like "*TableOfContent.md") {
            $indexFile = Join-Path $outMD $tocCollection[$i].file
            if ($buildConf.debug.enabled) {
                Write-Host "[Debug] $("   " * 1) Write table of content:" -ForegroundColor Gray
                Write-Host "$("   " * 2) '$indexFile'" -ForegroundColor DarkMagenta
            }

            Build-TableOfContents -Entries $tocCollection -StartIndex $i -Depth 2
                | Set-Content $indexFile -Encoding UTF8

            if ($buildConf.debug.enabled) {
                Write-Host "[Debug] $("   " * 1) Table of content generated." -ForegroundColor DarkGreen
            }
        }
    }


    if ($buildConf.debug.enabled) {
        Write-Host "[Debug] Table of content files generated." -ForegroundColor DarkGreen
    }
}

# --------------------------------------------------
# WRITE Search-Index
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
# WRITE APPLICATION CONFIGURATION
# --------------------------------------------------
Write-Host "Writing application configuration to JSON..." -ForegroundColor Cyan
$appConfig = @{}

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

($appConfig | ConvertTo-Json -Depth 5) -replace "\\\\","/" | 
    Set-Content $outAppConfig -Encoding UTF8 
 
if ($buildConf.debug.enabled) {
    Write-Host "[Debug] $("   " * 1) Application configuration files generated." -ForegroundColor DarkGreen
}
# --------------------------------------------------
# Build complete
# --------------------------------------------------
Write-Host "Build process completed successfully." -ForegroundColor Green

if (-not $buildConf.debug.enabled) {
    Start-Sleep -Seconds 5
}
exit