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
        PS C:\> ConvertTo-SortedTree -InputObject @{ b = 1; a = @{ d = 1; c = 2 } } | ConvertTo-Json -Compress -Depth 4
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
            $sorted
        }
        elseif ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [System.String]) {
            $items = [System.Collections.Generic.List[System.Object]]::new()
            foreach ($item in $InputObject) {
                $items.Add((ConvertTo-SortedTree -InputObject $item))
            }
            # THE COMMA KEEPS A ONE-ITEM OR EMPTY ARRAY FROM BEING UNROLLED INTO THE PIPELINE
            , $items.ToArray()
        }
        else {
            $InputObject
        }
    }
}
