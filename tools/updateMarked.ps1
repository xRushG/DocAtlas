param (
    [string] $TargetDir,
	[string] $MarkedURL
)
$ScRoot = $PSScriptRoot

$OutFile = "marked.min.js"

# Default setzen wenn nicht übergeben
if (-not $PSBoundParameters.ContainsKey("TargetDir")) {
    $TargetDir = Join-Path ($ScRoot | Split-Path) "html\lib"
}

# Download URL
if (-not $PSBoundParameters.ContainsKey("MarkedURL")) {
    $MarkedURL = "https://cdn.jsdelivr.net/npm/marked/marked.min.js"
}

# Ordner sicher anlegen
if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
}


# Zielpfad
$dest = Join-Path $TargetDir $OutFile

# Download
Invoke-WebRequest -Uri $MarkedURL -OutFile $dest

Write-Host "Marked.js updated -> $dest"