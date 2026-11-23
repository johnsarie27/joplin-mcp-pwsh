BeforeDiscovery {
    if (-not $env:BHProjectName) {
        $env:BHProjectName = 'JoplinMcp'
        $env:BHPSModuleManifest = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath '..', 'JoplinMcp.psd1'))
    }
    if (-not (Get-Module -Name $env:BHProjectName)) {
        Import-Module -Name $env:BHPSModuleManifest -ErrorAction Stop -Force
    }
    $commonParameters = @([System.Management.Automation.PSCmdlet]::CommonParameters) + @([System.Management.Automation.PSCmdlet]::OptionalCommonParameters)
    $commonParameterCases = $commonParameters.ForEach({ @{ Parameter = $_ } })
}

Describe -Name 'Argument strictness' -Fixture {
    BeforeAll {
        $script:schema = @{
            type                 = 'object'
            properties           = @{
                note_id = @{ type = 'string'; pattern = '^[0-9a-f]{32}$' }
                query   = @{ type = 'string'; minLength = 2; maxLength = 8 }
                limit   = @{ type = 'integer'; minimum = 1; maximum = 100 }
                done    = @{ type = 'boolean' }
                mode    = @{ type = 'string'; enum = @('fast', 'slow') }
                tags    = @{ type = 'array'; items = @{ type = 'string'; minLength = 1 } }
            }
            required             = @('query')
            additionalProperties = $false
        }
        # RETURNS $null WHEN THE ARGUMENTS ARE ACCEPTED, OTHERWISE THE TYPE NAME, CODE AND MESSAGE OF THE EXCEPTION
        $script:check = {
            param($Arguments)
            InModuleScope -ModuleName $env:BHProjectName -Parameters @{ Schema = $script:schema; Arguments = $Arguments } -ScriptBlock {
                try {
                    Test-ToolArgument -Schema $Schema -Arguments $Arguments
                    $null
                }
                catch {
                    @{ Type = $_.Exception.GetType().Name; Code = $_.Exception.Code; Message = $_.Exception.Message }
                }
            }
        }
    }

    It -Name 'accepts arguments that match the schema exactly' -Test {
        & $script:check @{ query = 'tax'; limit = 20; done = $false; mode = 'fast'; tags = @('a', 'b'); note_id = ('0123456789abcdef' * 2) } | Should -BeNullOrEmpty
    }
    It -Name 'accepts a missing optional argument' -Test {
        & $script:check @{ query = 'tax' } | Should -BeNullOrEmpty
    }
    It -Name 'rejects every problem with a McpProtocolError and code -32602' -Test {
        $result = & $script:check @{ query = 'tax'; extra = 1 }
        $result.Type | Should -Be 'McpProtocolError'
        $result.Code | Should -Be -32602
    }
    It -Name 'rejects arguments that are an array, never binding them by position' -Test {
        (& $script:check @('tax', 20)).Code | Should -Be -32602
    }
    It -Name 'rejects arguments that are not an object: <Case>' -ForEach @(
        @{ Case = 'a string'; Value = 'query' }
        @{ Case = 'a number'; Value = 5 }
        @{ Case = 'null'; Value = $null }
    ) -Test {
        (& $script:check $Value).Code | Should -Be -32602
    }
    It -Name 'rejects the common parameter <Parameter> as an unknown property' -ForEach $commonParameterCases -Test {
        $result = & $script:check @{ query = 'tax'; $Parameter = 'Stop' }
        $result.Code | Should -Be -32602
        $result.Message | Should -BeLike '*unknown property*'
    }
    It -Name 'rejects an unknown property' -Test {
        (& $script:check @{ query = 'tax'; other = 1 }).Message | Should -BeLike '*unknown property*'
    }
    It -Name 'rejects a missing required property' -Test {
        (& $script:check @{ limit = 5 }).Message | Should -BeLike '*required*'
    }
    It -Name 'rejects a property name that differs only in case' -Test {
        (& $script:check @{ query = 'tax'; Limit = 5 }).Code | Should -Be -32602
    }
    It -Name 'rejects a string for an integer' -Test {
        (& $script:check @{ query = 'tax'; limit = '20' }).Message | Should -BeLike '*limit*type integer*'
    }
    It -Name 'rejects a boolean for an integer' -Test {
        (& $script:check @{ query = 'tax'; limit = $true }).Code | Should -Be -32602
    }
    It -Name 'rejects a fractional number for an integer' -Test {
        (& $script:check @{ query = 'tax'; limit = 2.5 }).Code | Should -Be -32602
    }
    It -Name 'rejects <Case> for a boolean, never coercing it' -ForEach @(
        @{ Case = 'the string "false"'; Value = 'false' }
        @{ Case = 'the string "true"'; Value = 'true' }
        @{ Case = 'the number 0'; Value = 0 }
        @{ Case = 'the number 1'; Value = 1 }
    ) -Test {
        (& $script:check @{ query = 'tax'; done = $Value }).Message | Should -BeLike '*done*type boolean*'
    }
    It -Name 'rejects a number for a string' -Test {
        (& $script:check @{ query = 12345 }).Code | Should -Be -32602
    }
    It -Name 'rejects null for a string' -Test {
        (& $script:check @{ query = $null }).Code | Should -Be -32602
    }
    It -Name 'checks patterns case-sensitively' -Test {
        (& $script:check @{ query = 'tax'; note_id = ('0123456789ABCDEF' * 2) }).Message | Should -BeLike '*pattern*'
    }
    It -Name 'checks enum values case-sensitively' -Test {
        (& $script:check @{ query = 'tax'; mode = 'Fast' }).Message | Should -BeLike '*allowed values*'
    }
    It -Name 'enforces minLength, maxLength, minimum and maximum' -ForEach @(
        @{ Arguments = @{ query = 'a' } }
        @{ Arguments = @{ query = 'abcdefghi' } }
        @{ Arguments = @{ query = 'tax'; limit = 0 } }
        @{ Arguments = @{ query = 'tax'; limit = 101 } }
    ) -Test {
        (& $script:check $Arguments).Code | Should -Be -32602
    }
    It -Name 'checks the items of an array' -Test {
        (& $script:check @{ query = 'tax'; tags = @('a', 5) }).Message | Should -BeLike '*tags`[1`]*'
    }
    It -Name 'never repeats a rejected value in the message' -Test {
        (& $script:check @{ query = 'tax'; limit = 'SECRET-VALUE-123' }).Message | Should -Not -BeLike '*SECRET-VALUE-123*'
    }
    It -Name 'cuts a very long unknown property name in the message' -Test {
        (& $script:check @{ query = 'tax'; ('x' * 500) = 1 }).Message.Length | Should -BeLessThan 200
    }
}
