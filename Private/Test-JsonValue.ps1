function Test-JsonValue {
    <#
    .SYNOPSIS
        Checks one value against one schema node, and recurses into objects and arrays.
    .DESCRIPTION
        Helper for Test-ToolArgument. Raises a McpProtocolError with code -32602 naming the path of the first value that
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
        Raises McpProtocolError: arguments.limit must be at least 1.
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
        # A BOOLEAN IS NOT A NUMBER AND A STRING IS NOT EITHER; THESE TESTS ARE EXACT, NEVER POWERSHELL'S COERCION
        $typeIsMet = switch -CaseSensitive ($type) {
            'object' { $Value -is [System.Collections.IDictionary] }
            'array' { $Value -is [System.Array] }
            'string' { $Value -is [System.String] }
            'boolean' { $Value -is [System.Boolean] }
            'integer' { $Value -is [System.Int32] -or $Value -is [System.Int64] }
            'number' { $Value -is [System.Int32] -or $Value -is [System.Int64] -or $Value -is [System.Double] -or $Value -is [System.Decimal] }
            default { $false }
        }
        $properties = $Schema['properties']
        $propertyNames = [System.String[]] @()
        if ($properties) {
            $propertyNames = [System.String[]] @($properties.Keys)
        }
        # THE FIRST PROBLEM FOUND, IF ANY. THE VALUE ITSELF IS NEVER PUT IN A MESSAGE, ONLY ITS PATH
        $problem = $null
        if (-not $typeIsMet) {
            $problem = '{0} must be of type {1}.' -f $Path, $type
        }
        elseif ($Schema.Contains('enum') -and $Value -cnotin @($Schema['enum'])) {
            $problem = '{0} is not one of the allowed values.' -f $Path
        }
        elseif ($type -ceq 'string') {
            if ($Schema.Contains('pattern') -and $Value -cnotmatch $Schema['pattern']) {
                $problem = '{0} does not match the required pattern.' -f $Path
            }
            elseif ($Schema.Contains('minLength') -and $Value.Length -lt $Schema['minLength']) {
                $problem = '{0} must be at least {1} characters.' -f $Path, $Schema['minLength']
            }
            elseif ($Schema.Contains('maxLength') -and $Value.Length -gt $Schema['maxLength']) {
                $problem = '{0} must be at most {1} characters.' -f $Path, $Schema['maxLength']
            }
        }
        elseif ($type -ceq 'integer' -or $type -ceq 'number') {
            if ($Schema.Contains('minimum') -and $Value -lt $Schema['minimum']) {
                $problem = '{0} must be at least {1}.' -f $Path, $Schema['minimum']
            }
            elseif ($Schema.Contains('maximum') -and $Value -gt $Schema['maximum']) {
                $problem = '{0} must be at most {1}.' -f $Path, $Schema['maximum']
            }
        }
        elseif ($type -ceq 'object') {
            $unknown = @($Value.Keys).Where({ $_ -cnotin $propertyNames }, 'First')
            $missing = @($Schema['required']).Where({ $null -ne $_ -and -not $Value.Contains($_) }, 'First')
            if ($unknown) {
                # THE NAME IS SHOWN SO THE CLIENT CAN FIX ITS CALL; A LONG ONE IS CUT SO A HUGE KEY IS NOT ECHOED
                $shown = [System.String] $unknown[0]
                if ($shown.Length -gt 64) {
                    $shown = $shown.Substring(0, 64)
                }
                $problem = 'unknown property [{0}] in {1}.' -f $shown, $Path
            }
            elseif ($missing) {
                $problem = '{0}.{1} is required.' -f $Path, $missing[0]
            }
        }
        if ($problem) {
            $protocolError = [McpProtocolError]::new(-32602, ('Invalid arguments: {0}' -f $problem))
            Write-Error -Exception $protocolError -ErrorAction 'Stop'
        }
        if ($type -ceq 'array' -and $Schema.Contains('items')) {
            for ($i = 0; $i -lt $Value.Count; $i++) {
                Test-JsonValue -Schema $Schema['items'] -Value $Value[$i] -Path ('{0}[{1}]' -f $Path, $i)
            }
        }
        if ($type -ceq 'object') {
            foreach ($key in @($Value.Keys)) {
                Test-JsonValue -Schema $properties[$key] -Value $Value[$key] -Path ('{0}.{1}' -f $Path, $key)
            }
        }
    }
}
