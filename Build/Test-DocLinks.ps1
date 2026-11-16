#Requires -Version 7.0
<#
.SYNOPSIS
    Check relative links and heading anchors in the repository's Markdown files.
.DESCRIPTION
    Scans every *.md file under the repository root (skipping .git and .agent-tmp) and reports any
    relative link whose target file or folder does not exist, or whose #anchor matches no heading in
    the target file. External links (http, https, mailto) are not checked.

    Anchors are derived the way GitHub renders them: link markup is reduced to its text, the text is
    lowercased, punctuation other than hyphens and underscores is removed, spaces become hyphens, and
    repeated headings get -1, -2, ... suffixes. Fenced code blocks and inline code are ignored when
    finding links.
.PARAMETER Path
    Repository root to scan. Defaults to the parent of this script's folder.
.EXAMPLE
    ./Build/Test-DocLinks.ps1
.OUTPUTS
    None. Writes one line per problem and exits 1 if any are found, otherwise exits 0.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string] $Path = (Split-Path -Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'

function Get-MarkdownProse {
    # RETURNS THE TEXT WITH FENCED CODE BLOCKS AND INLINE CODE SPANS REMOVED
    param([string] $Text)
    $noFences = [regex]::Replace($Text, '(?ms)^[ \t]*(```|~~~).*?^[ \t]*\1[^\r\n]*$', '')
    return [regex]::Replace($noFences, '`[^`\r\n]*`', '')
}

function Get-HeadingAnchor {
    # GITHUB-STYLE SLUGS FOR EVERY HEADING IN A FILE, WITH -N SUFFIXES FOR DUPLICATES
    param([string] $FilePath)
    $text = Get-Content -LiteralPath $FilePath -Raw
    $noFences = [regex]::Replace($text, '(?ms)^[ \t]*(```|~~~).*?^[ \t]*\1[^\r\n]*$', '')
    $seen = @{}
    $anchors = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($match in [regex]::Matches($noFences, '(?m)^#{1,6}[ \t]+(.+?)[ \t]*#*[ \t]*$')) {
        $heading = [regex]::Replace($match.Groups[1].Value, '\[([^\]]*)\]\([^)]*\)', '$1')
        $slug = ($heading.ToLowerInvariant() -replace '[^\p{L}\p{N}\s_-]', '') -replace '\s', '-'
        if ($seen.ContainsKey($slug)) {
            $seen[$slug]++
            [void] $anchors.Add("$slug-$($seen[$slug])")
        }
        else {
            $seen[$slug] = 0
            [void] $anchors.Add($slug)
        }
    }
    return , $anchors
}

$root = (Resolve-Path -LiteralPath $Path).Path
$skip = [regex] '[\\/](\.git|\.agent-tmp)([\\/]|$)'
$files = Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.md' -Force |
    Where-Object { -not $skip.IsMatch($_.FullName.Substring($root.Length)) }

$anchorCache = @{}
$problems = [System.Collections.Generic.List[string]]::new()
$linkCount = 0

foreach ($file in $files) {
    $relativeFile = [System.IO.Path]::GetRelativePath($root, $file.FullName)
    $prose = Get-MarkdownProse -Text (Get-Content -LiteralPath $file.FullName -Raw)
    foreach ($match in [regex]::Matches($prose, '\]\(([^)\s]*)\)')) {
        $target = $match.Groups[1].Value
        if ($target -match '^(https?|mailto):' -or [string]::IsNullOrEmpty($target)) { continue }
        $linkCount++

        $pathPart, $anchor = $target -split '#', 2
        $targetPath = if ($pathPart) {
            [System.IO.Path]::GetFullPath((Join-Path -Path $file.DirectoryName -ChildPath ([uri]::UnescapeDataString($pathPart))))
        }
        else { $file.FullName }

        if (-not (Test-Path -LiteralPath $targetPath)) {
            $problems.Add("${relativeFile}: missing target '$target'")
            continue
        }
        if ($anchor) {
            if (Test-Path -LiteralPath $targetPath -PathType Container) {
                $problems.Add("${relativeFile}: anchor on a folder '$target'")
                continue
            }
            if (-not $anchorCache.ContainsKey($targetPath)) { $anchorCache[$targetPath] = Get-HeadingAnchor -FilePath $targetPath }
            if (-not $anchorCache[$targetPath].Contains($anchor)) {
                $problems.Add("${relativeFile}: no heading for anchor '$target'")
            }
        }
    }
}

Write-Output "Checked $linkCount relative links in $(@($files).Count) Markdown files."
if ($problems.Count -gt 0) {
    $problems | ForEach-Object { Write-Output "  $_" }
    Write-Output "$($problems.Count) broken link(s)."
    exit 1
}
Write-Output 'No broken links.'
