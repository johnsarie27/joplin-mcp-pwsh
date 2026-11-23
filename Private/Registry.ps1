# ==============================================================================
# Filename: Registry.ps1
# Author:   Justin Johns
# ==============================================================================

function Register-JoplinTool {
    <#
    .SYNOPSIS
        Registers an MCP tool.
    .DESCRIPTION
        Adds a tool to the registry that tools/list publishes and tools/call dispatches from. Registration fails, and
        nothing is added, unless the tool declares an access level, a description of useful length and a strict input
        schema: an object schema with additionalProperties set to false, no empty required array, and no property
        named like a PowerShell common parameter. A tool name can be registered once.
    .PARAMETER Name
        Tool name: lowercase letters, digits and underscores, starting with a letter.
    .PARAMETER Description
        What the tool does, shown to the model. At least 20 characters.
    .PARAMETER Access
        What the tool needs from the access object: Read, Write, CreateNotebook or ManageTags.
    .PARAMETER InputSchema
        JSON Schema of the tool's arguments, as a hashtable. Must be an object schema with additionalProperties = $false.
    .PARAMETER Handler
        Script block that receives the validated arguments (hashtable) and the access object, and returns exactly one
        value, normally a string.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .EXAMPLE
        PS C:\> $schema = @{ type = 'object'; properties = @{}; additionalProperties = $false }
        PS C:\> Register-JoplinTool -Name 'ping_joplin' -Description 'Check that the server is up.' -Access Read -InputSchema $schema -Handler { 'pong' }
        Registers a tool that takes no arguments.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'Tool name: lowercase letters, digits and underscores')]
        # (?-i): ValidatePattern IGNORES CASE BY DEFAULT, WHICH WOULD LET 'Search' THROUGH
        [ValidatePattern('(?-i)^[a-z][a-z0-9_]{0,63}$')]
        [System.String] $Name,

        [Parameter(Mandatory, HelpMessage = 'What the tool does, shown to the model')]
        [ValidateScript({ $_.Trim().Length -ge 20 }, ErrorMessage = 'A tool description must be at least 20 characters.')]
        [System.String] $Description,

        [Parameter(Mandatory, HelpMessage = 'Read, Write, CreateNotebook or ManageTags')]
        [JoplinToolAccess] $Access,

        [Parameter(Mandatory, HelpMessage = 'JSON Schema of the tool arguments, as a hashtable')]
        [System.Collections.IDictionary] $InputSchema,

        [Parameter(Mandatory, HelpMessage = 'Script block that receives the arguments and the access object')]
        [System.Management.Automation.ScriptBlock] $Handler
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        if ($script:ToolRegistry.ContainsKey($Name)) {
            Write-Error -Message ('Tool [{0}] is already registered.' -f $Name) -ErrorAction 'Stop'
        }
        if ($InputSchema['type'] -cne 'object') {
            Write-Error -Message ('Tool [{0}]: the input schema must have type "object".' -f $Name) -ErrorAction 'Stop'
        }
        if ($InputSchema['additionalProperties'] -isnot [System.Boolean] -or $InputSchema['additionalProperties']) {
            Write-Error -Message ('Tool [{0}]: the input schema must set additionalProperties to $false.' -f $Name) -ErrorAction 'Stop'
        }
        $properties = $InputSchema['properties']
        if ($null -eq $properties) {
            $properties = @{}
        }
        $propertyNames = [System.String[]] @($properties.Keys)
        # A COMMON PARAMETER NAME IN THE SCHEMA WOULD BE PUBLISHED AND ACCEPTED. DERIVED AT RUNTIME: A HAND-WRITTEN LIST
        # MISSES ProgressAction, ADDED IN 7.4
        $commonParameters = @([System.Management.Automation.PSCmdlet]::CommonParameters) + @([System.Management.Automation.PSCmdlet]::OptionalCommonParameters)
        foreach ($propertyName in $propertyNames) {
            if ($propertyName -in $commonParameters) {
                Write-Error -Message ('Tool [{0}]: property [{1}] is a PowerShell common parameter name.' -f $Name, $propertyName) -ErrorAction 'Stop'
            }
        }
        if ($InputSchema.Contains('required')) {
            $required = @($InputSchema['required'])
            if ($required.Count -eq 0) {
                Write-Error -Message ('Tool [{0}]: required must be omitted rather than empty.' -f $Name) -ErrorAction 'Stop'
            }
            foreach ($requiredName in $required) {
                if ($requiredName -cnotin $propertyNames) {
                    Write-Error -Message ('Tool [{0}]: required property [{1}] is not declared in properties.' -f $Name, $requiredName) -ErrorAction 'Stop'
                }
            }
        }
        $script:ToolRegistry.Add($Name, [ordered]@{
                Name        = $Name
                Description = $Description
                Access      = $Access
                InputSchema = $InputSchema
                Handler     = $Handler
            })
    }
}

