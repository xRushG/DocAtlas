param (
    [string] $TargetDir,
	[string] $MarkedURL
)
$ScRoot = $PSScriptRoot

$OutFile = "minisearch.min.js"

# Default setzen wenn nicht übergeben
if (-not $PSBoundParameters.ContainsKey("TargetDir")) {
    $TargetDir = Join-Path ($ScRoot | Split-Path) "html\lib"
}

# Download URL
if (-not $PSBoundParameters.ContainsKey("MarkedURL")) {
    $MarkedURL = "https://cdn.jsdelivr.net/npm/minisearch@6/dist/umd/index.min.js"
}

# Ordner sicher anlegen
if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
}


# Zielpfad
$dest = Join-Path $TargetDir $OutFile

# Download
Invoke-WebRequest -Uri $MarkedURL -OutFile $dest

Write-Host "minisearch.js updated -> $dest"