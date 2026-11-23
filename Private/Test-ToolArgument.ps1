function Test-ToolArgument {
    <#
    .SYNOPSIS
        Checks a tool call's arguments against the tool's input schema, strictly.
    .DESCRIPTION
        Raises a McpProtocolError with code -32602 for the first problem found, so the handler never runs. Arguments
        must be a JSON object, never an array that would bind positionally. Unknown properties are rejected, including
        PowerShell common parameters. JSON types must match exactly: a string is never accepted for an integer, and
        a string such as "false" is never accepted for a boolean. Property names, enum values and patterns are
        compared case-sensitively. Supports type, enum, pattern, minLength, maxLength, minimum, maximum, items,
        properties, required and additionalProperties.
    .PARAMETER Schema
        The tool's input schema.
    .PARAMETER Arguments
        The arguments from the tools/call request, as parsed from JSON.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .EXAMPLE
        PS C:\> Test-ToolArgument -Schema $tool.InputSchema -Arguments @{ query = 'tax' }
        Returns nothing when the arguments are valid, and raises McpProtocolError otherwise.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'The tool input schema')]
        [System.Collections.IDictionary] $Schema,

        [Parameter(Mandatory, HelpMessage = 'The arguments from the tools/call request')]
        [AllowNull()]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [System.Object] $Arguments
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        Test-JsonValue -Schema $Schema -Value $Arguments -Path 'arguments'
    }
}
