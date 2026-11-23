function Register-JoplinTool {
    <#
    .SYNOPSIS
        Registers an MCP tool.
    .DESCRIPTION
        Adds a tool to the registry that tools/list publishes and tools/call dispatches from. Registration fails, and
        nothing is added, unless the tool declares an access level, a description of useful length and a strict input
        schema: an object schema with additionalProperties set to false, no empty required array, and no property
        named like a PowerShell common parameter. Every nested schema declares one supported type, uses only the
        keywords Test-ToolArgument enforces, and sets additionalProperties to false on every object (Test-ToolSchema).
        A tool name can be registered once.
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
        # (?-i) BECAUSE ValidatePattern IGNORES CASE BY DEFAULT, WHICH WOULD LET 'Search' THROUGH
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
        # EVERY NODE: SUPPORTED KEYWORDS ONLY, A DECLARED TYPE, additionalProperties FALSE, A VALID required
        Test-ToolSchema -ToolName $Name -Schema $InputSchema -Path 'inputSchema'
        $propertyNames = [System.String[]] @()
        if ($InputSchema['properties']) {
            $propertyNames = [System.String[]] @($InputSchema['properties'].Keys)
        }
        # A COMMON PARAMETER NAME IN THE SCHEMA WOULD BE PUBLISHED AND ACCEPTED. DERIVED AT RUNTIME: A HAND-WRITTEN LIST
        # MISSES ProgressAction, ADDED IN 7.4
        $commonParameters = @([System.Management.Automation.PSCmdlet]::CommonParameters) + @([System.Management.Automation.PSCmdlet]::OptionalCommonParameters)
        foreach ($propertyName in $propertyNames) {
            if ($propertyName -in $commonParameters) {
                Write-Error -Message ('Tool [{0}]: property [{1}] is a PowerShell common parameter name.' -f $Name, $propertyName) -ErrorAction 'Stop'
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
