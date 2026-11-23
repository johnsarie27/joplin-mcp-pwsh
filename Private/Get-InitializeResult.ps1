function Get-InitializeResult {
    <#
    .SYNOPSIS
        Builds the result of the initialize request.
    .DESCRIPTION
        Negotiates the protocol version: the client's version is echoed only if the server supports it, and otherwise
        the server's latest supported version is returned. Advertises only the tools capability.
    .PARAMETER Params
        The params of the initialize request.
    .INPUTS
        None.
    .OUTPUTS
        System.Collections.Specialized.OrderedDictionary.
    .EXAMPLE
        PS C:\> Get-InitializeResult -Params @{ protocolVersion = '1999-01-01' }
        Returns the server's latest supported protocolVersion, never the unsupported one asked for.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'The params of the initialize request')]
        [AllowNull()]
        [System.Object] $Params
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        if ($Params -isnot [System.Collections.IDictionary] -or $Params['protocolVersion'] -isnot [System.String]) {
            $invalid = [McpProtocolError]::new(-32602, 'Invalid params: initialize requires a protocolVersion string.')
            Write-Error -Exception $invalid -ErrorAction 'Stop'
        }
        $negotiated = $supported_protocol_versions[-1]
        if ($Params['protocolVersion'] -cin $supported_protocol_versions) {
            $negotiated = $Params['protocolVersion']
        }
        [ordered]@{
            protocolVersion = $negotiated
            capabilities    = [ordered]@{ tools = [ordered]@{} }
            serverInfo      = [ordered]@{ name = 'joplin-mcp-pwsh'; version = $ExecutionContext.SessionState.Module.Version.ToString() }
        }
    }
}
