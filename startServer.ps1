param (
    [string]$DocsRoot,
    [int]$Port
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

if (-not $PSBoundParameters.ContainsKey("DocsRoot")) {
    $ini   = Join-Path $PSScriptRoot "build.ini"
    $match = Get-Content $ini | Select-String '^\s*buildFolder\s*=\s*"?([^"]+)"?'

    if ($match) { 
        $DocsRoot = Join-Path $PSScriptRoot $match.Matches.Groups[1].Value 
    } else { 
        $DocsRoot = Join-Path $PSScriptRoot "html" 
    }
}

if (-not $PSBoundParameters.ContainsKey("Port")) {
    $Port = 8080
}

$listener = New-Object System.Net.HttpListener
$prefix = "http://localhost:{0}/" -f $Port
$listener.Prefixes.Add($prefix)
$listener.Start()

Write-Host "Serving '$DocsRoot' on $prefix (Strg+C zum Beenden)"

# einfache MIME-Tabelle
$mimeTypes = @{
    ".html" = "text/html; charset=utf-8"
    ".htm"  = "text/html; charset=utf-8"
    ".css"  = "text/css; charset=utf-8"
    ".js"   = "application/javascript; charset=utf-8"
    ".json" = "application/json; charset=utf-8"
    ".md"   = "text/plain; charset=utf-8"   # oder text/markdown
    ".png"  = "image/png"
    ".jpg"  = "image/jpeg"
    ".jpeg" = "image/jpeg"
    ".gif"  = "image/gif"
    ".svg"  = "image/svg+xml; charset=utf-8"
}

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()

        try {
            $path = [System.Web.HttpUtility]::UrlDecode($ctx.Request.Url.LocalPath)
            if ($path -eq "/") { $path = "/index.html" }

            $file = [System.IO.Path]::GetFullPath((Join-Path $DocsRoot $path.TrimStart("/")))
            if (-not $file.StartsWith($DocsRoot)) { throw "Invalid path" }

            if (Test-Path -LiteralPath $file -PathType Leaf) {
                $bytes = [System.IO.File]::ReadAllBytes($file)

                $ext = [System.IO.Path]::GetExtension($file).ToLowerInvariant()
                if ($mimeTypes.ContainsKey($ext)) {
                    $ctx.Response.ContentType = $mimeTypes[$ext]
                } else {
                    $ctx.Response.ContentType = "application/octet-stream"
                }

                $ctx.Response.StatusCode = 200
                $ctx.Response.ContentLength64 = $bytes.Length
                $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
            } else {
                $ctx.Response.StatusCode = 404
                $msg = "404 Not Found"
                $bytes = [Text.Encoding]::UTF8.GetBytes($msg)
                $ctx.Response.ContentType = "text/plain; charset=utf-8"
                $ctx.Response.ContentLength64 = $bytes.Length
                $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
            }
        }
        catch {
            Write-Warning $_
            try {
                $ctx.Response.StatusCode = 500
                $msg = "500 Internal Server Error"
                $bytes = [Text.Encoding]::UTF8.GetBytes($msg)
                $ctx.Response.ContentType = "text/plain; charset=utf-8"
                $ctx.Response.ContentLength64 = $bytes.Length
                $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
            } catch {}
        }
        finally {
            $ctx.Response.OutputStream.Close()
            $ctx.Response.Close()
        }
    }
}
finally {
    $listener.Stop()
    $listener.Close()
}