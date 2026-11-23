function ConvertTo-McpJson {
    <#
    .SYNOPSIS
        Serializes a value to compact JSON, failing instead of truncating.
    .DESCRIPTION
        ConvertTo-Json cuts a value off at -Depth and reports it only as a warning, which would send the client a broken
        result and put text on a stream next to the protocol. This captures the warning silently and raises an error
        instead, so the caller never sees partial output. Depth is 32.
    .PARAMETER InputObject
        The value to serialize.
    .INPUTS
        None.
    .OUTPUTS
        System.String.
    .EXAMPLE
        PS C:\> ConvertTo-McpJson -InputObject ([ordered]@{ a = 1 })
        Returns {"a":1}.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'The value to serialize')]
        [System.Object] $InputObject
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        $jsonParams = @{
            InputObject     = $InputObject
            Compress        = $true
            Depth           = 32
            WarningAction   = 'SilentlyContinue'
            WarningVariable = 'serializeWarning'
        }
        $json = ConvertTo-Json @jsonParams
        if ($serializeWarning) {
            $truncated = [System.InvalidOperationException]::new('The value could not be serialized without truncation.')
            Write-Error -Exception $truncated -ErrorAction 'Stop'
        }
        $json
    }
}
