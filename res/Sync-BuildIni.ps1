#Requires -Version 7.0
<#
.SYNOPSIS
    Keeps build.ini in sync with res/build.ini.tmpl.

.DESCRIPTION
    - First run (no build.ini): copies the template.
    - Case A: keys present in template but missing from build.ini are appended.
    - Case B: keys in build.ini that no longer exist in the template are flagged;
              the user is prompted to remove them.

    Dot-source this file, then call Sync-BuildIni.
#>

function _SyncIni_ParseKeys {
    <# Returns an ordered hashtable of "Section§Key" -> "raw value string" #>
    param([string] $Path)
    $result  = [ordered]@{}
    $section = ''
    $raw     = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $raw     = [regex]::Replace(
        $raw, '/\*.*?\*/', '',
        [System.Text.RegularExpressions.RegexOptions]::Singleline)
    foreach ($line in ($raw -split "`r?`n")) {
        $l = ($line -replace '//.*$', '').Trim()
        if ($l -match '^\[(.+?)\]\s*$')             { $section = $matches[1].Trim(); continue }
        if ($l -match '^([^=\s][^=]*?)\s*=\s*(.*)$') {
            if ($section) { $result["$section§$($matches[1].Trim())"] = $matches[2].Trim() }
        }
    }
    return $result
}

function Sync-BuildIni {
    <#
    .SYNOPSIS
        Synchronises build.ini against its template.

    .PARAMETER IniPath
        Path to the live build.ini (project root).

    .PARAMETER TemplatePath
        Path to the template file (res/build.ini.tmpl).

    .PARAMETER UseGui
        Show a WinForms MessageBox for the deprecated-key prompt instead of Read-Host.
    #>
    param(
        [Parameter(Mandatory)] [string] $IniPath,
        [Parameter(Mandatory)] [string] $TemplatePath,
        [switch] $UseGui
    )

    if (-not (Test-Path -LiteralPath $TemplatePath)) { return }

    # ── First run: no build.ini yet ──────────────────────────────────────────
    if (-not (Test-Path -LiteralPath $IniPath)) {
        Copy-Item -LiteralPath $TemplatePath -Destination $IniPath -Force
        return
    }

    $tmpl = _SyncIni_ParseKeys -Path $TemplatePath
    $ini  = _SyncIni_ParseKeys -Path $IniPath

    # ── Case A: keys in template but not in ini → append ────────────────────
    $missing = @($tmpl.Keys | Where-Object { -not $ini.Contains($_) })

    if ($missing.Count -gt 0) {
        # Group missing keys by section
        $bySec = [ordered]@{}
        foreach ($sk in $missing) {
            $sec = ($sk -split '§', 2)[0]
            if (-not $bySec.Contains($sec)) {
                $bySec[$sec] = [System.Collections.Generic.List[string]]::new()
            }
            $bySec[$sec].Add($sk)
        }

        $sb = [System.Text.StringBuilder]::new()
        $sb.AppendLine() | Out-Null
        foreach ($sec in $bySec.Keys) {
            $sb.AppendLine("[$sec]") | Out-Null
            foreach ($sk in $bySec[$sec]) {
                $key = ($sk -split '§', 2)[1]
                $val = $tmpl[$sk]
                $sb.AppendLine("$key=$val") | Out-Null
            }
        }
        Add-Content -LiteralPath $IniPath -Value $sb.ToString() -Encoding UTF8 -NoNewline
    }

    # ── Case B: keys in ini but not in template → deprecated ────────────────
    $deprecated = @($ini.Keys | Where-Object { -not $tmpl.Contains($_) })

    if ($deprecated.Count -gt 0) {
        $list = ($deprecated | ForEach-Object {
            $p = $_ -split '§', 2
            "  [$($p[0])]  $($p[1])"
        }) -join "`n"

        $msg = "Veraltete Einstellungen in build.ini erkannt:`n`n$list`n`nAus build.ini entfernen?"

        $doRemove = if ($UseGui) {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
            [System.Windows.Forms.MessageBox]::Show(
                $msg, 'build.ini — Deprecated Settings',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) -eq 'Yes'
        } else {
            Write-Host "`n$msg" -ForegroundColor Yellow
            $a = Read-Host '[Y] Ja  /  [N] Nein'
            $a -eq 'Y' -or $a -eq 'y'
        }

        if ($doRemove) {
            $curSec = ''
            $out    = [System.Collections.Generic.List[string]]::new()
            foreach ($line in (Get-Content -LiteralPath $IniPath -Encoding UTF8)) {
                $s = [regex]::Replace($line, '/\*.*?\*/', '').Trim()
                $s = ($s -replace '//.*$', '').Trim()
                if ($s -match '^\[(.+?)\]\s*$') {
                    $curSec = $matches[1].Trim()
                    $out.Add($line)
                    continue
                }
                if ($s -match '^([^=\s][^=]*?)\s*=') {
                    if ($deprecated -contains "$curSec§$($matches[1].Trim())") { continue }
                }
                $out.Add($line)
            }
            Set-Content -LiteralPath $IniPath -Value $out -Encoding UTF8
        }
    }
}
