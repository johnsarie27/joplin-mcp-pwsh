BeforeDiscovery {
    if (-not $env:BHProjectName) {
        $env:BHProjectName = 'JoplinMcp'
        $env:BHPSModuleManifest = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath '..', 'JoplinMcp.psd1'))
    }
    if (-not (Get-Module -Name $env:BHProjectName)) {
        Import-Module -Name $env:BHPSModuleManifest -ErrorAction Stop -Force
    }
}

Describe -Name 'Protocol loop' -Fixture {
    BeforeAll {
        # FEEDS THE LINES TO THE LOOP AND RETURNS EACH RESPONSE LINE, PARSED. THE WRITER IS A StringWriter, SO THIS
        # SEES EXACTLY WHAT WOULD REACH STDOUT
        $script:run = {
            param([System.String[]] $Lines, [System.Boolean] $Raw = $false)
            $output = InModuleScope -ModuleName $env:BHProjectName -Parameters @{ Lines = $Lines } -ScriptBlock {
                $reader = [System.IO.StringReader]::new(($Lines -join "`n"))
                $writer = [System.IO.StringWriter]::new()
                $writer.NewLine = "`n"
                Invoke-McpLoop -Reader $reader -Writer $writer
                $writer.ToString()
            }
            if ($Raw) {
                return $output
            }
            , @($output -split "`n" | Where-Object { $_ -ne '' } | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable })
        }
        $script:addTool = {
            param([System.String] $Name, [System.Management.Automation.ScriptBlock] $Handler)
            InModuleScope -ModuleName $env:BHProjectName -Parameters @{ Name = $Name; Handler = $Handler } -ScriptBlock {
                $schema = @{ type = 'object'; properties = @{ text = @{ type = 'string' } }; additionalProperties = $false }
                # CreateNotebook: THE ACCESS GATE FOR IT RUNS IN THE HANDLER, SO THE HANDLER IS REACHED WITH THE PLACEHOLDER ACCESS
                Register-JoplinTool -Name $Name -Description 'A tool registered by the test suite.' -Access CreateNotebook -InputSchema $schema -Handler $Handler
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

    Context -Name 'one response per request' -Fixture {
        It -Name 'answers each request with exactly one line, in order' -Test {
            $responses = & $script:run @(
                '{"jsonrpc":"2.0","id":1,"method":"ping"}'
                '{"jsonrpc":"2.0","id":"two","method":"ping"}'
                '{"jsonrpc":"2.0","id":3,"method":"tools/list"}'
            )
            $responses | Should -HaveCount 3
            $responses.id | Should -Be @(1, 'two', 3)
        }
        It -Name 'never answers a notification, even one that fails' -Test {
            $output = & $script:run -Raw $true -Lines @(
                '{"jsonrpc":"2.0","method":"notifications/initialized"}'
                '{"jsonrpc":"2.0","method":"ping"}'
                '{"jsonrpc":"2.0","method":"no/such/method"}'
                '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"nope"}}'
            )
            $output | Should -BeNullOrEmpty
        }
        It -Name 'treats a message whose id is null as a request, not a notification' -Test {
            $responses = & $script:run @('{"jsonrpc":"2.0","id":null,"method":"ping"}')
            $responses | Should -HaveCount 1
        }
        It -Name 'echoes a string, integer or fractional id exactly' -Test {
            $responses = & $script:run @(
                '{"jsonrpc":"2.0","id":"abc-1","method":"ping"}'
                '{"jsonrpc":"2.0","id":0,"method":"ping"}'
                '{"jsonrpc":"2.0","id":9007199254740993,"method":"ping"}'
            )
            $responses.id | Should -Be @('abc-1', 0, 9007199254740993)
        }
        It -Name 'skips blank lines' -Test {
            $responses = & $script:run @('', '   ', '{"jsonrpc":"2.0","id":1,"method":"ping"}', '')
            $responses | Should -HaveCount 1
        }
        It -Name 'ends at once when the input is empty, writing nothing' -Test {
            & $script:run -Raw $true -Lines @() | Should -BeNullOrEmpty
        }
        It -Name 'answers ping with an empty result' -Test {
            $response = (& $script:run @('{"jsonrpc":"2.0","id":1,"method":"ping"}'))[0]
            $response.result.Count | Should -Be 0
            $response.jsonrpc | Should -Be '2.0'
        }
        It -Name 'writes compact single-line JSON ending in a line feed, with no byte order mark' -Test {
            $raw = & $script:run -Raw $true -Lines @('{"jsonrpc":"2.0","id":1,"method":"ping"}')
            $raw | Should -Be ('{"jsonrpc":"2.0","id":1,"result":{}}' + "`n")
        }
    }

    Context -Name 'errors' -Fixture {
        It -Name 'answers malformed JSON with -32700 and a null id, and keeps going' -Test {
            $responses = & $script:run @('{not json', '{"jsonrpc":"2.0","id":2,"method":"ping"}')
            $responses | Should -HaveCount 2
            $responses[0].error.code | Should -Be -32700
            $responses[0].ContainsKey('id') | Should -BeTrue
            $responses[0].id | Should -BeNullOrEmpty
            $responses[1].id | Should -Be 2
        }
        It -Name 'never reuses an earlier request''s id for a later error' -Test {
            $responses = & $script:run @('{"jsonrpc":"2.0","id":41,"method":"ping"}', 'garbage')
            $responses[1].id | Should -BeNullOrEmpty
        }
        It -Name 'answers an invalid request with -32600: <Case>' -ForEach @(
            @{ Case = 'no jsonrpc member'; Line = '{"id":1,"method":"ping"}' }
            @{ Case = 'wrong jsonrpc version'; Line = '{"jsonrpc":"1.0","id":1,"method":"ping"}' }
            @{ Case = 'jsonrpc that is not a string'; Line = '{"jsonrpc":2,"id":1,"method":"ping"}' }
            @{ Case = 'no method'; Line = '{"jsonrpc":"2.0","id":1}' }
            @{ Case = 'a method that is not a string'; Line = '{"jsonrpc":"2.0","id":1,"method":5}' }
            @{ Case = 'a batch array'; Line = '[{"jsonrpc":"2.0","id":1,"method":"ping"}]' }
            @{ Case = 'an empty array'; Line = '[]' }
            @{ Case = 'a bare number'; Line = '5' }
            @{ Case = 'a bare string'; Line = '"ping"' }
            @{ Case = 'JSON null'; Line = 'null' }
        ) -Test {
            $responses = & $script:run @($Line)
            $responses | Should -HaveCount 1
            $responses[0].error.code | Should -Be -32600
        }
        It -Name 'answers an invalid request with an id the client sent, when it is usable' -Test {
            $response = (& $script:run @('{"jsonrpc":"1.0","id":7,"method":"ping"}'))[0]
            $response.id | Should -Be 7
        }
        It -Name 'answers an id of the wrong type with -32600 and a null id' -Test {
            $response = (& $script:run @('{"jsonrpc":"2.0","id":{"a":1},"method":"ping"}'))[0]
            $response.error.code | Should -Be -32600
            $response.id | Should -BeNullOrEmpty
        }
        It -Name 'does not answer a response sent by the client' -Test {
            & $script:run -Raw $true -Lines @('{"jsonrpc":"2.0","id":1,"result":{}}') | Should -BeNullOrEmpty
        }
        It -Name 'answers an unknown method with -32601' -Test {
            (& $script:run @('{"jsonrpc":"2.0","id":1,"method":"resources/list"}'))[0].error.code | Should -Be -32601
        }
        It -Name 'matches method names case-sensitively' -Test {
            (& $script:run @('{"jsonrpc":"2.0","id":1,"method":"PING"}'))[0].error.code | Should -Be -32601
        }
        It -Name 'serializes every error code as an integer' -Test {
            # THE RAW TEXT, BECAUSE A PARSED NUMBER'S .NET TYPE SAYS NOTHING ABOUT HOW IT WAS WRITTEN: AN INTEGER HAS NO DECIMAL POINT
            $raw = & $script:run -Raw $true -Lines @('nope', '{"id":1}', '{"jsonrpc":"2.0","id":2,"method":"x"}', '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{}}')
            $codes = [System.Text.RegularExpressions.Regex]::Matches($raw, '"code":([^,}]*)')
            $codes.Count | Should -Be 4
            foreach ($code in $codes) {
                $code.Groups[1].Value | Should -Match '^-\d+$'
            }
        }
        It -Name 'answers -32603 with a generic message when an unexpected exception escapes' -Test {
            $output = InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $writer = [System.IO.StringWriter]::new()
                Mock -CommandName 'Get-ToolList' -MockWith { throw [System.InvalidOperationException]::new('boom https://localhost:41184/x?token=SECRET-TOKEN') }
                Invoke-McpLine -Line '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' -Writer $writer
                $writer.ToString()
            }
            $output | Should -BeLike '*-32603*'
            $output | Should -Not -BeLike '*SECRET-TOKEN*'
            $output | Should -Not -BeLike '*boom*'
        }
    }

    Context -Name 'initialize' -Fixture {
        It -Name 'echoes a protocol version the server supports' -Test {
            $supported = InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { $script:SupportedProtocolVersions[0] }
            $line = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"' + $supported + '"}}'
            (& $script:run @($line))[0].result.protocolVersion | Should -Be $supported
        }
        It -Name 'returns the latest supported version instead of echoing one it does not support' -Test {
            $latest = InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { $script:SupportedProtocolVersions[-1] }
            $line = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}'
            (& $script:run @($line))[0].result.protocolVersion | Should -Be $latest
        }
        It -Name 'rejects initialize without a protocolVersion with -32602' -Test {
            (& $script:run @('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'))[0].error.code | Should -Be -32602
            (& $script:run @('{"jsonrpc":"2.0","id":1,"method":"initialize"}'))[0].error.code | Should -Be -32602
        }
        It -Name 'advertises only the tools capability and names the server' -Test {
            $result = (& $script:run @('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"x"}}'))[0].result
            @($result.capabilities.Keys) | Should -Be @('tools')
            $result.serverInfo.name | Should -Be 'joplin-mcp-pwsh'
            $result.serverInfo.version | Should -Match '^\d+\.\d+\.\d+'
        }
    }

    Context -Name 'tools/call' -Fixture {
        It -Name 'answers an unknown tool with -32602, not an isError result' -Test {
            $response = (& $script:run @('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"nope","arguments":{}}}'))[0]
            $response.error.code | Should -Be -32602
            $response.ContainsKey('result') | Should -BeFalse
        }
        It -Name 'answers a tools/call with no tool name with -32602' -Test {
            (& $script:run @('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"arguments":{}}}'))[0].error.code | Should -Be -32602
        }
        It -Name 'answers bad arguments with -32602 before the handler runs' -Test {
            & $script:addTool 'zz_test_strict' { 'handler ran' }
            $response = (& $script:run @('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"zz_test_strict","arguments":{"ErrorAction":"Stop"}}}'))[0]
            $response.error.code | Should -Be -32602
        }
        It -Name 'treats absent arguments as an empty object' -Test {
            & $script:addTool 'zz_test_noargs' { 'handler ran' }
            $response = (& $script:run @('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"zz_test_noargs"}}'))[0]
            $response.result.content[0].text | Should -Be 'handler ran'
        }
        It -Name 'rejects arguments of null with -32602' -Test {
            & $script:addTool 'zz_test_nullargs' { 'handler ran' }
            (& $script:run @('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"zz_test_nullargs","arguments":null}}'))[0].error.code | Should -Be -32602
        }
        It -Name 'returns the handler''s value as text content with isError false' -Test {
            & $script:addTool 'zz_test_value' { param($Arguments, $Access) 'echo: {0}' -f $Arguments['text'] }
            $result = (& $script:run @('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"zz_test_value","arguments":{"text":"hi"}}}'))[0].result
            $result.isError | Should -BeFalse
            $result.content[0].type | Should -Be 'text'
            $result.content[0].text | Should -Be 'echo: hi'
        }
        It -Name 'runs the registered handler for a tool named like a command, never the command' -Test {
            # A TOOL CALLED 'echo' WOULD RUN Write-Output IF THE NAME WERE RESOLVED AS A COMMAND
            & $script:addTool 'zz_test_echo' { 'registered handler' }
            $result = (& $script:run @('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"zz_test_echo","arguments":{}}}'))[0].result
            $result.content[0].text | Should -Be 'registered handler'
        }
        It -Name 'finds a tool by its exact name only' -Test {
            & $script:addTool 'zz_test_exact' { 'ok' }
            (& $script:run @('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"ZZ_TEST_EXACT","arguments":{}}}'))[0].error.code | Should -Be -32602
        }
        It -Name 'reports a failure inside a tool as an isError result, never a JSON-RPC error' -Test {
            & $script:addTool 'zz_test_fail' { throw [McpToolError]::new('Note not found.') }
            $response = (& $script:run @('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"zz_test_fail","arguments":{}}}'))[0]
            $response.ContainsKey('error') | Should -BeFalse
            $response.result.isError | Should -BeTrue
            $response.result.content[0].text | Should -Be 'Note not found.'
        }
        It -Name 'hides the text of any other exception, which may carry a URL and the token' -Test {
            & $script:addTool 'zz_test_leak' { throw [System.Net.Http.HttpRequestException]::new('GET https://localhost:41184/notes?token=SECRET-TOKEN failed') }
            $raw = & $script:run -Raw $true -Lines @('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"zz_test_leak","arguments":{}}}')
            $raw | Should -Not -BeLike '*SECRET-TOKEN*'
            $raw | Should -Not -BeLike '*localhost*'
            ($raw | ConvertFrom-Json -AsHashtable).result.isError | Should -BeTrue
        }
        It -Name 'turns a handler that returns two values into an isError result' -Test {
            & $script:addTool 'zz_test_two' { 'one'; 'two' }
            $result = (& $script:run @('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"zz_test_two","arguments":{}}}'))[0].result
            $result.isError | Should -BeTrue
            $result.content[0].text | Should -Not -BeLike '*one*'
        }
        It -Name 'turns a handler that returns nothing into an isError result' -Test {
            & $script:addTool 'zz_test_none' { $null = 'discarded' }
            (& $script:run @('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"zz_test_none","arguments":{}}}'))[0].result.isError | Should -BeTrue
        }
        It -Name 'does not let a stray pipeline value pass as the result' -Test {
            & $script:addTool 'zz_test_stray' { [System.Collections.ArrayList]::new().Add('x'); 'real result' }
            (& $script:run @('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"zz_test_stray","arguments":{}}}'))[0].result.isError | Should -BeTrue
        }
        It -Name 'refuses a Read or Write tool while no access is configured (fails closed)' -ForEach @(@{ Access = 'Read' }, @{ Access = 'Write' }) -Test {
            InModuleScope -ModuleName $env:BHProjectName -Parameters @{ Access = $Access } -ScriptBlock {
                $schema = @{ type = 'object'; properties = @{}; additionalProperties = $false }
                Register-JoplinTool -Name 'zz_test_gated' -Description 'A tool registered by the test suite.' -Access $Access -InputSchema $schema -Handler { 'handler ran' }
            }
            $result = (& $script:run @('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"zz_test_gated","arguments":{}}}'))[0].result
            $result.isError | Should -BeTrue
            $result.content[0].text | Should -BeLike 'No notebooks are configured*'
        }
        It -Name 'refuses a ManageTags tool while no access is configured' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $schema = @{ type = 'object'; properties = @{}; additionalProperties = $false }
                Register-JoplinTool -Name 'zz_test_tags' -Description 'A tool registered by the test suite.' -Access ManageTags -InputSchema $schema -Handler { 'handler ran' }
            }
            $result = (& $script:run @('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"zz_test_tags","arguments":{}}}'))[0].result
            $result.isError | Should -BeTrue
            $result.content[0].text | Should -BeLike 'Tag management*'
        }
    }

    Context -Name 'serialization' -Fixture {
        It -Name 'fails loudly, writing nothing, when a message is nested too deeply to serialize' -Test {
            $threw = InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $writer = [System.IO.StringWriter]::new()
                $deep = @{ leaf = 1 }
                1..40 | ForEach-Object { $deep = @{ nested = $deep } }
                $caught = $false
                try {
                    Write-McpMessage -Writer $writer -Message ([ordered]@{ jsonrpc = '2.0'; id = 1; result = $deep })
                }
                catch {
                    $caught = $true
                }
                @{ Caught = $caught; Written = $writer.ToString() }
            }
            $threw.Caught | Should -BeTrue
            $threw.Written | Should -BeNullOrEmpty
        }
    }
}
