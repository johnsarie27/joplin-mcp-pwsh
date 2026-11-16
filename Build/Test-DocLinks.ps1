#Requires -Version 7.4
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
.INPUTS
    None.
.OUTPUTS
    System.String. A summary line, then one line per broken link. Exits 1 if any link is broken,
    otherwise 0.
.EXAMPLE
    PS C:\> ./Build/Test-DocLinks.ps1
    Checks every Markdown file in the repository that contains this script.
.EXAMPLE
    PS C:\> ./Build/Test-DocLinks.ps1 -Path ./fixtures/docs
    Checks the Markdown files under a different folder.
.NOTES
    Status: Stable
    Run by .github/workflows/docs.yml as the required docs check.
#>
[CmdletBinding()]
[OutputType([System.String])]
Param(
    [Parameter(HelpMessage = 'Repository root to scan')]
    [ValidateScript({
        if (Test-Path -LiteralPath $_ -PathType 'Container') { $true }
        else { Write-Error -Message ('Folder not found: [{0}]' -f $_) -ErrorAction Stop }
    })]
    [System.String] $Path = (Split-Path -Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'

#region - FUNCTIONS ============================================================
# MATCHES A FENCED CODE BLOCK OPENED AND CLOSED BY THE SAME ``` OR ~~~ MARKER
$fencePattern = '(?ms)^[ \t]*(```|~~~).*?^[ \t]*\1[^\r\n]*$'

function Get-MarkdownProse {
    <#
    .SYNOPSIS
        Remove fenced code blocks and inline code spans from Markdown text.
    .PARAMETER Text
        Markdown text.
    .OUTPUTS
        System.String.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'Markdown text')]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String] $Text
    )
    ($Text -replace $fencePattern, '') -replace '`[^`\r\n]*`', ''
}

function Get-HeadingAnchor {
    <#
    .SYNOPSIS
        Get the GitHub-style anchor for every heading in a Markdown file.
    .DESCRIPTION
        Returns a set of anchors. A heading's anchor is its text with link markup reduced to the link
        text, lowercased, with punctuation other than hyphens and underscores removed and spaces
        replaced by hyphens. A repeated heading gets a -1, -2, ... suffix, as GitHub renders it.
    .PARAMETER FilePath
        Path of the Markdown file.
    .OUTPUTS
        System.Collections.Generic.HashSet[System.String].
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.HashSet[System.String]])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'Path of the Markdown file')]
        [ValidateNotNullOrEmpty()]
        [System.String] $FilePath
    )
    $text = (Get-Content -LiteralPath $FilePath -Raw) -replace $fencePattern, ''
    $seen = @{}
    $anchors = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::Ordinal)
    $headings = Select-String -InputObject $text -Pattern '(?m)^#{1,6}[ \t]+(.+?)[ \t]*#*[ \t]*$' -AllMatches

    foreach ($match in $headings.Matches) {
        # REDUCE LINKS TO THEIR TEXT, THEN SLUG THE HEADING
        $heading = $match.Groups[1].Value -replace '\[([^\]]*)\]\([^)]*\)', '$1'
        $slug = ($heading.ToLowerInvariant() -replace '[^\p{L}\p{N}\s_-]', '') -replace '\s', '-'

        # REPEATED HEADINGS GET -1, -2, ... IN ORDER OF APPEARANCE
        if ($seen.ContainsKey($slug)) {
            $seen[$slug]++
            [void] $anchors.Add(('{0}-{1}' -f $slug, $seen[$slug]))
        }
        else {
            $seen[$slug] = 0
            [void] $anchors.Add($slug)
        }
    }
    Write-Output -InputObject $anchors -NoEnumerate
}

#endregion =====================================================================


#region - CHECK LINKS ==========================================================
# FIND EVERY MARKDOWN FILE OUTSIDE .git AND .agent-tmp
$root = (Resolve-Path -LiteralPath $Path).Path
$childItemParams = @{
    LiteralPath = $root
    Filter      = '*.md'
    Recurse     = $true
    File        = $true
    Force       = $true
}
$skipPattern = '[\\/](\.git|\.agent-tmp)([\\/]|$)'
$files = (Get-ChildItem @childItemParams).Where({ $PSItem.FullName.Substring($root.Length) -notmatch $skipPattern })

$anchorCache = @{}
$problems = [System.Collections.Generic.List[System.String]]::new()
$linkCount = 0

foreach ($file in $files) {
    $relativeFile = Resolve-Path -LiteralPath $file.FullName -Relative -RelativeBasePath $root
    $prose = Get-MarkdownProse -Text (Get-Content -LiteralPath $file.FullName -Raw)
    $links = Select-String -InputObject $prose -Pattern '\]\(([^)\s]*)\)' -AllMatches

    foreach ($match in $links.Matches) {
        # SKIP EXTERNAL AND EMPTY LINKS
        $target = $match.Groups[1].Value
        if ([System.String]::IsNullOrEmpty($target) -or $target -match '^(https?|mailto):') {
            continue
        }
        $linkCount++

        # RESOLVE THE TARGET; GetFullPath NORMALISES PATHS THAT MAY NOT EXIST, WHICH NO CMDLET DOES
        $pathPart, $anchor = $target -split '#', 2
        $targetPath = $file.FullName
        if ($pathPart) {
            $joinedPath = Join-Path -Path $file.DirectoryName -ChildPath ([System.Uri]::UnescapeDataString($pathPart))
            $targetPath = [System.IO.Path]::GetFullPath($joinedPath)
        }

        if (-not (Test-Path -LiteralPath $targetPath)) {
            $problems.Add(('{0}: missing target [{1}]' -f $relativeFile, $target))
            continue
        }
        if (-not $anchor) {
            continue
        }

        # AN ANCHOR MUST NAME A HEADING IN A FILE
        if (Test-Path -LiteralPath $targetPath -PathType 'Container') {
            $problems.Add(('{0}: anchor on a folder [{1}]' -f $relativeFile, $target))
            continue
        }
        if (-not $anchorCache.ContainsKey($targetPath)) {
            $anchorCache[$targetPath] = Get-HeadingAnchor -FilePath $targetPath
        }
        if (-not $anchorCache[$targetPath].Contains($anchor)) {
            $problems.Add(('{0}: no heading for anchor [{1}]' -f $relativeFile, $target))
        }
    }
}

#endregion =====================================================================


#region - REPORT ===============================================================
# SUMMARY, THEN ONE LINE PER PROBLEM; A NON-ZERO EXIT FAILS THE CI CHECK
Write-Output -InputObject ('Checked {0} relative links in {1} Markdown files.' -f $linkCount, $files.Count)
if ($problems.Count -gt 0) {
    foreach ($problem in $problems) {
        Write-Output -InputObject ('  {0}' -f $problem)
    }
    Write-Output -InputObject ('{0} broken link(s).' -f $problems.Count)
    exit 1
}
Write-Output -InputObject 'No broken links.'

#endregion =====================================================================
