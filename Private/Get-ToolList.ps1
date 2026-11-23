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
