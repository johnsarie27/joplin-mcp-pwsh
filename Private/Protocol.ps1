# ==============================================================================
# Filename: Protocol.ps1
# Author:   Justin Johns
# ==============================================================================

function ConvertTo-McpJson {
    <#
    .SYNOPSIS
        Serializes a value to compact JSON, failing instead of truncating.
    .DESCRIPTION
        ConvertTo-Json cuts a value off at -Depth and reports it only as a warning, which would send the client a broken
        result and put text on a stream next to the protocol. This captures the warning silently and throws instead, so
        the caller never sees partial output. Depth is 32.
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
        $json = ConvertTo-Json -InputObject $InputObject -Compress -Depth 32 -WarningAction 'SilentlyContinue' -WarningVariable 'serializeWarning'
        if ($serializeWarning) {
            throw [System.InvalidOperationException]::new('The value could not be serialized without truncation.')
        }
        $json
    }
}

function Write-McpMessage {
    <#
    .SYNOPSIS
        Writes one JSON-RPC message to the protocol stream as a single line.
    .DESCRIPTION
        The only place a protocol message is serialized and written. The message is built and serialized first, so a
        serialization failure writes nothing, and the line is written with one call. Serialization fails, rather than
        truncating, when the message is nested deeper than 32 levels (see ConvertTo-McpJson).
    .PARAMETER Writer
        The protocol stream: the dedicated stdout writer, or a StringWriter in tests.
    .PARAMETER Message
        The JSON-RPC message to write.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .EXAMPLE
        PS C:\> Write-McpMessage -Writer $writer -Message ([ordered]@{ jsonrpc = '2.0'; id = 1; result = @{} })
        Writes {"jsonrpc":"2.0","id":1,"result":{}} and a line feed.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'The protocol stream')]
        [System.IO.TextWriter] $Writer,

        [Parameter(Mandatory, HelpMessage = 'The JSON-RPC message to write')]
        [System.Collections.IDictionary] $Message
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        $json = ConvertTo-McpJson -InputObject $Message
        $Writer.WriteLine($json)
        $Writer.Flush()
    }
}

function Write-McpResult {
    <#
    .SYNOPSIS
        Writes a JSON-RPC success response.
    .DESCRIPTION
        Wraps a result in a JSON-RPC 2.0 response envelope with the request's id, and writes it as one line.
    .PARAMETER Writer
        The protocol stream.
    .PARAMETER Id
        The id of the request being answered, exactly as the client sent it.
    .PARAMETER Result
        The result object.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .EXAMPLE
        PS C:\> Write-McpResult -Writer $writer -Id 7 -Result @{}
        Writes {"jsonrpc":"2.0","id":7,"result":{}}.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'The protocol stream')]
        [System.IO.TextWriter] $Writer,

        [Parameter(Mandatory, HelpMessage = 'The id of the request being answered')]
        [AllowNull()]
        [System.Object] $Id,

        [Parameter(Mandatory, HelpMessage = 'The result object')]
        [System.Collections.IDictionary] $Result
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        Write-McpMessage -Writer $Writer -Message ([ordered]@{ jsonrpc = '2.0'; id = $Id; result = $Result })
    }
}

function Write-McpError {
    <#
    .SYNOPSIS
        Writes a JSON-RPC error response.
    .DESCRIPTION
        Wraps an error code and message in a JSON-RPC 2.0 error envelope and writes it as one line. The code is
        always an integer. Use an id of null when the request's id is unknown, such as a parse error.
    .PARAMETER Writer
        The protocol stream.
    .PARAMETER Id
        The id of the request being answered, or null when it cannot be known.
    .PARAMETER Code
        The JSON-RPC error code, for example -32602.
    .PARAMETER Message
        A short message safe to show the client. Never raw exception text.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .EXAMPLE
        PS C:\> Write-McpError -Writer $writer -Id $null -Code -32700 -Message 'Parse error'
        Writes {"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"Parse error"}}.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'The protocol stream')]
        [System.IO.TextWriter] $Writer,

        [Parameter(Mandatory, HelpMessage = 'The id of the request being answered, or null')]
        [AllowNull()]
        [System.Object] $Id,

        [Parameter(Mandatory, HelpMessage = 'The JSON-RPC error code')]
        [System.Int32] $Code,

        [Parameter(Mandatory, HelpMessage = 'A short message safe to show the client')]
        [System.String] $Message
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        $errorBody = [ordered]@{ code = $Code; message = $Message }
        Write-McpMessage -Writer $Writer -Message ([ordered]@{ jsonrpc = '2.0'; id = $Id; error = $errorBody })
    }
}

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
            throw [McpProtocolError]::new(-32602, 'Invalid params: initialize requires a protocolVersion string.')
        }
        $requested = $Params['protocolVersion']
        $negotiated = if ($requested -cin $script:SupportedProtocolVersions) { $requested } else { $script:SupportedProtocolVersions[-1] }
        [ordered]@{
            protocolVersion = $negotiated
            capabilities    = [ordered]@{ tools = [ordered]@{} }
            serverInfo      = [ordered]@{ name = 'joplin-mcp-pwsh'; version = $ExecutionContext.SessionState.Module.Version.ToString() }
        }
    }
}

