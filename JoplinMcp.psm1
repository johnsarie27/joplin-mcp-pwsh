# ==============================================================================
# Filename: JoplinMcp.psm1
# Author:   Justin Johns
# ==============================================================================

# SET DIRECTORIES
$dirs = @(
    (Join-Path -Path $PSScriptRoot -ChildPath 'Public')
    (Join-Path -Path $PSScriptRoot -ChildPath 'Private')
)

# REGISTERED TOOLS, KEYED BY EXACT TOOL NAME. ORDINAL, SO A TOOL NAMED 'Echo' IS NOT FOUND BY 'echo'. A TOOL IS
# CALLABLE ONLY IF IT IS IN HERE; NOTHING IS EVER LOOKED UP AS A COMMAND NAME (SECURITY-MODEL.MD)
$script:ToolRegistry = [System.Collections.Generic.Dictionary[System.String, System.Collections.IDictionary]]::new(
    [System.StringComparer]::Ordinal
)

# MCP PROTOCOL VERSIONS THIS SERVER NEGOTIATES, OLDEST FIRST; THE LAST IS THE LATEST. PROVISIONAL UNTIL ISSUE #15
# PINS THE LIST AGAINST THE MCP SPEC
$script:SupportedProtocolVersions = @('2025-06-18')

# DOT SOURCE ALL PS SCRIPTS. Get-ChildItem SORTS BY NAME, AND A CLASS MUST BE DEFINED BEFORE A FILE USES IT AS A TYPE
# LITERAL IN A PARAMETER, SO Private/Access.ps1 AND Private/Errors.ps1 SORT BEFORE THE FILES THAT NEED THEM
foreach ($file in (Get-ChildItem -Path $dirs -Filter '*.ps1' -ErrorAction SilentlyContinue)) {
    . $file.FullName
}

# EXPORT MEMBERS
# FunctionsToExport in the manifest is the authoritative export list.
