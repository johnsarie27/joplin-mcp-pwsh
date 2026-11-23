BeforeDiscovery {
    if (-not $env:BHProjectName) {
        $env:BHProjectName = 'JoplinMcp'
        $env:BHPSModuleManifest = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath '..', 'JoplinMcp.psd1'))
    }
    if (-not (Get-Module -Name $env:BHProjectName)) {
        Import-Module -Name $env:BHPSModuleManifest -ErrorAction Stop -Force
    }
}

# THESE RUN THE SERVER AS A REAL pwsh PROCESS, THE WAY AN MCP CLIENT DOES, BECAUSE THE PROPERTY UNDER TEST IS WHAT REACHES
# THE PROCESS'S STDOUT. AN IN-PROCESS WRITER CANNOT SHOW A Write-Host OR [Console]::WriteLine THAT BYPASSES IT
Describe -Name 'Stdout isolation' -Fixture {
    BeforeAll {
        $manifestPath = Join-Path -Path (Split-Path -Path (Get-Module -Name $env:BHProjectName).Path -Parent) -ChildPath ('{0}.psd1' -f $env:BHProjectName)
        $scriptPath = Join-Path -Path $TestDrive -ChildPath 'run-server.ps1'
        # THE SCRIPT REGISTERS TOOLS THAT MISBEHAVE ON PURPOSE, THEN STARTS THE SERVER. CreateNotebook REACHES THE HANDLER
        # WITHOUT ACCESS BEING CONFIGURED
        $serverScript = @'
param([System.String] $Manifest)
Import-Module -Name $Manifest -Force -ErrorAction Stop
& (Get-Module -Name 'JoplinMcp') {
    $schema = @{ type = 'object'; properties = @{}; additionalProperties = $false }
    Register-JoplinTool -Name 'noisy' -Description 'Writes to every output stream on purpose.' -Access CreateNotebook -InputSchema $schema -Handler {
        param($Arguments, $Access)
        Write-Host 'STRAY-HOST'
        Write-Warning 'STRAY-WARNING'
        $VerbosePreference = 'Continue'
        Write-Verbose 'STRAY-VERBOSE'
        $DebugPreference = 'Continue'
        Write-Debug 'STRAY-DEBUG'
        Write-Information 'STRAY-INFORMATION' -InformationAction Continue
        Write-Error 'STRAY-ERROR' -ErrorAction Continue
        [System.Console]::WriteLine('STRAY-CONSOLE-WRITELINE')
        [System.Console]::Out.WriteLine('STRAY-CONSOLE-OUT')
        'RESULT-OK'
    }
    Register-JoplinTool -Name 'leaky' -Description 'Fails with a message that holds a URL and a token.' -Access CreateNotebook -InputSchema $schema -Handler {
        param($Arguments, $Access)
        throw [System.Net.Http.HttpRequestException]::new('GET http://localhost:41184/notes?token=SECRET-TOKEN failed')
    }
}
Start-JoplinMcpServer
'@
        Set-Content -LiteralPath $scriptPath -Value $serverScript -Encoding utf8NoBOM

        # RUNS THE SERVER, FEEDS IT THE LINES, CLOSES STDIN, AND RETURNS STDOUT (BYTES AND TEXT), STDERR AND THE EXIT CODE
        $script:runServer = {
            param([System.String[]] $Lines)
            $startInfo = [System.Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
            foreach ($argument in '-NoProfile', '-NonInteractive', '-File', $scriptPath, '-Manifest', $manifestPath) {
                $startInfo.ArgumentList.Add($argument)
            }
            $startInfo.RedirectStandardInput = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $startInfo.StandardInputEncoding = [System.Text.UTF8Encoding]::new($false)
            $startInfo.UseShellExecute = $false
            $process = [System.Diagnostics.Process]::Start($startInfo)
            # BOTH OUTPUT STREAMS ARE DRAINED CONCURRENTLY, OR A FULL PIPE BUFFER WOULD DEADLOCK THE CHILD
            $stdoutBytes = [System.IO.MemoryStream]::new()
            $stdoutTask = $process.StandardOutput.BaseStream.CopyToAsync($stdoutBytes)
            $stderrTask = $process.StandardError.ReadToEndAsync()
            foreach ($line in $Lines) {
                $process.StandardInput.Write($line + "`n")
            }
            $process.StandardInput.Close()
            $exited = $process.WaitForExit(60000)
            if (-not $exited) {
                $process.Kill($true)
            }
            $stdoutTask.Wait(10000) | Out-Null
            $stderrTask.Wait(10000) | Out-Null
            $bytes = $stdoutBytes.ToArray()
            @{
                Exited   = $exited
                ExitCode = if ($exited) { $process.ExitCode } else { $null }
                Bytes    = $bytes
                Stdout   = [System.Text.UTF8Encoding]::new($false).GetString($bytes)
                Stderr   = $stderrTask.Result
            }
        }
        $script:session = & $script:runServer @(
            '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}'
            '{"jsonrpc":"2.0","method":"notifications/initialized"}'
            '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"noisy","arguments":{}}}'
            'this line is not JSON and holds SECRET-INPUT-LINE'
            '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"leaky","arguments":{}}}'
            '{"jsonrpc":"2.0","id":4,"method":"ping"}'
        )
        $script:stdoutLines = @($script:session.Stdout -split "`n" | Where-Object { $_ -ne '' })
    }

    It -Name 'exits promptly when stdin closes' -Test {
        $script:session.Exited | Should -BeTrue
        $script:session.ExitCode | Should -Be 0
    }
    It -Name 'writes only JSON-RPC messages to stdout: one parseable line per request, none for the notification' -Test {
        # 1 initialize, 2 noisy, a parse error, 3 leaky and 4 ping; the notification gets no line
        $script:stdoutLines | Should -HaveCount 5
        foreach ($line in $script:stdoutLines) {
            { $line | ConvertFrom-Json -AsHashtable -ErrorAction Stop } | Should -Not -Throw
        }
    }
    It -Name 'answers in order, with the noisy tool''s single value as its result' -Test {
        $responses = $script:stdoutLines | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable }
        $responses[0].id | Should -Be 1
        $responses[1].id | Should -Be 2
        $responses[1].result.isError | Should -BeFalse
        $responses[1].result.content[0].text | Should -Be 'RESULT-OK'
        $responses[2].error.code | Should -Be -32700
        $responses[4].id | Should -Be 4
    }
    It -Name 'keeps Write-Host, warnings, verbose, debug, information, errors and Console writes off stdout' -Test {
        $script:session.Stdout | Should -Not -BeLike '*STRAY*'
    }
    # THE Console WRITES ARE MOVED BY [Console]::SetOut. THE OTHER SIX ARE CAUGHT BY Invoke-HandlerIsolated, WHICH TAGS EACH WITH ITS
    # RECORD TYPE. ASSERTING THE TAG, NOT JUST THE TEXT, IS WHAT SHOWS THAT SECOND LAYER WORKS: WITHOUT IT THE HOST WOULD STILL
    # WRITE THE TEXT TO THE REDIRECTED Console.Out, SO A TEXT-ONLY CHECK PASSES EITHER WAY
    It -Name 'sends <Marker> to stderr, tagged <Expected>' -ForEach @(
        @{ Marker = 'STRAY-HOST'; Expected = '[diag:InformationRecord] STRAY-HOST' }
        @{ Marker = 'STRAY-WARNING'; Expected = '[diag:WarningRecord] STRAY-WARNING' }
        @{ Marker = 'STRAY-VERBOSE'; Expected = '[diag:VerboseRecord] STRAY-VERBOSE' }
        @{ Marker = 'STRAY-DEBUG'; Expected = '[diag:DebugRecord] STRAY-DEBUG' }
        @{ Marker = 'STRAY-INFORMATION'; Expected = '[diag:InformationRecord] STRAY-INFORMATION' }
        @{ Marker = 'STRAY-ERROR'; Expected = '[diag:ErrorRecord] STRAY-ERROR' }
        @{ Marker = 'STRAY-CONSOLE-WRITELINE'; Expected = 'STRAY-CONSOLE-WRITELINE' }
        @{ Marker = 'STRAY-CONSOLE-OUT'; Expected = 'STRAY-CONSOLE-OUT' }
    ) -Test {
        $script:session.Stderr | Should -BeLike ('*{0}*' -f $Expected.Replace('[', '`[').Replace(']', '`]'))
    }
    It -Name 'writes no byte order mark and no carriage return' -Test {
        $script:session.Bytes[0] | Should -Be ([System.Byte][System.Char]'{')
        $script:session.Bytes | Should -Not -Contain ([System.Byte] 13)
    }
    It -Name 'carries no ANSI escape code in either stream' -Test {
        $script:session.Stdout | Should -Not -BeLike "*$([System.Char]27)*"
        $script:session.Stderr | Should -Not -BeLike "*$([System.Char]27)*"
    }
    It -Name 'leaks the token to neither stream when a tool fails with a URL in its exception' -Test {
        $script:session.Stdout | Should -Not -BeLike '*SECRET-TOKEN*'
        $script:session.Stderr | Should -Not -BeLike '*SECRET-TOKEN*'
        $leaky = ($script:stdoutLines[3] | ConvertFrom-Json -AsHashtable).result
        $leaky.isError | Should -BeTrue
        $leaky.content[0].text | Should -Be 'The tool call failed.'
    }
    It -Name 'never echoes the raw input line to stderr or stdout' -Test {
        $script:session.Stderr | Should -Not -BeLike '*SECRET-INPUT-LINE*'
        $script:session.Stdout | Should -Not -BeLike '*SECRET-INPUT-LINE*'
        $script:session.Stderr | Should -BeLike '*Parse error: input of length*'
    }
    It -Name 'writes nothing at startup before the first response' -Test {
        $quiet = & $script:runServer @()
        $quiet.Exited | Should -BeTrue
        $quiet.Stdout | Should -BeNullOrEmpty
    }
}
