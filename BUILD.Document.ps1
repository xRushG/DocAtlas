#Requires -Version 7.0
<#
.SYNOPSIS
    DocAtlas Document Export (PDF) — V2

.DESCRIPTION
    Opens a GUI that lets you pick any combination of headings from the src/
    Markdown files, configure a logo, page numbers and page layout, and export
    the selection as a single print-ready PDF via Edge headless.
    All settings are persisted in build.ini [document] and reloaded on next run.
#>
param()

# ══════════════════════════════════════════════════════════════════════════════
# 0 — BOOTSTRAP
# ══════════════════════════════════════════════════════════════════════════════

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        "This script requires PowerShell 7 (pwsh).`nPlease run it in a PowerShell 7 session.",
        "DocAtlas Export", 'OK', 'Error') | Out-Null
    exit 1
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ProjectRoot = $PSScriptRoot
Import-Module (Join-Path $ProjectRoot "res\DocAtlasMarkdown.psm1") -Force

# ══════════════════════════════════════════════════════════════════════════════
# 0.5 — CONFIG  (mirrors build.ps1 Read-IniFile pattern)
# ══════════════════════════════════════════════════════════════════════════════

$IniPath = Join-Path $ProjectRoot "build.ini"

function Read-IniFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { Throw "File not found: $Path" }

    $rawLines = Get-Content -LiteralPath $Path -Raw
    $noBlockComments = [regex]::Replace(
        $rawLines, '/\*.*?\*/', '',
        [System.Text.RegularExpressions.RegexOptions]::Singleline)

    $lines = $noBlockComments -split "`r?`n" |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $lines = $lines | ForEach-Object { ($_ -replace '//.*$', '').Trim() } | Where-Object { $_ }

    $iniData        = @{}
    $currentSection = $null

    switch -regex ($lines) {
        '^\s*\[(.+?)\]\s*$' {
            $currentSection = $matches[1].Trim()
            if (-not $iniData.ContainsKey($currentSection)) { $iniData[$currentSection] = @{} }
            continue
        }
        '^\s*([^=]+?)\s*=\s*(.+?)\s*$' {
            if (-not $currentSection) { Throw "Key/value pair outside section: '$_'" }
            $key   = $matches[1].Trim()
            $value = $matches[2].Trim()
            if ($value -match '^"(.*)"$') { $value = $matches[1] }
            switch -regex ($value) {
                '^true$'      { $value = $true }
                '^false$'     { $value = $false }
                '^\d+$'       { $value = [int]$value }
                '^\d+\.\d+$'  { $value = [double]$value }
            }
            $iniData[$currentSection][$key] = $value
        }
    }

    Write-Output ($iniData | ConvertTo-Json | ConvertFrom-Json)
}

