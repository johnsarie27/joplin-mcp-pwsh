function Test-ToolSchema {
    <#
    .SYNOPSIS
        Checks one node of a tool's input schema, and recurses into its properties and items.
    .DESCRIPTION
        Helper for Register-JoplinTool. A schema may use only the keywords Test-ToolArgument enforces, so the schema
        tools/list publishes never promises a constraint the server does not check. The annotations description and
        default are allowed too, and a default must itself satisfy the node's schema. Every node must declare one
        supported type as a string. Every object node must set additionalProperties to false, may not have an empty
        required array, and may only require properties it declares. Raises an error naming the first problem found.
    .PARAMETER ToolName
        The tool being registered, for the error message.
    .PARAMETER Schema
        The schema node.
    .PARAMETER Path
        Where the node sits in the input schema, for the error message.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .EXAMPLE
        PS C:\> Test-ToolSchema -ToolName 'get_note' -Schema @{ type = 'string'; format = 'uuid' } -Path 'inputSchema.properties.id'
        Raises an error: format is not a supported keyword.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'The tool being registered')]
        [System.String] $ToolName,

        [Parameter(Mandatory, HelpMessage = 'The schema node')]
        [AllowNull()]
        [System.Object] $Schema,

        [Parameter(Mandatory, HelpMessage = 'Where the node sits in the input schema')]
        [System.String] $Path
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        # THE KEYWORDS Test-JsonValue ENFORCES, BY TYPE. ANYTHING ELSE WOULD BE PUBLISHED BUT NOT CHECKED
        $keywordsByType = @{
            object  = @('properties', 'required', 'additionalProperties')
            array   = @('items')
            string  = @('pattern', 'minLength', 'maxLength')
            integer = @('minimum', 'maximum')
            number  = @('minimum', 'maximum')
            boolean = @()
        }
        if ($Schema -isnot [System.Collections.IDictionary]) {
            Write-Error -Message ('Tool [{0}]: {1} must be a schema object.' -f $ToolName, $Path) -ErrorAction 'Stop'
        }
        $type = $Schema['type']
        if ($type -isnot [System.String] -or $type -cnotin @($keywordsByType.Keys)) {
            $message = 'Tool [{0}]: {1} must declare one type: object, array, string, integer, number or boolean.' -f $ToolName, $Path
            Write-Error -Message $message -ErrorAction 'Stop'
        }
        # description AND default ARE ANNOTATIONS, NOT CONSTRAINTS. THE HANDLER APPLIES A DEFAULT (docs/design/tools.md)
        $allowed = @('type', 'description', 'default', 'enum') + $keywordsByType[$type]
        foreach ($keyword in @($Schema.Keys)) {
            if ($keyword -cnotin $allowed) {
                $message = 'Tool [{0}]: {1} uses [{2}], which is not supported for type {3}.' -f $ToolName, $Path, $keyword, $type
                Write-Error -Message $message -ErrorAction 'Stop'
            }
        }
        if ($type -ceq 'object') {
            if ($Schema['additionalProperties'] -isnot [System.Boolean] -or $Schema['additionalProperties']) {
                $message = 'Tool [{0}]: {1} must set additionalProperties to $false.' -f $ToolName, $Path
                Write-Error -Message $message -ErrorAction 'Stop'
            }
            $properties = $Schema['properties']
            if ($null -eq $properties) {
                $properties = @{}
            }
            if ($properties -isnot [System.Collections.IDictionary]) {
                Write-Error -Message ('Tool [{0}]: {1}.properties must be an object.' -f $ToolName, $Path) -ErrorAction 'Stop'
            }
            $propertyNames = [System.String[]] @($properties.Keys)
            if ($Schema.Contains('required')) {
                $required = @($Schema['required'])
                if ($required.Count -eq 0) {
                    Write-Error -Message ('Tool [{0}]: {1}.required must be omitted rather than empty.' -f $ToolName, $Path) -ErrorAction 'Stop'
                }
                foreach ($requiredName in $required) {
                    if ($requiredName -cnotin $propertyNames) {
                        $message = 'Tool [{0}]: {1}.required names [{2}], which is not declared in properties.' -f $ToolName, $Path, $requiredName
                        Write-Error -Message $message -ErrorAction 'Stop'
                    }
                }
            }
            foreach ($propertyName in $propertyNames) {
                Test-ToolSchema -ToolName $ToolName -Schema $properties[$propertyName] -Path ('{0}.properties.{1}' -f $Path, $propertyName)
            }
        }
        if ($type -ceq 'array' -and $Schema.Contains('items')) {
            Test-ToolSchema -ToolName $ToolName -Schema $Schema['items'] -Path ('{0}.items' -f $Path)
        }
        # CHECKED AFTER THE NODE ITSELF, SO THE DEFAULT IS TESTED AGAINST A SCHEMA ALREADY KNOWN TO BE VALID
        if ($Schema.Contains('default')) {
            try {
                Test-JsonValue -Schema $Schema -Value $Schema['default'] -Path ('{0}.default' -f $Path)
            }
            catch [McpProtocolError] {
                $message = 'Tool [{0}]: {1}.default does not satisfy its own schema.' -f $ToolName, $Path
                Write-Error -Message $message -ErrorAction 'Stop'
            }
        }
    }
}
