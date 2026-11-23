# ==============================================================================
# Filename: JoplinMcp.psm1
# Author:   Justin Johns
# ==============================================================================

# SET DIRECTORIES
$classesPath = Join-Path -Path $PSScriptRoot -ChildPath 'Private', 'Classes.ps1'
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
New-Variable -Name 'supported_protocol_versions' -Option Constant -Value @('2025-06-18')

# DOT SOURCE ALL PS SCRIPTS. A CLASS MUST BE DEFINED BEFORE A FILE USES IT AS A TYPE IN A PARAMETER, SO EVERY CLASS LIVES
# IN Private/Classes.ps1, WHICH IS LOADED FIRST AND BY NAME, NEVER BY SORT ORDER (ADR 12)
. $classesPath
# NOT Get-ChildItem -Exclude: WITH A DIRECTORY AS -Path IT DROPS EVERY FILE, SO NO FUNCTION WOULD LOAD
$files = (Get-ChildItem -Path $dirs -Filter '*.ps1' -ErrorAction SilentlyContinue).Where({ $_.FullName -ne $classesPath })
foreach ($file in $files) { . $file.FullName }

# EXPORT MEMBERS
# FunctionsToExport in the manifest is the authoritative export list.