function Invoke-HandlerIsolated {
    <#
    .SYNOPSIS
        Runs a tool handler so that nothing it writes can reach the protocol stream.
    .DESCRIPTION
        Merges every stream of the handler into the output, then sends each information, warning, verbose, debug and
        error record to stderr and keeps only the success output. The handler must produce exactly one value; any other
        count throws, so a stray pipeline value is never mistaken for the result. The handler is invoked as a script
        block, never looked up by name.
    .PARAMETER Handler
        The registered handler script block.
    .PARAMETER Arguments
        The validated tool arguments, passed as the handler's first argument.
    .PARAMETER Access
        The access object, passed as the handler's second argument.
    .INPUTS
        None.
    .OUTPUTS
        System.Object.
    .EXAMPLE
        PS C:\> Invoke-HandlerIsolated -Handler { param($Arguments, $Access) Write-Host 'noise'; 'result' } -Arguments @{} -Access $access
        Returns 'result' and writes the Write-Host text to stderr.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.Object])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'The registered handler script block')]
        [System.Management.Automation.ScriptBlock] $Handler,

        [Parameter(Mandatory, HelpMessage = 'The validated tool arguments')]
        [System.Collections.IDictionary] $Arguments,

        [Parameter(Mandatory, HelpMessage = 'The access object')]
        [NotebookAccess] $Access
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        # PowerShell HAS NO 3>&2-STYLE REDIRECTION (A PARSE ERROR), SO MERGE EVERYTHING AND SPLIT BY RECORD TYPE
        $items = @(& $Handler $Arguments $Access *>&1)
        # @() SO A SINGLE VALUE STAYS AN ARRAY: INDEXING A BARE STRING WOULD RETURN ITS FIRST CHARACTER
        $output = @(foreach ($item in $items) {
            if ($item -is [System.Management.Automation.InformationRecord] -or
                $item -is [System.Management.Automation.WarningRecord] -or
                $item -is [System.Management.Automation.VerboseRecord] -or
                $item -is [System.Management.Automation.DebugRecord] -or
                $item -is [System.Management.Automation.ErrorRecord]) {
                [System.Console]::Error.WriteLine(('[diag:{0}] {1}' -f $item.GetType().Name, $item))
            }
            else {
                , $item
            }
        })
        if ($output.Count -ne 1) {
            throw [System.InvalidOperationException]::new('A tool handler must return exactly one value.')
        }
        $output[0]
    }
}

function Invoke-ToolCall {
    <#
    .SYNOPSIS
        Runs a tools/call request and builds its result.
    .DESCRIPTION
        Looks the tool up in the registry, validates the arguments against its schema, applies the access gate for the
        tool's declared access level, and runs the handler isolated. Protocol problems (unknown tool, bad arguments)
        throw McpProtocolError with code -32602. Failures while running the tool come back as a normal result with
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
            throw [McpProtocolError]::new(-32602, 'Invalid params: tools/call requires a tool name.')
        }
        # THE REGISTRY IS AN ORDINAL DICTIONARY, SO THE NAME IS NEVER RESOLVED AS AN ALIAS OR COMMAND
        $tool = $null
        if (-not $script:ToolRegistry.TryGetValue($Params['name'], [ref] $tool)) {
            throw [McpProtocolError]::new(-32602, 'Unknown tool.')
        }
        $arguments = if ($Params.Contains('arguments')) { $Params['arguments'] } else { @{} }
        Test-ToolArgument -Schema $tool.InputSchema -Arguments $arguments

        try {
            $access = Resolve-NotebookAccess
            if ($tool.Access -in [JoplinToolAccess]::Read, [JoplinToolAccess]::Write) {
                if (-not $access.HasAnyAccess()) {
                    throw [NotebookAccessError]::new('No notebooks are configured for access. Add a `notebooks` list to the config file.')
                }
            }
            elseif ($tool.Access -eq [JoplinToolAccess]::ManageTags) {
                if (-not $access.CanManageTags()) {
                    throw [NotebookAccessError]::new('Tag management is not permitted by the configured access.')
                }
            }
            # CreateNotebook IS CHECKED IN THE HANDLER: CanWrite(parent_id) OR CanCreateRootNotebook()
            $text = Invoke-HandlerIsolated -Handler $tool.Handler -Arguments $arguments -Access $access
            [ordered]@{ content = @([ordered]@{ type = 'text'; text = [System.String] $text }); isError = $false }
        }
        catch {
            [ordered]@{ content = @([ordered]@{ type = 'text'; text = (Get-SafeErrorMessage -ErrorRecord $_) }); isError = $true }
        }
    }
}

