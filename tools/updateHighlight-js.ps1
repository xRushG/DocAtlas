param (
    [string] $TargetDir,
	[string] $MarkedURL
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

$ScRoot = $PSScriptRoot
$OutFile = "highlight.min.js"

# Default setzen wenn nicht übergeben
if (-not $PSBoundParameters.ContainsKey("TargetDir")) {
    $TargetDir = Join-Path ($ScRoot | Split-Path) "res\lib"
}

# Download URL
if (-not $PSBoundParameters.ContainsKey("MarkedURL")) {
    $MarkedURL = "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"
}

# Ordner sicher anlegen
if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
}


# Zielpfad
$dest = Join-Path $TargetDir $OutFile

# Download
Invoke-WebRequest -Uri $MarkedURL -OutFile $dest

Write-Host "highlight.js updated -> $dest"