function ConvertTo-SortedTree {
    <#
    .SYNOPSIS
        Copies a tree of hashtables and arrays with every dictionary's keys in ordinal order.
    .DESCRIPTION
        Hashtable key order is not stable, so a schema serialized as is would differ from run to run and break a
        golden-file comparison. Array order is kept, because it can carry meaning (required, enum).
    .PARAMETER InputObject
        The value to copy: a dictionary, an array, or a scalar.
    .INPUTS
        System.Object.
    .OUTPUTS
        System.Object.
    .EXAMPLE
        PS C:\> ConvertTo-SortedTree -InputObject @{ b = 1; a = @{ d = 1; c = 2 } } | ConvertTo-Json -Compress
        Returns {"a":{"c":2,"d":1},"b":1}.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.Object])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'The value to copy')]
        [AllowNull()]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [System.Object] $InputObject
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        if ($InputObject -is [System.Collections.IDictionary]) {
            $keys = [System.String[]] @($InputObject.Keys)
            [System.Array]::Sort($keys, [System.StringComparer]::Ordinal)
            $sorted = [ordered]@{}
            foreach ($key in $keys) {
                $sorted[$key] = ConvertTo-SortedTree -InputObject $InputObject[$key]
            }
            return $sorted
        }
        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [System.String]) {
            $items = [System.Collections.Generic.List[System.Object]]::new()
            foreach ($item in $InputObject) {
                $items.Add((ConvertTo-SortedTree -InputObject $item))
            }
            # THE COMMA KEEPS A ONE-ITEM OR EMPTY ARRAY FROM BEING UNROLLED INTO THE PIPELINE
            return , $items.ToArray()
        }
        $InputObject
    }
}

function Get-ToolList {
    <#
    .SYNOPSIS
        Returns the registered tools in the shape tools/list publishes.
    .DESCRIPTION
        One entry per registered tool, ordered by name, with name, description, inputSchema and annotations. A tool
        that needs Read access is marked readOnlyHint true; every other tool is marked false. Schema keys are sorted so
        the output is the same on every run.
    .INPUTS
        None.
    .OUTPUTS
        System.Collections.Specialized.OrderedDictionary.
    .EXAMPLE
        PS C:\> Get-ToolList
        Returns the published form of every registered tool.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    Param()
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        $names = [System.String[]] @($script:ToolRegistry.Keys)
        [System.Array]::Sort($names, [System.StringComparer]::Ordinal)
        foreach ($name in $names) {
            $tool = $script:ToolRegistry[$name]
            [ordered]@{
                name        = $tool.Name
                description = $tool.Description
                inputSchema = ConvertTo-SortedTree -InputObject $tool.InputSchema
                annotations = [ordered]@{ readOnlyHint = ($tool.Access -eq [JoplinToolAccess]::Read) }
            }
        }
    }
}

