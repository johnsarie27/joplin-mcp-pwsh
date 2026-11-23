BeforeDiscovery {
    if (-not $env:BHProjectName) {
        $env:BHProjectName = 'JoplinMcp'
        $env:BHPSModuleManifest = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..', '..', 'JoplinMcp.psd1'))
    }
    if (-not (Get-Module -Name $env:BHProjectName)) {
        Import-Module -Name $env:BHPSModuleManifest -ErrorAction Stop -Force
    }
    $commonParameters = @([System.Management.Automation.PSCmdlet]::CommonParameters) + @([System.Management.Automation.PSCmdlet]::OptionalCommonParameters)
    $commonParameterCases = $commonParameters.ForEach({ @{ Parameter = $_ } })
}

Describe -Name 'Tool registry' -Fixture {
    BeforeAll {
        # EACH TEST REGISTERS UNDER ITS OWN NAMES AND THIS REMOVES THEM, SO A TOOL THE MODULE REGISTERS ITSELF IS NEVER TOUCHED
        $script:validSchema = {
            @{
                type                 = 'object'
                properties           = @{ query = @{ type = 'string'; minLength = 1 } }
                required             = @('query')
                additionalProperties = $false
            }
        }
        $script:register = {
            param([System.Collections.IDictionary] $Override = @{})
            InModuleScope -ModuleName $env:BHProjectName -Parameters @{ Override = $Override; Schema = (& $script:validSchema) } -ScriptBlock {
                $params = @{
                    Name        = 'zz_test_tool'
                    Description = 'A tool registered by the test suite.'
                    Access      = 'Read'
                    InputSchema = $Schema
                    Handler     = { 'ok' }
                }
                foreach ($key in $Override.Keys) {
                    $params[$key] = $Override[$key]
                }
                try {
                    Register-JoplinTool @params
                    $null
                }
                catch {
                    $_.Exception.Message
                }
            }
        }
    }
    AfterEach {
        InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
            foreach ($name in @($script:ToolRegistry.Keys).Where({ $_ -like 'zz_test_*' })) {
                $script:ToolRegistry.Remove($name) | Out-Null
            }
        }
    }
    Context -Name 'registration' -Fixture {
        It -Name 'registers a valid tool and publishes it in the tools/list shape' -Test {
            & $script:register | Should -BeNullOrEmpty
            $tool = @(InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { @(Get-ToolList).Where({ $_.name -eq 'zz_test_tool' }) })
            $tool | Should -HaveCount 1
            $tool[0].description | Should -Be 'A tool registered by the test suite.'
            $tool[0].inputSchema.additionalProperties | Should -BeFalse
            $tool[0].inputSchema.required | Should -Be @('query')
        }
        It -Name 'marks only Read tools as read-only' -ForEach @(@{ Access = 'Read'; Expected = $true }, @{ Access = 'Write'; Expected = $false }, @{ Access = 'CreateNotebook'; Expected = $false }, @{ Access = 'ManageTags'; Expected = $false }) -Test {
            & $script:register @{ Access = $Access } | Should -BeNullOrEmpty
            $tool = @(InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { @(Get-ToolList).Where({ $_.name -eq 'zz_test_tool' }) })
            $tool[0].annotations.readOnlyHint | Should -Be $Expected
        }
        It -Name 'requires Access and accepts only the four access levels' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $access = (Get-Command -Name 'Register-JoplinTool').Parameters['Access']
                $access.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
                [System.Enum]::GetNames([JoplinToolAccess]) | Should -Be @('Read', 'Write', 'CreateNotebook', 'ManageTags')
            }
        }
        It -Name 'rejects an access level that does not exist' -Test {
            & $script:register @{ Access = 'Admin' } | Should -Not -BeNullOrEmpty
        }
        It -Name 'rejects a description that is too short to be useful' -Test {
            & $script:register @{ Description = 'Short.' } | Should -Not -BeNullOrEmpty
        }
        It -Name 'rejects a tool name that is not lowercase letters, digits and underscores' -ForEach @(@{ Value = 'Search' }, @{ Value = 'has-dash' }, @{ Value = '9lives' }, @{ Value = '' }) -Test {
            & $script:register @{ Name = $Value } | Should -Not -BeNullOrEmpty
        }
        It -Name 'rejects a schema that does not set additionalProperties to false' -ForEach @(
            @{ Case = 'true'; Value = $true }
            @{ Case = 'missing'; Value = $null }
            @{ Case = 'a string'; Value = 'false' }
        ) -Test {
            $schema = & $script:validSchema
            if ($null -eq $Value) { $schema.Remove('additionalProperties') } else { $schema['additionalProperties'] = $Value }
            & $script:register @{ InputSchema = $schema } | Should -Not -BeNullOrEmpty
        }
        It -Name 'rejects a schema that is not an object schema' -Test {
            & $script:register @{ InputSchema = @{ type = 'array'; additionalProperties = $false } } | Should -Not -BeNullOrEmpty
        }
        It -Name 'rejects an empty required array' -Test {
            $schema = & $script:validSchema
            $schema['required'] = @()
            & $script:register @{ InputSchema = $schema } | Should -Not -BeNullOrEmpty
        }
        It -Name 'rejects a required name that is not a declared property' -Test {
            $schema = & $script:validSchema
            $schema['required'] = @('missing')
            & $script:register @{ InputSchema = $schema } | Should -Not -BeNullOrEmpty
        }
        It -Name 'rejects a schema property named like the common parameter <Parameter>' -ForEach $commonParameterCases -Test {
            $schema = & $script:validSchema
            $schema['properties'][$Parameter] = @{ type = 'string' }
            & $script:register @{ InputSchema = $schema } | Should -Not -BeNullOrEmpty
        }
        It -Name 'rejects a second registration of the same name and keeps the first' -Test {
            & $script:register | Should -BeNullOrEmpty
            & $script:register @{ Description = 'A different description entirely.' } | Should -Not -BeNullOrEmpty
            $tool = @(InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { @(Get-ToolList).Where({ $_.name -eq 'zz_test_tool' }) })
            $tool[0].description | Should -Be 'A tool registered by the test suite.'
        }
        It -Name 'registers nothing when registration fails' -Test {
            & $script:register @{ Description = 'Short.' } | Out-Null
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { $script:ToolRegistry.ContainsKey('zz_test_tool') } | Should -BeFalse
        }
        It -Name 'looks a tool up by exact name, so a tool named like a command is not an alias' -Test {
            & $script:register @{ Name = 'zz_test_echo' } | Should -BeNullOrEmpty
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $script:ToolRegistry.ContainsKey('zz_test_echo') | Should -BeTrue
                $script:ToolRegistry.ContainsKey('ZZ_TEST_ECHO') | Should -BeFalse
            }
        }
    }
    Context -Name 'published tool list' -Fixture {
        It -Name 'lists tools in name order, whatever order they were registered in' -Test {
            & $script:register @{ Name = 'zz_test_b' } | Should -BeNullOrEmpty
            & $script:register @{ Name = 'zz_test_a' } | Should -BeNullOrEmpty
            $names = @(InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { @(Get-ToolList).Where({ $_.name -like 'zz_test_*' }).name })
            $names | Should -Be @('zz_test_a', 'zz_test_b')
        }
        It -Name 'serializes schema keys in a fixed order, so a golden file is stable' -Test {
            $schema = @{ type = 'object'; additionalProperties = $false; properties = @{ zebra = @{ type = 'string' }; alpha = @{ type = 'string' } } }
            & $script:register @{ InputSchema = $schema } | Should -BeNullOrEmpty
            $json = InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                ConvertTo-Json -InputObject (@(Get-ToolList).Where({ $_.name -eq 'zz_test_tool' })[0].inputSchema) -Compress
            }
            $json | Should -Be '{"additionalProperties":false,"properties":{"alpha":{"type":"string"},"zebra":{"type":"string"}},"type":"object"}'
        }
        It -Name 'keeps a one-item required array an array' -Test {
            & $script:register | Should -BeNullOrEmpty
            $json = InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                ConvertTo-Json -InputObject (@(Get-ToolList).Where({ $_.name -eq 'zz_test_tool' })[0].inputSchema) -Compress
            }
            $json | Should -BeLike '*"required":`["query"`]*'
        }
    }
    Context -Name 'invariants over every tool the module registers' -Fixture {
        BeforeAll {
            $script:published = InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { @(Get-ToolList) }
        }
        It -Name 'gives every tool an Access value that is one of the four levels' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $valid = [System.Enum]::GetValues([JoplinToolAccess])
                foreach ($tool in $script:ToolRegistry.Values) {
                    $tool.Access | Should -BeIn $valid -Because ('tool [{0}] must declare Access' -f $tool.Name)
                }
            }
        }
        It -Name 'sets additionalProperties to false in every schema' -Test {
            foreach ($tool in $script:published) {
                $tool.inputSchema.additionalProperties | Should -BeFalse -Because ('tool [{0}]' -f $tool.name)
            }
        }
        It -Name 'emits no empty required array and no common parameter in any schema' -Test {
            $commonParameters = @([System.Management.Automation.PSCmdlet]::CommonParameters) + @([System.Management.Automation.PSCmdlet]::OptionalCommonParameters)
            foreach ($tool in $script:published) {
                if ($tool.inputSchema.Contains('required')) {
                    @($tool.inputSchema.required).Count | Should -BeGreaterThan 0 -Because ('tool [{0}]' -f $tool.name)
                }
                foreach ($propertyName in @($tool.inputSchema.properties.Keys)) {
                    $propertyName | Should -Not -BeIn $commonParameters -Because ('tool [{0}]' -f $tool.name)
                }
            }
        }
        It -Name 'requires every id property to match the 32-character hex pattern' -Test {
            foreach ($tool in $script:published) {
                foreach ($propertyName in @($tool.inputSchema.properties.Keys).Where({ $_ -match '(^|_)id$' })) {
                    $tool.inputSchema.properties[$propertyName].pattern | Should -Be '^[0-9a-f]{32}$' -Because ('tool [{0}] property [{1}]' -f $tool.name, $propertyName)
                }
            }
        }
        It -Name 'gives every tool a description of useful length' -Test {
            foreach ($tool in $script:published) {
                $tool.description.Trim().Length | Should -BeGreaterOrEqual 20 -Because ('tool [{0}]' -f $tool.name)
            }
        }
    }
}