function Get-DocumentConfig {
    param($IniConfig)

    $doc  = $IniConfig.document
    $dbg  = $IniConfig.debug
    $toc  = $IniConfig.tableOfContents
    $logo = $IniConfig.logo

    # Resolve [logo] document → absolute filesystem path for the PDF default
    $logoDocPath = $null
    if (-not [string]::IsNullOrWhiteSpace($logo.document)) {
        $rel       = ($logo.document -replace '/', '\').TrimStart('\')
        $candidate = Join-Path $ProjectRoot ("res\" + $rel)
        if (Test-Path -LiteralPath $candidate) { $logoDocPath = $candidate }
    }

    # Always produce an absolute path — resolve relative entries against $ProjectRoot
    $rawLogoPath = $doc.LogoPath ? [string]$doc.LogoPath :
                   $logoDocPath  ? $logoDocPath           :
                   (Join-Path $ProjectRoot "res\assets\logo-light.svg")
    $absLogoPath = if ([System.IO.Path]::IsPathRooted($rawLogoPath)) { $rawLogoPath }
                   else { Join-Path $ProjectRoot $rawLogoPath }

    $rawStylePath = ![string]::IsNullOrWhiteSpace($doc.Style) ? [string]$doc.Style : 'res\Document\StylesOverrides.css'
    $absStylePath = if ([System.IO.Path]::IsPathRooted($rawStylePath)) { $rawStylePath }
                    else { Join-Path $ProjectRoot $rawStylePath }

    @{
        Logo               = $null -ne $doc?.Logo ? [bool]$doc.Logo : $true
        LogoAllPages       = $null -ne $doc?.LogoAllPages ? [bool]$doc.LogoAllPages : $false
        LogoPath           = $absLogoPath
        LogoPosition       = $doc.LogoPosition       ? $doc.LogoPosition : 'Right'
        PageNumbers        = $null -ne $doc?.PageNumbers ? [bool]$doc.PageNumbers : $true
        PageNumberPosition = $doc.PageNumberPosition ? $doc.PageNumberPosition : 'Center'

        OutputDirectory    = $doc?.OutputDirectory `
            ? (($doc.OutputDirectory -replace '%ScriptRoot%', $ProjectRoot))
            : (Join-Path $ProjectRoot "documents")

        HeaderHeight       = $null -ne $doc.HeaderHeight ? [double]$doc.HeaderHeight : 2.0
        FooterHeight       = $null -ne $doc.FooterHeight ? [double]$doc.FooterHeight : 1.0

        MarginTop          = $null -ne $doc.MarginTop ? [double]$doc.MarginTop : 1.0
        MarginTopFirst     = $null -ne $doc.MarginTopFirst ? [double]$doc.MarginTopFirst : 1.0
        MarginBottom       = $null -ne $doc.MarginBottom ? [double]$doc.MarginBottom : 1.0
        MarginLeft         = $null -ne $doc.MarginLeft ? [double]$doc.MarginLeft : 1.0
        MarginRight        = $null -ne $doc.MarginRight ? [double]$doc.MarginRight : 1.0

        Orientation        = $doc.Orientation ? $doc.Orientation : 'Portrait'

        LogoWidth          = $null -ne $doc.LogoWidth ? [double]$doc.LogoWidth : 5.0
        LogoHeight         = $null -ne $doc.LogoHeight ? [double]$doc.LogoHeight : 1.5

        StyleOverridePath  = $absStylePath

        TocHeadline        = $toc.Headline ? [string]$toc.Headline : 'Table of Contents'

        DebugEnabled       = $null -ne $dbg.enabled ? [bool]$dbg.enabled : $false
        OutputPath         = ![string]::IsNullOrWhiteSpace($dbg.outputPath) ? $dbg.outputPath : 'debug'
    }
}

function Write-IniSection {
    param(
        [string] $Path,
        [string] $SectionName,
        [System.Collections.Specialized.OrderedDictionary] $Values
    )

    $raw         = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $escapedName = [regex]::Escape($SectionName)
    $raw         = [regex]::Replace($raw, "(?ms)\[$escapedName\][^\[]*", '').TrimEnd()

    $sb = [System.Text.StringBuilder]::new()
    $sb.Append("`r`n`r`n[$SectionName]`r`n") | Out-Null
    foreach ($kv in $Values.GetEnumerator()) {
        $sb.Append("$($kv.Key)=$($kv.Value)`r`n") | Out-Null
    }

    Set-Content -LiteralPath $Path -Value ($raw + $sb.ToString()) -Encoding UTF8 -NoNewline
}

function Save-DocumentConfig {
    param(
        [bool]   $Logo,
        [bool]   $LogoAllPages,
        [string] $LogoPath,
        [string] $LogoPosition,
        [bool]   $PageNumbers,
        [string] $PageNumberPosition,
        [string] $OutputDirectory,
        [double] $HeaderHeight,
        [double] $FooterHeight,
        [double] $MarginTop,
        [double] $MarginTopFirst,
        [double] $MarginBottom,
        [double] $MarginLeft,
        [double] $MarginRight,
        [string] $Orientation,
        [double] $LogoWidth,
        [double] $LogoHeight
    )

    $ic = [System.Globalization.CultureInfo]::InvariantCulture

    $values = [ordered]@{
        Logo               = if ($Logo)         { 'true' } else { 'false' }
        LogoAllPages       = if ($LogoAllPages)  { 'true' } else { 'false' }
        LogoPath           = $LogoPath
        LogoPosition       = $LogoPosition
        LogoWidth          = $LogoWidth.ToString($ic)
        LogoHeight         = $LogoHeight.ToString($ic)
        PageNumbers        = if ($PageNumbers) { 'true' } else { 'false' }
        PageNumberPosition = $PageNumberPosition
        OutputDirectory    = $OutputDirectory
        HeaderHeight       = $HeaderHeight.ToString($ic)
        FooterHeight       = $FooterHeight.ToString($ic)
        MarginTop          = $MarginTop.ToString($ic)
        MarginTopFirst     = $MarginTopFirst.ToString($ic)
        MarginBottom       = $MarginBottom.ToString($ic)
        MarginLeft         = $MarginLeft.ToString($ic)
        MarginRight        = $MarginRight.ToString($ic)
        Orientation        = $Orientation
    }

    Write-IniSection -Path $IniPath -SectionName 'document' -Values $values
}

# Sync build.ini against template (create if missing, add new keys, flag deprecated)
. (Join-Path $ProjectRoot "res\Sync-BuildIni.ps1")
Sync-BuildIni `
    -IniPath      $IniPath `
    -TemplatePath (Join-Path $ProjectRoot "res\build.ini.tmpl") `
    -UseGui

# Read config at startup
try   { $iniCfg = Read-IniFile -Path $IniPath }
catch { $iniCfg = $null }
$script:cfg = Get-DocumentConfig -IniConfig $iniCfg

# ══════════════════════════════════════════════════════════════════════════════
# 1 — HTML HELPERS
# ══════════════════════════════════════════════════════════════════════════════

function Get-HtmlFileSections {
    <#  Splits a built HTML file into sections by heading.
        Each section carries its Level, display Text, anchor Id, and the raw
        HtmlContent (from that heading to the start of the next heading). #>
    param([string]$FilePath)

    $raw  = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8
    $opts = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
            [System.Text.RegularExpressions.RegexOptions]::Singleline

    # Match every heading tag (captures tag name + full opening tag)
    # Closing uses </\1> not </h\1> — group 1 already contains "h1","h2",…
    $headRx = [regex]::new('<(h[1-6])([^>]*)>(.*?)</\1>', $opts)
    $tagRx  = [regex]'<[^>]+>'
    $idRx   = [regex]'id="([^"]*)"'

    $headMatches = @($headRx.Matches($raw))
    $secs        = [System.Collections.Generic.List[hashtable]]::new()

    for ($i = 0; $i -lt $headMatches.Count; $i++) {
        $m     = $headMatches[$i]
        $level = [int]($m.Groups[1].Value.Substring(1))   # h1→1 … h6→6
        $attrs = $m.Groups[2].Value
        $inner = $m.Groups[3].Value
        $text  = $tagRx.Replace($inner, '').Trim()

        $idMatch = $idRx.Match($attrs)
        $id      = if ($idMatch.Success) { $idMatch.Groups[1].Value } else { "s$i" }

        $start       = $m.Index
        $end         = if ($i + 1 -lt $headMatches.Count) { $headMatches[$i+1].Index } else { $raw.Length }
        $htmlContent = $raw.Substring($start, $end - $start).Trim()

        $secs.Add(@{
            IsFile      = $false
            File        = $FilePath
            Level       = $level
            Text        = $text
            Id          = $id
            HtmlContent = $htmlContent
        })
    }
    # -NoEnumerate prevents PowerShell from unrolling a 1-item list to a bare
    # hashtable, which would break the [List[hashtable]] parameter binding.
    Write-Output -NoEnumerate $secs
}

function Resolve-HtmlImagePaths {
    <#  Rewrites relative img src attributes to absolute file:// paths so that
        Edge headless can resolve them from the temp HTML file. #>
    param([string]$HtmlContent, [string]$SourceDir)

    $rx = [regex]'(<img\b[^>]+\bsrc=")([^"]+)(")'
    return $rx.Replace($HtmlContent, {
        param([System.Text.RegularExpressions.Match]$m)
        $src = $m.Groups[2].Value
        if ($src -match '^(https?://|data:|//)' -or [System.IO.Path]::IsPathRooted($src)) {
            return $m.Value
        }
        $abs = [System.IO.Path]::GetFullPath((Join-Path $SourceDir $src))
        return $m.Groups[1].Value + $abs.Replace('\', '/') + $m.Groups[3].Value
    })
}

function Get-InlinedCss {
    <#  Reads every CSS file in CssPaths, strips @import statements (all
        referenced files are already passed in directly), and returns one
        concatenated string ready for a <style> block. #>
    param([string[]]$CssPaths)

    # Matches any @import line regardless of url()/string/media-query variant
    $importRx = [regex]'@import\b[^;]+;?'

    $sb = [System.Text.StringBuilder]::new()
    foreach ($p in $CssPaths) {
        if (-not $p -or -not (Test-Path -LiteralPath $p)) { continue }
        $content = Get-Content -LiteralPath $p -Raw -Encoding UTF8
        $content = $importRx.Replace($content, '')   # strip redundant @imports
        $sb.AppendLine($content) | Out-Null
    }
    return $sb.ToString()
}

function Encode-Html {
    param([string]$Text)
    return $Text.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;')
}

# ══════════════════════════════════════════════════════════════════════════════
# 2 — TREE HELPERS
# ══════════════════════════════════════════════════════════════════════════════

function Add-FileToTree {
    param(
        $Parent,    # System.Windows.Forms.TreeView  OR  System.Windows.Forms.TreeNode
        $TreeFont,  # System.Drawing.Font — used for bold heading nodes
        $MdFile,
        [System.Collections.Generic.List[hashtable]]$Sections
    )

    if ($Sections.Count -eq 0) { return }

    # Determine the minimum heading level in this file so that level becomes the
    # top-level tree entry (handles files that start with h2 instead of h1).
    $minLevel = ($Sections | Measure-Object -Property Level -Minimum).Minimum

    $byLevel = @{}
    foreach ($sec in $Sections) {
        $node         = New-Object System.Windows.Forms.TreeNode
        $node.Text    = $sec.Text
        $node.Checked = $true
        $node.Tag     = $sec

        # Top-level headings (h1 or whatever the file starts with) → bold
        if ($sec.Level -eq $minLevel) {
            $node.NodeFont = New-Object System.Drawing.Font(
                $TreeFont.FontFamily, $TreeFont.Size, [System.Drawing.FontStyle]::Bold)
        }

        # Walk up to find the nearest parent node
        $parentNode = $null
        for ($l = $sec.Level - 1; $l -ge 1; $l--) {
            if ($byLevel.ContainsKey($l)) { $parentNode = $byLevel[$l]; break }
        }

        if ($parentNode) { $parentNode.Nodes.Add($node) | Out-Null }
        else             { $Parent.Nodes.Add($node) | Out-Null }

        $byLevel[$sec.Level] = $node
        @($byLevel.Keys | Where-Object { $_ -gt $sec.Level }) |
            ForEach-Object { $byLevel.Remove($_) }
    }
}

function Set-NodeCheckState {
    param($Node, [bool]$Checked)
    foreach ($child in $Node.Nodes) {
        $child.Checked = $Checked
        Set-NodeCheckState -Node $child -Checked $Checked
    }
}

function Collect-TreeSections {
    param($Node, [System.Collections.Generic.List[hashtable]]$Accumulator)
    if ($Node.Tag -and -not $Node.Tag.IsFile -and $Node.Checked) {
        $Accumulator.Add($Node.Tag) | Out-Null
    }
    foreach ($child in $Node.Nodes) {
        Collect-TreeSections -Node $child -Accumulator $Accumulator
    }
}

function Get-SelectedSections {
    param($TreeView)
    $list = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($fileNode in $TreeView.Nodes) {
        Collect-TreeSections -Node $fileNode -Accumulator $list
    }
    Write-Output -NoEnumerate $list
}

# ══════════════════════════════════════════════════════════════════════════════
# 3 — PDF BUILD
# ══════════════════════════════════════════════════════════════════════════════

function Find-EdgeExe {
    $candidates = @(
        'msedge',
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    )
    foreach ($c in $candidates) {
        if ($c -eq 'msedge') {
            if (Get-Command msedge -ErrorAction SilentlyContinue) { return 'msedge' }
        } elseif (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function Build-PrintHtml {
    <#  Assembles a print-ready HTML file from already-built HTML sections.
        The built CSS is inlined so that Edge headless produces a fully styled PDF. #>
    param(
        [System.Collections.Generic.List[hashtable]] $Sections,
        [bool]   $Logo          = $true,
        [bool]   $LogoAllPages  = $false,
        [string] $LogoPath,
        [string] $LogoPosition,   # left | center | right | none
        [bool]   $PageNumbers,
        [string] $PageNumberPos,  # left | center | right
        [string] $OutputPath,
        [string] $InlinedCss,     # pre-loaded CSS from html/css/ + highlight
        [string] $Orientation    = 'Portrait',
        [double] $MarginTop      = 1.0,
        [double] $MarginTopFirst = 1.0,
        [double] $MarginBottom   = 1.0,
        [double] $MarginLeft     = 1.0,
        [double] $MarginRight    = 1.0,
        [double] $HeaderHeight   = 2.0,
        [double] $FooterHeight   = 1.0,
        [double] $LogoWidth      = 5.0,
        [double] $LogoHeight     = 1.5,
        [string] $TocHeadline   = 'Table of Contents',
        [string] $DocTitle      = '',
        [string] $PdfTitle      = '',
        [string] $OverrideCss   = ''
    )

    # ── Assemble HTML content from already-built sections ──────────────────
    $fragSb = [System.Text.StringBuilder]::new()
    foreach ($s in $Sections) {
        $srcDir = [System.IO.Path]::GetDirectoryName($s.File)
        $html   = Resolve-HtmlImagePaths -HtmlContent $s.HtmlContent -SourceDir $srcDir
        $fragSb.AppendLine($html) | Out-Null
    }
    $frag = $fragSb.ToString()

    # ── Build TOC from section metadata ───────────────────────────────────
    $tocSb = [System.Text.StringBuilder]::new()
    $tocSb.AppendLine('<nav class="da-toc">') | Out-Null
    $tocSb.AppendLine("<p class=""da-toc-title"">$TocHeadline</p>") | Out-Null
    $tocSb.AppendLine('<ul>') | Out-Null
    foreach ($s in $Sections) {
        $tocSb.AppendLine("<li class=""da-toc-h$($s.Level)""><a href=""#$($s.Id)"">$(Encode-Html $s.Text)</a></li>") | Out-Null
    }
    $tocSb.AppendLine('</ul>') | Out-Null
    $tocSb.AppendLine('</nav>') | Out-Null

    # ── Logo ──────────────────────────────────────────────────────────────
    $ic        = [System.Globalization.CultureInfo]::InvariantCulture
    $logoHtml  = ''
    $headerCss = ''
    # Header height: auto-expand to fit logo
    $effHdrH   = [Math]::Max($HeaderHeight, $LogoHeight)

    $showLogo  = $Logo -and ($LogoPosition -ne 'none') -and $LogoPath -and (Test-Path -LiteralPath $LogoPath)
    if ($showLogo) {
        $ext  = [System.IO.Path]::GetExtension($LogoPath).ToLower().TrimStart('.')
        $mime = switch ($ext) { 'svg' { 'image/svg+xml' } 'jpg' { 'image/jpeg' } 'jpeg' { 'image/jpeg' } default { 'image/png' } }
        $b64  = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($LogoPath))

        $justify  = switch ($LogoPosition.ToLower()) { 'left' { 'flex-start' } 'center' { 'center' } default { 'flex-end' } }
        $hdrHStr  = $effHdrH.ToString($ic)
        $logoWStr = $LogoWidth.ToString($ic)
        $logoHStr = $LogoHeight.ToString($ic)

        $logoHtml = "<div class=""da-header""><img class=""da-logo"" src=""data:$mime;base64,$b64"" alt=""Logo"" /></div>"

        if ($LogoAllPages) {
            # position:fixed repeats the header on every page.
            # top: -hdrH moves the header up into the @page margin area
            # (@page margin-top = MarginTop + effHdrH, so content starts below).
            $headerCss = @"
.da-header {
  position: fixed !important;
  top: -${hdrHStr}cm !important;
  left: 0 !important;
  right: 0 !important;
  width: 100% !important;
  height: ${hdrHStr}cm !important;
  display: flex !important;
  align-items: flex-start !important;
  justify-content: $justify !important;
  padding: 0 !important;
  margin: 0 !important;
  box-sizing: border-box;
  background: white !important;
}
.da-logo {
  width: ${logoWStr}cm !important;
  height: ${logoHStr}cm !important;
  max-width: none !important;
  max-height: none !important;
  object-fit: contain !important;
  display: block !important;
  margin: 0 !important;
}
"@
        } else {
            # in-flow: logo appears only on the first page
            $headerCss = @"
.da-header {
  width: 100% !important;
  height: ${hdrHStr}cm !important;
  display: flex !important;
  align-items: flex-start !important;
  justify-content: $justify !important;
  padding: 0 !important;
  margin: 0 !important;
  page-break-after: avoid;
  box-sizing: border-box;
}
.da-logo {
  width: ${logoWStr}cm !important;
  height: ${logoHStr}cm !important;
  max-width: none !important;
  max-height: none !important;
  object-fit: contain !important;
  display: block !important;
  margin: 0 !important;
}
"@
        }
    }

    # ── Page numbers ──────────────────────────────────────────────────────
    $pageNumCss = ''
    if ($PageNumbers) {
        $box = switch ($PageNumberPos.ToLower()) { 'left' { '@bottom-left' } 'right' { '@bottom-right' } default { '@bottom-center' } }
        $pageNumCss = "@page { $box { content: counter(page); font-size: 9pt; color: #555; } }"
    }

    # ── @page layout ──────────────────────────────────────────────────────
    # LogoAllPages: top margin grows by header height so content never overlaps the fixed header
    if ($showLogo -and $LogoAllPages) {
        $effTop      = [Math]::Round($MarginTop + $effHdrH, 2).ToString($ic)
        $firstPageCss = ''   # no :first distinction — all pages have the same header
    } else {
        $effTop      = $MarginTop.ToString($ic)
        $firstPageCss = "@page :first { margin-top: $($MarginTopFirst.ToString($ic))cm; }"
    }
    $effBottom = [Math]::Round($MarginBottom + $FooterHeight, 2).ToString($ic)
    $mLeft     = $MarginLeft.ToString($ic)
    $mRight    = $MarginRight.ToString($ic)
    $pageSize  = "A4 $(if ($Orientation -eq 'Landscape') { 'landscape' } else { 'portrait' })"

    # ── Document title (optional — rendered above TOC) ───────────────────
    $titleHtml = if (-not [string]::IsNullOrWhiteSpace($DocTitle)) {
        "<div class=""da-doc-title"">$(Encode-Html $DocTitle)</div>"
    } else { '' }

    # ── Full HTML (inlined CSS + print overrides + content) ───────────────
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>$(Encode-Html $PdfTitle)</title>
<style>
/* ════ Inlined build CSS ════ */
$InlinedCss

/* ════ Print layout ════ */
@page { size: $pageSize; margin: ${effTop}cm ${mRight}cm ${effBottom}cm ${mLeft}cm; }
$firstPageCss
$pageNumCss

$OverrideCss

/* ════ Logo / Header ════ */
$headerCss
</style>
</head>
<body>
$logoHtml
$titleHtml
$($tocSb.ToString())
<div id="da-content-div" class="da-content">
$frag
</div>
<script>document.querySelectorAll('details').forEach(function(d){d.open=true;});</script>
</body>
</html>
"@

    $html | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}

# ══════════════════════════════════════════════════════════════════════════════
# 4 — INITIALISE (scan built html/ output)
# ══════════════════════════════════════════════════════════════════════════════

# Resolve build-folder paths from build.ini [environment]
$env_      = $iniCfg?.environment
$bFolder   = if ($env_?.buildFolder)   { [string]$env_.buildFolder   } else { 'html' }
$sSuffix   = if ($env_?.sitesFolder)   { [string]$env_.sitesFolder   } else { 'sites' }
$cssSuffix = if ($env_?.cssFolder)     { [string]$env_.cssFolder     } else { 'css' }
$libSuffix = if ($env_?.libFolder)     { [string]$env_.libFolder     } else { 'lib' }

$buildDir  = Join-Path $ProjectRoot $bFolder
$sitesDir  = Join-Path $buildDir    $sSuffix
$cssDir    = Join-Path $buildDir    $cssSuffix
$libDir    = Join-Path $buildDir    $libSuffix

# ── Build check ───────────────────────────────────────────────────────────
$buildScript = Join-Path $ProjectRoot 'build.ps1'

function Invoke-Build {
    $proc = Start-Process pwsh `
        -ArgumentList "-ExecutionPolicy Bypass -File `"$buildScript`"" `
        -WorkingDirectory $ProjectRoot `
        -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "build.ps1 failed (exit code $($proc.ExitCode)).`nExport aborted.",
            "DocAtlas Export — Build Error", 'OK', 'Error') | Out-Null
        exit 1
    }
}

if (Test-Path $buildDir) {
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Ein vorhandener Build wurde gefunden:`n$buildDir`n`nBuild jetzt neu erstellen?",
        "DocAtlas Export — Rebuild?", 'YesNo', 'Question')
    if ($answer -eq 'Yes') { Invoke-Build }
} else {
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Kein Build-Output gefunden.`nJetzt build.ps1 ausführen?",
        "DocAtlas Export — Kein Build", 'YesNo', 'Question')
    if ($answer -eq 'Yes') { Invoke-Build }
    else {
        [System.Windows.Forms.MessageBox]::Show(
            "Ohne Build kann kein Export erstellt werden.",
            "DocAtlas Export", 'OK', 'Warning') | Out-Null
        exit 0
    }
}

if (-not (Test-Path $sitesDir)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Build-Output unvollständig:`n$sitesDir fehlt.`n`nBitte build.ps1 erneut ausführen.",
        "DocAtlas Export", 'OK', 'Error') | Out-Null
    exit 1
}

# The TOC file name is configured in build.ini [tableOfContents] name
$tocFileName = if ($iniCfg?.tableOfContents?.name) { [string]$iniCfg.tableOfContents.name } else { 'TableOfContent.html' }

$htmlFiles = @(
    Get-ChildItem -LiteralPath $sitesDir -Recurse -Filter "*.html" |
        Where-Object { $_.Name -ne $tocFileName } |
        Sort-Object FullName
)
if ($htmlFiles.Count -eq 0) {
    [System.Windows.Forms.MessageBox]::Show(
        "No HTML files found in:`n$sitesDir`n`nRun build.ps1 first.",
        "DocAtlas Export", 'OK', 'Warning') | Out-Null
    exit 1
}

$allSections = @{}
foreach ($f in $htmlFiles) {
    $allSections[$f.FullName] = Get-HtmlFileSections -FilePath $f.FullName
}

# Collect CSS: prefer built html/css/, fall back to res/css/ source
$resDir    = Join-Path $ProjectRoot 'res'
$resCssDir = Join-Path $resDir $cssSuffix
$resLibDir = Join-Path $resDir $libSuffix

$effectiveCssDir = if ((Get-ChildItem -LiteralPath $cssDir -Filter '*.css' -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) {
    $cssDir
} else {
    $resCssDir   # build hasn't copied CSS yet — use source directly
}

$effectiveLibDir = if (Test-Path (Join-Path $libDir 'highlight.min.css')) { $libDir } else { $resLibDir }

$cssPaths = [System.Collections.Generic.List[string]]::new()
Get-ChildItem -LiteralPath $effectiveCssDir -Filter '*.css' -ErrorAction SilentlyContinue |
    Sort-Object Name |
    ForEach-Object { $cssPaths.Add($_.FullName) }
$hlCss = Join-Path $effectiveLibDir 'highlight.min.css'
if (Test-Path $hlCss) { $cssPaths.Add($hlCss) }

$script:inlinedCss = Get-InlinedCss -CssPaths $cssPaths

$script:overrideCss = if (Test-Path -LiteralPath $script:cfg.StyleOverridePath) {
    Get-Content -LiteralPath $script:cfg.StyleOverridePath -Raw -Encoding UTF8
} else { '' }

# Build a slug → display title map by parsing the nav-item divs in html/index.html.
# Each folder has a nav entry whose data-file points to its TableOfContent.html;
# the div's text content is the human-readable project name shown in the nav.
# This lets folder nodes in the TreeView use the same titles as the HTML navigation.
$script:folderTitleMap = @{}
$mainIndexHtml = Join-Path $buildDir 'index.html'
if (Test-Path -LiteralPath $mainIndexHtml) {
    $navContent  = Get-Content -LiteralPath $mainIndexHtml -Raw -Encoding UTF8
    $tocEscaped  = [regex]::Escape($tocFileName)
    $folderNavRx = [regex]"data-file=""([^""]*[/\\]$tocEscaped)""[^>]*>([^<]+)<"
    foreach ($m in $folderNavRx.Matches($navContent)) {
        $relFile = $m.Groups[1].Value.Replace('/', '\').TrimStart('\')
        $title   = $m.Groups[2].Value.Trim()
        if ($relFile -and $title) { $script:folderTitleMap[$relFile.ToLower()] = $title }
    }
}

# No logo path resolved → disable logo rather than guess a file
if ([string]::IsNullOrWhiteSpace($script:cfg.LogoPath)) {
    $script:cfg.Logo = $false
}

# Default document name: first H1 found across all loaded files (file order)
$script:defaultDocName = 'document'
foreach ($f in $htmlFiles) {
    $h1 = $allSections[$f.FullName] | Where-Object { $_.Level -eq 1 } | Select-Object -First 1
    if ($h1) {
        $raw = $h1.Text
        $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
        foreach ($ch in $invalidChars) { $raw = $raw.Replace([string]$ch, '_') }
        $raw = $raw.Trim('_').Trim()
        if (-not [string]::IsNullOrWhiteSpace($raw)) { $script:defaultDocName = $raw }
        break
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# 5 — GUI
# ══════════════════════════════════════════════════════════════════════════════

#[System.Windows.Forms.Application]::EnableVisualStyles()
#[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

$form             = New-Object System.Windows.Forms.Form
$form.Text        = "DocAtlas — Document Export  (PDF)"
$form.ClientSize  = New-Object System.Drawing.Size(620, 830)
$form.MinimumSize = New-Object System.Drawing.Size(500, 720)
$form.StartPosition = "CenterScreen"
$form.Font        = New-Object System.Drawing.Font("Segoe UI", 9)

# ── Document Settings GroupBox ────────────────────────────────────────────

$grpSettings          = New-Object System.Windows.Forms.GroupBox
$grpSettings.Text     = " Document Settings "
$grpSettings.Location = New-Object System.Drawing.Point(10, 10)
$grpSettings.Size     = New-Object System.Drawing.Size(600, 156)
$grpSettings.Anchor   = "Top, Left, Right"

$lblLogo           = New-Object System.Windows.Forms.Label
$lblLogo.Text      = "Logo:"
$lblLogo.Location  = New-Object System.Drawing.Point(10, 24)
$lblLogo.Size      = New-Object System.Drawing.Size(44, 22)
$lblLogo.TextAlign = "MiddleRight"

$txtLogo          = New-Object System.Windows.Forms.TextBox
$txtLogo.Location = New-Object System.Drawing.Point(58, 22)
$txtLogo.Size     = New-Object System.Drawing.Size(380, 22)
$txtLogo.Anchor   = "Top, Left"
$txtLogo.Text     = $script:cfg.LogoPath

$btnBrowseLogo          = New-Object System.Windows.Forms.Button
$btnBrowseLogo.Text     = "..."
$btnBrowseLogo.Location = New-Object System.Drawing.Point(442, 21)
$btnBrowseLogo.Size     = New-Object System.Drawing.Size(34, 24)
$btnBrowseLogo.Anchor   = "Top, Left"
$btnBrowseLogo.Add_Click({
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Filter = "Image Files|*.png;*.jpg;*.jpeg;*.svg"
    $d.Title  = "Select Logo Image"
    if ($d.ShowDialog() -eq 'OK') { $txtLogo.Text = $d.FileName }
})

$chkLogo          = New-Object System.Windows.Forms.CheckBox
$chkLogo.Text     = "Logo enabled"
$chkLogo.Location = New-Object System.Drawing.Point(482, 22)
$chkLogo.Size     = New-Object System.Drawing.Size(110, 22)
$chkLogo.Checked  = $script:cfg.Logo

$lblLogoPos           = New-Object System.Windows.Forms.Label
$lblLogoPos.Text      = "Position:"
$lblLogoPos.Location  = New-Object System.Drawing.Point(10, 54)
$lblLogoPos.Size      = New-Object System.Drawing.Size(62, 22)
$lblLogoPos.TextAlign = "MiddleRight"

$rbLogoLeft           = New-Object System.Windows.Forms.RadioButton
$rbLogoLeft.Text      = "Top-left"
$rbLogoLeft.Location  = New-Object System.Drawing.Point(76, 52)
$rbLogoLeft.Size      = New-Object System.Drawing.Size(76, 22)

$rbLogoCenter         = New-Object System.Windows.Forms.RadioButton
$rbLogoCenter.Text    = "Top-center"
$rbLogoCenter.Location = New-Object System.Drawing.Point(157, 52)
$rbLogoCenter.Size    = New-Object System.Drawing.Size(88, 22)

$rbLogoRight          = New-Object System.Windows.Forms.RadioButton
$rbLogoRight.Text     = "Top-right"
$rbLogoRight.Location = New-Object System.Drawing.Point(250, 52)
$rbLogoRight.Size     = New-Object System.Drawing.Size(80, 22)

$rbLogoNone           = New-Object System.Windows.Forms.RadioButton
$rbLogoNone.Text      = "None"
$rbLogoNone.Location  = New-Object System.Drawing.Point(335, 52)
$rbLogoNone.Size      = New-Object System.Drawing.Size(58, 22)

$chkLogoAllPages          = New-Object System.Windows.Forms.CheckBox
$chkLogoAllPages.Text     = "All pages"
$chkLogoAllPages.Location = New-Object System.Drawing.Point(400, 52)
$chkLogoAllPages.Size     = New-Object System.Drawing.Size(88, 22)
$chkLogoAllPages.Checked  = $script:cfg.LogoAllPages

# Apply logo position from config
$rbLogoRight.Checked = $true
switch ($script:cfg.LogoPosition.ToLower()) {
    'left'   { $rbLogoLeft.Checked   = $true }
    'center' { $rbLogoCenter.Checked = $true }
    'none'   { $rbLogoNone.Checked   = $true }
}

$chkPageNums          = New-Object System.Windows.Forms.CheckBox
$chkPageNums.Text     = "Page numbers"
$chkPageNums.Location = New-Object System.Drawing.Point(10, 86)
$chkPageNums.Size     = New-Object System.Drawing.Size(105, 22)
$chkPageNums.Checked  = $script:cfg.PageNumbers

$lblPagePos           = New-Object System.Windows.Forms.Label
$lblPagePos.Text      = "Position:"
$lblPagePos.Location  = New-Object System.Drawing.Point(122, 86)
$lblPagePos.Size      = New-Object System.Drawing.Size(62, 22)
$lblPagePos.TextAlign = "MiddleRight"

$rbPageLeft           = New-Object System.Windows.Forms.RadioButton
$rbPageLeft.Text      = "Left"
$rbPageLeft.Location  = New-Object System.Drawing.Point(189, 84)
$rbPageLeft.Size      = New-Object System.Drawing.Size(60, 22)

$rbPageCenter         = New-Object System.Windows.Forms.RadioButton
$rbPageCenter.Text    = "Center"
$rbPageCenter.Location = New-Object System.Drawing.Point(254, 84)
$rbPageCenter.Size    = New-Object System.Drawing.Size(68, 22)

$rbPageRight          = New-Object System.Windows.Forms.RadioButton
$rbPageRight.Text     = "Right"
$rbPageRight.Location = New-Object System.Drawing.Point(327, 84)
$rbPageRight.Size     = New-Object System.Drawing.Size(60, 22)

# Apply page number position from config
$rbPageCenter.Checked = $true
switch ($script:cfg.PageNumberPosition.ToLower()) {
    'left'  { $rbPageLeft.Checked  = $true }
    'right' { $rbPageRight.Checked = $true }
}

$chkPageNums.Add_CheckedChanged({
    $on = $chkPageNums.Checked
    foreach ($c in @($lblPagePos, $rbPageLeft, $rbPageCenter, $rbPageRight)) { $c.Enabled = $on }
})
# Sync initial enabled state
foreach ($c in @($lblPagePos, $rbPageLeft, $rbPageCenter, $rbPageRight)) { $c.Enabled = $chkPageNums.Checked }

# Logo size (row 4)
$lblLogoSize           = New-Object System.Windows.Forms.Label
$lblLogoSize.Text      = "Logo size:"
$lblLogoSize.Location  = New-Object System.Drawing.Point(10, 118)
$lblLogoSize.Size      = New-Object System.Drawing.Size(62, 22)
$lblLogoSize.TextAlign = "MiddleRight"

$lblLogoW           = New-Object System.Windows.Forms.Label
$lblLogoW.Text      = "W:"
$lblLogoW.Location  = New-Object System.Drawing.Point(76, 118)
$lblLogoW.Size      = New-Object System.Drawing.Size(20, 22)
$lblLogoW.TextAlign = "MiddleRight"

$nudLogoW               = New-Object System.Windows.Forms.NumericUpDown
$nudLogoW.Location      = New-Object System.Drawing.Point(98, 116)
$nudLogoW.Size          = New-Object System.Drawing.Size(55, 22)
$nudLogoW.Minimum       = [decimal]0.5;  $nudLogoW.Maximum   = [decimal]20
$nudLogoW.DecimalPlaces = 1;             $nudLogoW.Increment = [decimal]0.5
$nudLogoW.Value         = [Math]::Max([decimal]0.5, [Math]::Min([decimal]20, [decimal]$script:cfg.LogoWidth))

$lblLogoWCm           = New-Object System.Windows.Forms.Label
$lblLogoWCm.Text      = "cm"
$lblLogoWCm.Location  = New-Object System.Drawing.Point(155, 118)
$lblLogoWCm.Size      = New-Object System.Drawing.Size(24, 22)

$lblLogoH           = New-Object System.Windows.Forms.Label
$lblLogoH.Text      = "H:"
$lblLogoH.Location  = New-Object System.Drawing.Point(192, 118)
$lblLogoH.Size      = New-Object System.Drawing.Size(20, 22)
$lblLogoH.TextAlign = "MiddleRight"

$nudLogoH               = New-Object System.Windows.Forms.NumericUpDown
$nudLogoH.Location      = New-Object System.Drawing.Point(214, 116)
$nudLogoH.Size          = New-Object System.Drawing.Size(55, 22)
$nudLogoH.Minimum       = [decimal]0.5;  $nudLogoH.Maximum   = [decimal]20
$nudLogoH.DecimalPlaces = 1;             $nudLogoH.Increment = [decimal]0.5
$nudLogoH.Value         = [Math]::Max([decimal]0.5, [Math]::Min([decimal]20, [decimal]$script:cfg.LogoHeight))

$lblLogoHCm           = New-Object System.Windows.Forms.Label
$lblLogoHCm.Text      = "cm"
$lblLogoHCm.Location  = New-Object System.Drawing.Point(271, 118)
$lblLogoHCm.Size      = New-Object System.Drawing.Size(24, 22)

# All controls whose enabled state is toggled by the "Logo enabled" checkbox —
# must be built AFTER all logo-size controls are defined above.
$script:logoControls = @($txtLogo, $btnBrowseLogo,
    $lblLogoPos, $rbLogoLeft, $rbLogoCenter, $rbLogoRight, $rbLogoNone,
    $chkLogoAllPages,
    $lblLogoSize, $lblLogoW, $nudLogoW, $lblLogoWCm,
    $lblLogoH, $nudLogoH, $lblLogoHCm)

$chkLogo.Add_CheckedChanged({
    $on = $chkLogo.Checked
    foreach ($c in $script:logoControls) { $c.Enabled = $on }
})

# Sync initial enabled state
foreach ($c in $script:logoControls) { $c.Enabled = $chkLogo.Checked }

$grpSettings.Controls.AddRange(@(
    $lblLogo, $txtLogo, $btnBrowseLogo, $chkLogo,
    $lblLogoPos, $rbLogoLeft, $rbLogoCenter, $rbLogoRight, $rbLogoNone, $chkLogoAllPages,
    $chkPageNums, $lblPagePos, $rbPageLeft, $rbPageCenter, $rbPageRight,
    $lblLogoSize, $lblLogoW, $nudLogoW, $lblLogoWCm,
    $lblLogoH, $nudLogoH, $lblLogoHCm
))

# ── Page Settings GroupBox ────────────────────────────────────────────────

$grpPage          = New-Object System.Windows.Forms.GroupBox
$grpPage.Text     = " Page Settings "
$grpPage.Location = New-Object System.Drawing.Point(10, 174)
$grpPage.Size     = New-Object System.Drawing.Size(600, 152)
$grpPage.Anchor   = "Top, Left, Right"

$lblOrientation           = New-Object System.Windows.Forms.Label
$lblOrientation.Text      = "Orientation:"
$lblOrientation.Location  = New-Object System.Drawing.Point(10, 24)
$lblOrientation.Size      = New-Object System.Drawing.Size(74, 22)
$lblOrientation.TextAlign = "MiddleRight"

$rbPortrait           = New-Object System.Windows.Forms.RadioButton
$rbPortrait.Text      = "Portrait"
$rbPortrait.Location  = New-Object System.Drawing.Point(88, 22)
$rbPortrait.Size      = New-Object System.Drawing.Size(74, 22)
$rbPortrait.Checked   = ($script:cfg.Orientation -ne 'Landscape')

$rbLandscape          = New-Object System.Windows.Forms.RadioButton
$rbLandscape.Text     = "Landscape"
$rbLandscape.Location = New-Object System.Drawing.Point(166, 22)
$rbLandscape.Size     = New-Object System.Drawing.Size(82, 22)
$rbLandscape.Checked  = ($script:cfg.Orientation -eq 'Landscape')

$lblHeaderH           = New-Object System.Windows.Forms.Label
$lblHeaderH.Text      = "Header:"
$lblHeaderH.Location  = New-Object System.Drawing.Point(10, 56)
$lblHeaderH.Size      = New-Object System.Drawing.Size(52, 22)
$lblHeaderH.TextAlign = "MiddleRight"

$nudHeaderH               = New-Object System.Windows.Forms.NumericUpDown
$nudHeaderH.Location      = New-Object System.Drawing.Point(66, 54)
$nudHeaderH.Size          = New-Object System.Drawing.Size(55, 22)
$nudHeaderH.Minimum       = [decimal]0
$nudHeaderH.Maximum       = [decimal]10
$nudHeaderH.DecimalPlaces = 1
$nudHeaderH.Increment     = [decimal]0.5
$nudHeaderH.Value         = [Math]::Max([decimal]0, [Math]::Min([decimal]10, [decimal]$script:cfg.HeaderHeight))

$lblHeaderCm           = New-Object System.Windows.Forms.Label
$lblHeaderCm.Text      = "cm"
$lblHeaderCm.Location  = New-Object System.Drawing.Point(123, 56)
$lblHeaderCm.Size      = New-Object System.Drawing.Size(24, 22)

$lblFooterH           = New-Object System.Windows.Forms.Label
$lblFooterH.Text      = "Footer:"
$lblFooterH.Location  = New-Object System.Drawing.Point(162, 56)
$lblFooterH.Size      = New-Object System.Drawing.Size(52, 22)
$lblFooterH.TextAlign = "MiddleRight"

$nudFooterH               = New-Object System.Windows.Forms.NumericUpDown
$nudFooterH.Location      = New-Object System.Drawing.Point(218, 54)
$nudFooterH.Size          = New-Object System.Drawing.Size(55, 22)
$nudFooterH.Minimum       = [decimal]0
$nudFooterH.Maximum       = [decimal]10
$nudFooterH.DecimalPlaces = 1
$nudFooterH.Increment     = [decimal]0.5
$nudFooterH.Value         = [Math]::Max([decimal]0, [Math]::Min([decimal]10, [decimal]$script:cfg.FooterHeight))

$lblFooterCm           = New-Object System.Windows.Forms.Label
$lblFooterCm.Text      = "cm"
$lblFooterCm.Location  = New-Object System.Drawing.Point(275, 56)
$lblFooterCm.Size      = New-Object System.Drawing.Size(24, 22)

$lblMargins           = New-Object System.Windows.Forms.Label
$lblMargins.Text      = "Margins:"
$lblMargins.Location  = New-Object System.Drawing.Point(10, 88)
$lblMargins.Size      = New-Object System.Drawing.Size(52, 22)
$lblMargins.TextAlign = "MiddleRight"

$lblMTop           = New-Object System.Windows.Forms.Label
$lblMTop.Text      = "Top"
$lblMTop.Location  = New-Object System.Drawing.Point(66, 88)
$lblMTop.Size      = New-Object System.Drawing.Size(28, 22)
$lblMTop.TextAlign = "MiddleLeft"

$nudMTop               = New-Object System.Windows.Forms.NumericUpDown
$nudMTop.Location      = New-Object System.Drawing.Point(96, 86)
$nudMTop.Size          = New-Object System.Drawing.Size(50, 22)
$nudMTop.Minimum       = [decimal]0;  $nudMTop.Maximum   = [decimal]10
$nudMTop.DecimalPlaces = 1;           $nudMTop.Increment = [decimal]0.5
$nudMTop.Value         = [Math]::Max([decimal]0, [Math]::Min([decimal]10, [decimal]$script:cfg.MarginTop))

$lblMBottom           = New-Object System.Windows.Forms.Label
$lblMBottom.Text      = "Bottom"
$lblMBottom.Location  = New-Object System.Drawing.Point(150, 88)
$lblMBottom.Size      = New-Object System.Drawing.Size(48, 22)
$lblMBottom.TextAlign = "MiddleLeft"

$nudMBottom               = New-Object System.Windows.Forms.NumericUpDown
$nudMBottom.Location      = New-Object System.Drawing.Point(200, 86)
$nudMBottom.Size          = New-Object System.Drawing.Size(50, 22)
$nudMBottom.Minimum       = [decimal]0;  $nudMBottom.Maximum   = [decimal]10
$nudMBottom.DecimalPlaces = 1;           $nudMBottom.Increment = [decimal]0.5
$nudMBottom.Value         = [Math]::Max([decimal]0, [Math]::Min([decimal]10, [decimal]$script:cfg.MarginBottom))

$lblMLeft           = New-Object System.Windows.Forms.Label
$lblMLeft.Text      = "Left"
$lblMLeft.Location  = New-Object System.Drawing.Point(254, 88)
$lblMLeft.Size      = New-Object System.Drawing.Size(28, 22)
$lblMLeft.TextAlign = "MiddleLeft"

$nudMLeft               = New-Object System.Windows.Forms.NumericUpDown
$nudMLeft.Location      = New-Object System.Drawing.Point(284, 86)
$nudMLeft.Size          = New-Object System.Drawing.Size(50, 22)
$nudMLeft.Minimum       = [decimal]0;  $nudMLeft.Maximum   = [decimal]10
$nudMLeft.DecimalPlaces = 1;           $nudMLeft.Increment = [decimal]0.5
$nudMLeft.Value         = [Math]::Max([decimal]0, [Math]::Min([decimal]10, [decimal]$script:cfg.MarginLeft))

$lblMRight           = New-Object System.Windows.Forms.Label
$lblMRight.Text      = "Right"
$lblMRight.Location  = New-Object System.Drawing.Point(338, 88)
$lblMRight.Size      = New-Object System.Drawing.Size(36, 22)
$lblMRight.TextAlign = "MiddleLeft"

$nudMRight               = New-Object System.Windows.Forms.NumericUpDown
$nudMRight.Location      = New-Object System.Drawing.Point(376, 86)
$nudMRight.Size          = New-Object System.Drawing.Size(50, 22)
$nudMRight.Minimum       = [decimal]0;  $nudMRight.Maximum   = [decimal]10
$nudMRight.DecimalPlaces = 1;           $nudMRight.Increment = [decimal]0.5
$nudMRight.Value         = [Math]::Max([decimal]0, [Math]::Min([decimal]10, [decimal]$script:cfg.MarginRight))

$lblMCm           = New-Object System.Windows.Forms.Label
$lblMCm.Text      = "cm each"
$lblMCm.Location  = New-Object System.Drawing.Point(430, 88)
$lblMCm.Size      = New-Object System.Drawing.Size(58, 22)

$lblMTopFirst           = New-Object System.Windows.Forms.Label
$lblMTopFirst.Text      = "Top (1st page):"
$lblMTopFirst.Location  = New-Object System.Drawing.Point(10, 120)
$lblMTopFirst.Size      = New-Object System.Drawing.Size(96, 22)
$lblMTopFirst.TextAlign = "MiddleRight"

$nudMTopFirst               = New-Object System.Windows.Forms.NumericUpDown
$nudMTopFirst.Location      = New-Object System.Drawing.Point(110, 118)
$nudMTopFirst.Size          = New-Object System.Drawing.Size(50, 22)
$nudMTopFirst.Minimum       = [decimal]0;  $nudMTopFirst.Maximum   = [decimal]10
$nudMTopFirst.DecimalPlaces = 1;           $nudMTopFirst.Increment = [decimal]0.5
$nudMTopFirst.Value         = [Math]::Max([decimal]0, [Math]::Min([decimal]10, [decimal]$script:cfg.MarginTopFirst))

$lblMTopFirstCm           = New-Object System.Windows.Forms.Label
$lblMTopFirstCm.Text      = "cm"
$lblMTopFirstCm.Location  = New-Object System.Drawing.Point(162, 120)
$lblMTopFirstCm.Size      = New-Object System.Drawing.Size(24, 22)

$grpPage.Controls.AddRange(@(
    $lblOrientation, $rbPortrait, $rbLandscape,
    $lblHeaderH, $nudHeaderH, $lblHeaderCm,
    $lblFooterH, $nudFooterH, $lblFooterCm,
    $lblMargins,
    $lblMTop,      $nudMTop,
    $lblMBottom,   $nudMBottom,
    $lblMLeft,     $nudMLeft,
    $lblMRight,    $nudMRight,
    $lblMCm,
    $lblMTopFirst, $nudMTopFirst, $lblMTopFirstCm
))

# ── Sections GroupBox ─────────────────────────────────────────────────────

$grpSections          = New-Object System.Windows.Forms.GroupBox
$grpSections.Text     = " Select Sections "
$grpSections.Location = New-Object System.Drawing.Point(10, 334)
$grpSections.Size     = New-Object System.Drawing.Size(600, 346)
$grpSections.Anchor   = "Top, Left, Right, Bottom"

$btnSelAll          = New-Object System.Windows.Forms.Button
$btnSelAll.Text     = "Select All"
$btnSelAll.Location = New-Object System.Drawing.Point(10, 20)
$btnSelAll.Size     = New-Object System.Drawing.Size(88, 26)

$btnDeselAll          = New-Object System.Windows.Forms.Button
$btnDeselAll.Text     = "Deselect All"
$btnDeselAll.Location = New-Object System.Drawing.Point(103, 20)
$btnDeselAll.Size     = New-Object System.Drawing.Size(96, 26)

$pnlTree             = New-Object System.Windows.Forms.Panel
$pnlTree.Location    = New-Object System.Drawing.Point(8, 52)
$pnlTree.Size        = New-Object System.Drawing.Size(584, 286)
$pnlTree.Anchor      = "Top, Left, Right, Bottom"
$pnlTree.BorderStyle = "FixedSingle"

$treeView               = New-Object System.Windows.Forms.TreeView
$treeView.Dock          = "Fill"
$treeView.CheckBoxes    = $true
$treeView.ShowLines     = $true
$treeView.HideSelection = $false

# Group HTML files under folder nodes that mirror the sites/ directory hierarchy.
# Each unique subdirectory under $sitesDir gets one bold folder node whose display
# name comes from the HTML navigation (falling back to a prettified folder name).
# Files located directly in $sitesDir are added to the root of the TreeView.
$folderNodes = @{}   # lower-cased relative dir path → TreeNode

foreach ($f in $htmlFiles) {
    $secs = $allSections[$f.FullName]
    if ($secs.Count -eq 0) { continue }

    $relPath = $f.FullName.Substring($sitesDir.TrimEnd('\').Length + 1)
    $parts   = $relPath -split '[/\\]'

    if ($parts.Count -gt 1) {
        # Build (or reuse) a folder node for every directory component above the file.
        for ($i = 0; $i -lt ($parts.Count - 1); $i++) {
            $seg        = $parts[$i]
            $relDirPath = ($parts[0..$i]) -join '/'
            $lookupKey  = $relDirPath.ToLower()

            if (-not $folderNodes.ContainsKey($lookupKey)) {
                # Prefer the nav title from html/index.html; fall back to prettified name.
                $tocRelPath  = ($relDirPath -replace '/', '\') + '\' + $tocFileName
                $folderTitle = $script:folderTitleMap[$tocRelPath.ToLower()]
                if (-not $folderTitle) {
                    $folderTitle = (Get-Culture).TextInfo.ToTitleCase(($seg -replace '[_-]', ' '))
                }

                $folderNode          = New-Object System.Windows.Forms.TreeNode
                $folderNode.Text     = $folderTitle
                $folderNode.Checked  = $true
                $folderNode.Tag      = $null   # not a section — not collected, but children are
                $folderNode.NodeFont = New-Object System.Drawing.Font(
                    $treeView.Font.FontFamily, $treeView.Font.Size, [System.Drawing.FontStyle]::Bold)

                if ($i -eq 0) {
                    $treeView.Nodes.Add($folderNode) | Out-Null
                } else {
                    $parentKey = ($parts[0..($i - 1)] -join '/').ToLower()
                    $folderNodes[$parentKey].Nodes.Add($folderNode) | Out-Null
                }
                $folderNodes[$lookupKey] = $folderNode
            }
        }

        $parentKey = ($parts[0..($parts.Count - 2)] -join '/').ToLower()
        Add-FileToTree -Parent $folderNodes[$parentKey] -TreeFont $treeView.Font `
                       -MdFile $f -Sections $secs
    } else {
        Add-FileToTree -Parent $treeView -TreeFont $treeView.Font `
                       -MdFile $f -Sections $secs
    }
}
$treeView.ExpandAll()

$script:suppressCheck = $false

$treeView.Add_AfterCheck({
    param($s, $e)
    if ($script:suppressCheck) { return }
    if ($e.Action -eq [System.Windows.Forms.TreeViewAction]::Unknown) { return }
    $script:suppressCheck = $true
    Set-NodeCheckState -Node $e.Node -Checked $e.Node.Checked
    $script:suppressCheck = $false
})

$btnSelAll.Add_Click({
    $script:suppressCheck = $true
    foreach ($n in $treeView.Nodes) { $n.Checked = $true; Set-NodeCheckState -Node $n -Checked $true }
    $script:suppressCheck = $false
})

$btnDeselAll.Add_Click({
    $script:suppressCheck = $true
    foreach ($n in $treeView.Nodes) { $n.Checked = $false; Set-NodeCheckState -Node $n -Checked $false }
    $script:suppressCheck = $false
})

$pnlTree.Controls.Add($treeView)
$grpSections.Controls.AddRange(@($btnSelAll, $btnDeselAll, $pnlTree))

# ── Output rows ──────────────────────────────────────────────────────────

# Row 1: document title (optional — appears above the TOC in the PDF)
$lblDocTitle           = New-Object System.Windows.Forms.Label
$lblDocTitle.Text      = "Dokumenten Titel:"
$lblDocTitle.Location  = New-Object System.Drawing.Point(10, 692)
$lblDocTitle.Size      = New-Object System.Drawing.Size(110, 24)
$lblDocTitle.TextAlign = "MiddleRight"
$lblDocTitle.Anchor    = "Bottom, Left"

$txtDocTitle          = New-Object System.Windows.Forms.TextBox
$txtDocTitle.Location = New-Object System.Drawing.Point(124, 692)
$txtDocTitle.Size     = New-Object System.Drawing.Size(478, 24)
$txtDocTitle.Anchor   = "Bottom, Left, Right"
$txtDocTitle.Text     = ''

# Row 2: file name (required — enables Export button)
$lblFileName           = New-Object System.Windows.Forms.Label
$lblFileName.Text      = "Dateiname:"
$lblFileName.Location  = New-Object System.Drawing.Point(10, 720)
$lblFileName.Size      = New-Object System.Drawing.Size(110, 24)
$lblFileName.TextAlign = "MiddleRight"
$lblFileName.Anchor    = "Bottom, Left"

$txtFileName          = New-Object System.Windows.Forms.TextBox
$txtFileName.Location = New-Object System.Drawing.Point(124, 720)
$txtFileName.Size     = New-Object System.Drawing.Size(478, 24)
$txtFileName.Anchor   = "Bottom, Left, Right"
$txtFileName.Text     = ''

# Row 3: output folder
$lblOutDir           = New-Object System.Windows.Forms.Label
$lblOutDir.Text      = "Path:"
$lblOutDir.Location  = New-Object System.Drawing.Point(10, 750)
$lblOutDir.Size      = New-Object System.Drawing.Size(110, 24)
$lblOutDir.TextAlign = "MiddleRight"
$lblOutDir.Anchor    = "Bottom, Left"

$txtOutDir          = New-Object System.Windows.Forms.TextBox
$txtOutDir.Location = New-Object System.Drawing.Point(124, 750)
$txtOutDir.Size     = New-Object System.Drawing.Size(440, 24)
$txtOutDir.Anchor   = "Bottom, Left, Right"
$txtOutDir.Text     = $script:cfg.OutputDirectory

$btnBrowseOut          = New-Object System.Windows.Forms.Button
$btnBrowseOut.Text     = "..."
$btnBrowseOut.Location = New-Object System.Drawing.Point(568, 749)
$btnBrowseOut.Size     = New-Object System.Drawing.Size(34, 26)
$btnBrowseOut.Anchor   = "Bottom, Right"
$btnBrowseOut.Add_Click({
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description  = "Select output folder"
    $d.SelectedPath = $txtOutDir.Text
    if ($d.ShowDialog() -eq 'OK') { $txtOutDir.Text = $d.SelectedPath }
})

# ── Export button ─────────────────────────────────────────────────────────

$btnExport           = New-Object System.Windows.Forms.Button
$btnExport.Text      = "Export PDF"
$btnExport.Location  = New-Object System.Drawing.Point(10, 782)
$btnExport.Size      = New-Object System.Drawing.Size(600, 40)
$btnExport.Anchor    = "Bottom, Left, Right"
$btnExport.BackColor = [System.Drawing.Color]::FromArgb(30, 80, 200)
$btnExport.ForeColor = [System.Drawing.Color]::White
$btnExport.FlatStyle = "Flat"
$btnExport.Font      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnExport.FlatAppearance.BorderSize = 0
$btnExport.Enabled   = $false
$btnExport.BackColor = [System.Drawing.Color]::FromArgb(160, 160, 160)

$txtFileName.Add_TextChanged({
    $hasName = -not [string]::IsNullOrWhiteSpace($txtFileName.Text)
    $btnExport.Enabled   = $hasName
    $btnExport.BackColor = if ($hasName) {
        [System.Drawing.Color]::FromArgb(30, 80, 200)
    } else {
        [System.Drawing.Color]::FromArgb(160, 160, 160)
    }
})

$btnExport.Add_Click({
    # ── Validate ──────────────────────────────────────────────────────────
    $secs = Get-SelectedSections -TreeView $treeView
    if ($secs.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please select at least one section.", "Nothing selected", 'OK', 'Warning') | Out-Null
        return
    }

    # Build output path from folder + filename
    $outDir    = $txtOutDir.Text.Trim()
    $outName   = $txtFileName.Text.Trim()
    $docTitle  = $txtDocTitle.Text.Trim()
    $pdfTitle  = if (-not [string]::IsNullOrWhiteSpace($docTitle)) { $docTitle } else { $outName }
    if ([string]::IsNullOrWhiteSpace($outName)) { $outName = $script:defaultDocName }

    # Strip invalid filename characters
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($ch in $invalidChars) { $outName = $outName.Replace([string]$ch, '_') }
    $outName = $outName.TrimEnd('.')

    if ([string]::IsNullOrWhiteSpace($outDir)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please specify an output folder.", "No output path", 'OK', 'Warning') | Out-Null
        return
    }
    $outPdf = Join-Path $outDir "$outName.pdf"

    $edgeExe = Find-EdgeExe
    if (-not $edgeExe) {
        [System.Windows.Forms.MessageBox]::Show(
            "Microsoft Edge was not found.`nInstall Edge or add msedge.exe to PATH.",
            "Edge not found", 'OK', 'Error') | Out-Null
        return
    }

    # ── Collect settings ──────────────────────────────────────────────────
    $logoPos = if ($rbLogoLeft.Checked)   { 'left'   }
               elseif ($rbLogoCenter.Checked) { 'center' }
               elseif ($rbLogoRight.Checked)  { 'right'  }
               else                           { 'none'   }

    $pagePos = if ($rbPageLeft.Checked)  { 'left'  }
               elseif ($rbPageRight.Checked) { 'right' }
               else                          { 'center' }

    $orient     = if ($rbLandscape.Checked) { 'Landscape' } else { 'Portrait' }
    $hdrH       = [double]$nudHeaderH.Value
    $ftrH       = [double]$nudFooterH.Value
    $mTop       = [double]$nudMTop.Value
    $mTopFirst  = [double]$nudMTopFirst.Value
    $mBottom    = [double]$nudMBottom.Value
    $mLeft      = [double]$nudMLeft.Value
    $mRight     = [double]$nudMRight.Value
    $logoW      = [double]$nudLogoW.Value
    $logoH      = [double]$nudLogoH.Value

    # ── Persist settings to build.ini ─────────────────────────────────────
    try {
        $ti = (Get-Culture).TextInfo
        Save-DocumentConfig `
            -Logo               $chkLogo.Checked `
            -LogoAllPages       $chkLogoAllPages.Checked `
            -LogoPath           $txtLogo.Text.Trim() `
            -LogoPosition       (if ($logoPos -eq 'none') { 'None' } else { $ti.ToTitleCase($logoPos) }) `
            -PageNumbers        $chkPageNums.Checked `
            -PageNumberPosition $ti.ToTitleCase($pagePos) `
            -OutputDirectory    (if ($outDir) { $outDir } else { Join-Path $ProjectRoot "documents" }) `
            -HeaderHeight       $hdrH ` 
            -FooterHeight       $ftrH `
            -MarginTop          $mTop `
            -MarginTopFirst     $mTopFirst `
            -MarginBottom       $mBottom `
            -MarginLeft         $mLeft `
            -MarginRight        $mRight `
            -Orientation        $orient `
            -LogoWidth          $logoW `
            -LogoHeight         $logoH
    } catch { }

    # ── Prepare output + temp dir ─────────────────────────────────────────
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

    $tmpDir  = Join-Path $env:TEMP "da_doc_export"
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    $tmpHtml = Join-Path $tmpDir "da_print.html"

    try {
        $btnExport.Text    = "Generating..."
        $btnExport.Enabled = $false
        [System.Windows.Forms.Application]::DoEvents()

        Build-PrintHtml `
            -Sections      $secs `
            -Logo          $chkLogo.Checked `
            -LogoAllPages  $chkLogoAllPages.Checked `
            -LogoPath      $txtLogo.Text.Trim() `
            -LogoPosition  $logoPos `
            -PageNumbers   $chkPageNums.Checked `
            -PageNumberPos $pagePos `
            -OutputPath    $tmpHtml `
            -InlinedCss    $script:inlinedCss `
            -Orientation    $orient `
            -MarginTop      $mTop `
            -MarginTopFirst $mTopFirst `
            -MarginBottom   $mBottom `
            -MarginLeft     $mLeft `
            -MarginRight    $mRight `
            -HeaderHeight   $hdrH `
            -FooterHeight  $ftrH `
            -LogoWidth     $logoW `
            -LogoHeight    $logoH `
            -TocHeadline   $script:cfg.TocHeadline `
            -DocTitle      $docTitle `
            -PdfTitle      $pdfTitle `
            -OverrideCss   $script:overrideCss

        # ── Debug: save generated HTML before PDF creation ────────────────
        if ($script:cfg.DebugEnabled) {
            $debugDir = Join-Path $ProjectRoot $script:cfg.outputPath
            if (-not (Test-Path $debugDir)) { New-Item -ItemType Directory -Path $debugDir -Force | Out-Null }
            Copy-Item -LiteralPath $tmpHtml -Destination (Join-Path $debugDir "da_print_debug.html") -Force
        }
        
        # ── Run Edge headless ─────────────────────────────────────────────
        $fileUri = 'file:///' + $tmpHtml.Replace('\', '/')

        $psi                       = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName              = $edgeExe
        # Paths quoted to handle spaces; arguments as single string avoids array-escaping quirks
        $psi.Arguments             = "--headless --disable-gpu --no-pdf-header-footer " +
                                     "--print-to-pdf=`"$outPdf`" `"$fileUri`""
        $psi.UseShellExecute       = $false
        $psi.CreateNoWindow        = $true
        $psi.RedirectStandardError = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.WaitForExit()

        # Edge can finish writing the PDF slightly after the process exits — poll up to 10 s
        $deadline = [DateTime]::Now.AddSeconds(10)
        while (-not (Test-Path -LiteralPath $outPdf) -and [DateTime]::Now -lt $deadline) {
            Start-Sleep -Milliseconds 300
        }

        if (($proc.ExitCode -eq 0) -and (Test-Path -LiteralPath $outPdf)) {
            $res = [System.Windows.Forms.MessageBox]::Show(
                "PDF created successfully:`n$outPdf`n`nOpen the PDF now?",
                "Export complete", 'YesNo', 'Information')
            if ($res -eq 'Yes') { Start-Process $outPdf }
        } else {
            [System.Windows.Forms.MessageBox]::Show(
                "Export failed (Edge exit code: $($proc.ExitCode)).",
                "Export error", 'OK', 'Error') | Out-Null
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Unexpected error:`n$_", "Export error", 'OK', 'Error') | Out-Null
    } finally {
        $btnExport.Text    = "Export PDF"
        $btnExport.Enabled = $true
        Remove-Item $tmpHtml -ErrorAction SilentlyContinue
    }
})

# ── Assemble & show ───────────────────────────────────────────────────────

$form.Controls.AddRange(@(
    $grpSettings,
    $grpPage,
    $grpSections,
    $lblFileName, $txtFileName,
    $lblDocTitle, $txtDocTitle,
    $lblOutDir, $txtOutDir, $btnBrowseOut,
    $btnExport
))

$form.ShowDialog() | Out-Null