function Test-ToolArgument {
    <#
    .SYNOPSIS
        Checks a tool call's arguments against the tool's input schema, strictly.
    .DESCRIPTION
        Throws a McpProtocolError with code -32602 for the first problem found, so the handler never runs. Arguments
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
        Returns nothing when the arguments are valid, and throws McpProtocolError otherwise.
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

function Test-JsonValue {
    <#
    .SYNOPSIS
        Checks one value against one schema node, and recurses into objects and arrays.
    .DESCRIPTION
        Helper for Test-ToolArgument. Throws a McpProtocolError with code -32602 naming the path of the first value that
        does not match. The message never repeats the value itself, only the path.
    .PARAMETER Schema
        The schema node.
    .PARAMETER Value
        The value to check.
    .PARAMETER Path
        Where the value sits in the arguments, for the error message.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .EXAMPLE
        PS C:\> Test-JsonValue -Schema @{ type = 'integer'; minimum = 1 } -Value 0 -Path 'arguments.limit'
        Throws McpProtocolError: arguments.limit must be at least 1.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'The schema node')]
        [System.Collections.IDictionary] $Schema,

        [Parameter(Mandatory, HelpMessage = 'The value to check')]
        [AllowNull()]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [System.Object] $Value,

        [Parameter(Mandatory, HelpMessage = 'Where the value sits in the arguments')]
        [System.String] $Path
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        $type = $Schema['type']
        # A BOOLEAN IS NOT A NUMBER AND A STRING IS NOT EITHER; THESE TESTS ARE EXACT, NEVER PowerShell's COERCION
        $typeIsMet = switch -CaseSensitive ($type) {
            'object' { $Value -is [System.Collections.IDictionary] }
            'array' { $Value -is [System.Array] }
            'string' { $Value -is [System.String] }
            'boolean' { $Value -is [System.Boolean] }
            'integer' { $Value -is [System.Int32] -or $Value -is [System.Int64] }
            'number' { $Value -is [System.Int32] -or $Value -is [System.Int64] -or $Value -is [System.Double] -or $Value -is [System.Decimal] }
            default { $false }
        }
        if (-not $typeIsMet) {
            throw [McpProtocolError]::new(-32602, ('Invalid arguments: {0} must be of type {1}.' -f $Path, $type))
        }

        if ($Schema.Contains('enum') -and $Value -cnotin @($Schema['enum'])) {
            throw [McpProtocolError]::new(-32602, ('Invalid arguments: {0} is not one of the allowed values.' -f $Path))
        }
        if ($type -ceq 'string') {
            if ($Schema.Contains('pattern') -and $Value -cnotmatch $Schema['pattern']) {
                throw [McpProtocolError]::new(-32602, ('Invalid arguments: {0} does not match the required pattern.' -f $Path))
            }
            if ($Schema.Contains('minLength') -and $Value.Length -lt $Schema['minLength']) {
                throw [McpProtocolError]::new(-32602, ('Invalid arguments: {0} must be at least {1} characters.' -f $Path, $Schema['minLength']))
            }
            if ($Schema.Contains('maxLength') -and $Value.Length -gt $Schema['maxLength']) {
                throw [McpProtocolError]::new(-32602, ('Invalid arguments: {0} must be at most {1} characters.' -f $Path, $Schema['maxLength']))
            }
        }
        if ($type -ceq 'integer' -or $type -ceq 'number') {
            if ($Schema.Contains('minimum') -and $Value -lt $Schema['minimum']) {
                throw [McpProtocolError]::new(-32602, ('Invalid arguments: {0} must be at least {1}.' -f $Path, $Schema['minimum']))
            }
            if ($Schema.Contains('maximum') -and $Value -gt $Schema['maximum']) {
                throw [McpProtocolError]::new(-32602, ('Invalid arguments: {0} must be at most {1}.' -f $Path, $Schema['maximum']))
            }
        }
        if ($type -ceq 'array' -and $Schema.Contains('items')) {
            for ($i = 0; $i -lt $Value.Count; $i++) {
                Test-JsonValue -Schema $Schema['items'] -Value $Value[$i] -Path ('{0}[{1}]' -f $Path, $i)
            }
        }
        if ($type -ceq 'object') {
            $properties = $Schema['properties']
            $propertyNames = if ($properties) { [System.String[]] @($properties.Keys) } else { [System.String[]] @() }
            foreach ($key in @($Value.Keys)) {
                if ($key -cnotin $propertyNames) {
                    # THE NAME IS SHOWN SO THE CLIENT CAN FIX ITS CALL; LONG NAMES ARE CUT SO A HUGE KEY IS NOT ECHOED
                    $shown = if (([System.String] $key).Length -gt 64) { ([System.String] $key).Substring(0, 64) } else { [System.String] $key }
                    throw [McpProtocolError]::new(-32602, ('Invalid arguments: unknown property [{0}] in {1}.' -f $shown, $Path))
                }
            }
            foreach ($requiredName in @($Schema['required'])) {
                if ($null -ne $requiredName -and -not $Value.Contains($requiredName)) {
                    throw [McpProtocolError]::new(-32602, ('Invalid arguments: {0}.{1} is required.' -f $Path, $requiredName))
                }
            }
            foreach ($key in @($Value.Keys)) {
                Test-JsonValue -Schema $properties[$key] -Value $Value[$key] -Path ('{0}.{1}' -f $Path, $key)
            }
        }
    }
}
