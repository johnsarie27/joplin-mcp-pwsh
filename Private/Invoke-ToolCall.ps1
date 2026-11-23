function Invoke-ToolCall {
    <#
    .SYNOPSIS
        Runs a tools/call request and builds its result.
    .DESCRIPTION
        Looks the tool up in the registry, validates the arguments against its schema, applies the access gate for the
        tool's declared access level, and runs the handler isolated. Protocol problems (unknown tool, bad arguments)
        raise McpProtocolError with code -32602. Failures while running the tool come back as a normal result with
        isError true and a sanitized message, so the model can read it and recover.
    .PARAMETER Params
        The params of the tools/call request: the tool name and its arguments.
    .INPUTS
        None.
    .OUTPUTS
        System.Collections.Specialized.OrderedDictionary.
    .EXAMPLE
        PS C:\> Invoke-ToolCall -Params @{ name = 'search_notes'; arguments = @{ query = 'tax' } }
        Returns the tool's content, or an isError result if access is not granted.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'The params of the tools/call request')]
        [AllowNull()]
        [System.Object] $Params
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        if ($Params -isnot [System.Collections.IDictionary] -or $Params['name'] -isnot [System.String]) {
            $invalid = [McpProtocolError]::new(-32602, 'Invalid params: tools/call requires a tool name.')
            Write-Error -Exception $invalid -ErrorAction 'Stop'
        }
        # THE REGISTRY IS AN ORDINAL DICTIONARY, SO THE NAME IS NEVER RESOLVED AS AN ALIAS OR COMMAND
        $tool = $null
        if (-not $script:ToolRegistry.TryGetValue($Params['name'], [ref] $tool)) {
            Write-Error -Exception ([McpProtocolError]::new(-32602, 'Unknown tool.')) -ErrorAction 'Stop'
        }
        $arguments = @{}
        if ($Params.Contains('arguments')) {
            $arguments = $Params['arguments']
        }
        Test-ToolArgument -Schema $tool.InputSchema -Arguments $arguments
        try {
            $access = Resolve-NotebookAccess
            if ($tool.Access -in [JoplinToolAccess]::Read, [JoplinToolAccess]::Write) {
                if (-not $access.HasAnyAccess()) {
                    $message = 'No notebooks are configured for access. Add a `notebooks` list to the config file.'
                    Write-Error -Exception ([NotebookAccessError]::new($message)) -ErrorAction 'Stop'
                }
            }
            elseif ($tool.Access -eq [JoplinToolAccess]::ManageTags) {
                if (-not $access.CanManageTags()) {
                    $message = 'Tag management is not permitted by the configured access.'
                    Write-Error -Exception ([NotebookAccessError]::new($message)) -ErrorAction 'Stop'
                }
            }
            # CreateNotebook IS CHECKED IN THE HANDLER: CanWrite(parent_id) OR CanCreateRootNotebook()
            $handlerParams = @{
                Handler   = $tool.Handler
                Arguments = $arguments
                Access    = $access
            }
            $text = Invoke-HandlerIsolated @handlerParams
            [ordered]@{ content = @([ordered]@{ type = 'text'; text = [System.String] $text }); isError = $false }
        }
        catch {
            [ordered]@{ content = @([ordered]@{ type = 'text'; text = (Get-SafeErrorMessage -ErrorRecord $PSItem) }); isError = $true }
        }
    }
}