function Invoke-McpLine {
    <#
    .SYNOPSIS
        Handles one line of input: parses it, dispatches it and writes at most one response.
    .DESCRIPTION
        Malformed JSON gets -32700 with a null id, and a message that is not a valid JSON-RPC 2.0 request gets -32600,
        so the client is never left waiting. A message with no id key is a notification and is never answered, even
        when it fails. An unexpected exception becomes -32603 with a generic message; only its type name goes to stderr.
        The input line is never echoed anywhere: a parse failure logs only the line's length.
    .PARAMETER Line
        One line of input.
    .PARAMETER Writer
        The protocol stream.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .EXAMPLE
        PS C:\> Invoke-McpLine -Line '{"jsonrpc":"2.0","id":1,"method":"ping"}' -Writer $writer
        Writes {"jsonrpc":"2.0","id":1,"result":{}}.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'One line of input')]
        [System.String] $Line,

        [Parameter(Mandatory, HelpMessage = 'The protocol stream')]
        [System.IO.TextWriter] $Writer
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        try {
            # -NoEnumerate: A JSON ARRAY MUST STAY ONE VALUE, NOT BE UNROLLED INTO ITS ELEMENTS, SO IT IS REJECTED AS A BATCH
            $message = ConvertFrom-Json -InputObject $Line -AsHashtable -NoEnumerate -Depth 32 -ErrorAction 'Stop'
        }
        catch {
            [System.Console]::Error.WriteLine(('[diag] Parse error: input of length {0}' -f $Line.Length))
            Write-McpError -Writer $Writer -Id $null -Code -32700 -Message 'Parse error'
            return
        }

        $hasValidId = $false
        $id = $null
        if ($message -is [System.Collections.IDictionary] -and $message.Contains('id')) {
            $id = $message['id']
            $hasValidId = $id -is [System.String] -or $id -is [System.Int32] -or $id -is [System.Int64] -or $id -is [System.Double]
        }
        $isResponse = $message -is [System.Collections.IDictionary] -and -not $message.Contains('method') -and
        ($message.Contains('result') -or $message.Contains('error'))
        if ($isResponse) {
            # THE SERVER SENDS NO REQUESTS, SO A RESPONSE FROM THE CLIENT IS NOT AN ERROR; THERE IS NOTHING TO MATCH IT TO
            return
        }
        # jsonrpc MUST BE THE STRING '2.0'. -cne ALONE IS NOT ENOUGH: PowerShell CONVERTS '2.0' TO AN INTEGER TO COMPARE IT WITH ONE
        if ($message -isnot [System.Collections.IDictionary] -or $message['jsonrpc'] -isnot [System.String] -or $message['jsonrpc'] -cne '2.0' -or
            $message['method'] -isnot [System.String] -or ($message.Contains('id') -and -not $hasValidId)) {
            Write-McpError -Writer $Writer -Id $(if ($hasValidId) { $id } else { $null }) -Code -32600 -Message 'Invalid Request'
            return
        }

        # A NOTIFICATION IS A MESSAGE WITH NO id KEY, NOT ONE WHOSE id IS NULL
        $hasId = $message.Contains('id')
        try {
            $result = switch -CaseSensitive ($message['method']) {
                'initialize' { Get-InitializeResult -Params $message['params'] }
                'notifications/initialized' { $null }
                'ping' { [ordered]@{} }
                'tools/list' { [ordered]@{ tools = @(Get-ToolList) } }
                'tools/call' { Invoke-ToolCall -Params $message['params'] }
                default { throw [McpProtocolError]::new(-32601, 'Method not found.') }
            }
            if ($hasId) {
                Write-McpResult -Writer $Writer -Id $id -Result $(if ($null -eq $result) { [ordered]@{} } else { $result })
            }
        }
        catch [McpProtocolError] {
            if ($hasId) {
                Write-McpError -Writer $Writer -Id $id -Code $_.Exception.Code -Message $_.Exception.Message
            }
        }
        catch {
            # NEVER SURFACE RAW EXCEPTION TEXT: IT MAY CONTAIN THE REQUEST URI AND THE TOKEN
            [System.Console]::Error.WriteLine(('[diag] Unhandled: {0}' -f $_.Exception.GetType().Name))
            if ($hasId) {
                Write-McpError -Writer $Writer -Id $id -Code -32603 -Message 'Internal error'
            }
        }
    }
}

function Invoke-McpLoop {
    <#
    .SYNOPSIS
        Reads requests line by line until the input ends.
    .DESCRIPTION
        Takes the reader and writer as parameters, rather than opening the console, so tests can pass a StringReader
        and a StringWriter and assert the exact bytes written. A blank line is skipped. The loop ends promptly when the
        reader returns null at end of input. One bad line never stops it, because each line is handled on its own.
    .PARAMETER Reader
        Where requests come from, one JSON-RPC message per line.
    .PARAMETER Writer
        The protocol stream.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .EXAMPLE
        PS C:\> Invoke-McpLoop -Reader ([System.IO.StringReader]::new('{"jsonrpc":"2.0","id":1,"method":"ping"}')) -Writer $writer
        Answers the ping, then returns at the end of the input.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'Where requests come from')]
        [System.IO.TextReader] $Reader,

        [Parameter(Mandatory, HelpMessage = 'The protocol stream')]
        [System.IO.TextWriter] $Writer
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        while ($null -ne ($line = $Reader.ReadLine())) {
            if ([System.String]::IsNullOrWhiteSpace($line)) {
                continue
            }
            Invoke-McpLine -Line $line -Writer $Writer
        }
    }
}
