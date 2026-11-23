BeforeDiscovery {
    if (-not $env:BHProjectName) {
        $env:BHProjectName = 'JoplinMcp'
        $env:BHPSModuleManifest = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..', '..', 'JoplinMcp.psd1'))
    }
    if (-not (Get-Module -Name $env:BHProjectName)) {
        Import-Module -Name $env:BHPSModuleManifest -ErrorAction Stop -Force
    }
}

Describe -Name 'Start-JoplinMcpServer' -Fixture {
    BeforeAll {
        $script:golden = (Get-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..', 'Registry', 'tools-list.golden.json') -Raw).Trim()
        # RUNS A COMMAND IN A REAL pwsh PROCESS AFTER IMPORTING THE MODULE, WITH STDIN CLOSED, AND RETURNS STDOUT AND STDERR
        $script:runCommand = {
            param([System.String] $Command)
            $manifestPath = Join-Path -Path (Split-Path -Path (Get-Module -Name $env:BHProjectName).Path -Parent) -ChildPath ('{0}.psd1' -f $env:BHProjectName)
            $fullCommand = "Import-Module -Name '{0}' -ErrorAction Stop; {1}" -f $manifestPath.Replace("'", "''"), $Command
            $startInfo = [System.Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
            foreach ($argument in '-NoProfile', '-NonInteractive', '-Command', $fullCommand) {
                $startInfo.ArgumentList.Add($argument)
            }
            $startInfo.RedirectStandardInput = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $startInfo.UseShellExecute = $false
            $process = [System.Diagnostics.Process]::Start($startInfo)
            $stderrTask = $process.StandardError.ReadToEndAsync()
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $process.StandardInput.Close()
            $process.WaitForExit(60000) | Out-Null
            @{ ExitCode = $process.ExitCode; Stdout = $stdoutTask.Result; Stderr = $stderrTask.Result }
        }
    }
    Context -Name '-ListTools' -Fixture {
        It -Name 'returns the tools/list JSON and matches the golden file' -Test {
            Start-JoplinMcpServer -ListTools | Should -Be $script:golden
        }
        It -Name 'returns one string of valid JSON with a tools array' -Test {
            $output = @(Start-JoplinMcpServer -ListTools)
            $output | Should -HaveCount 1
            $output[0] | Should -BeOfType [System.String]
            $parsed = $output[0] | ConvertFrom-Json -AsHashtable
            # NOT PIPED: AN EMPTY ARRAY WOULD BE UNROLLED INTO NOTHING
            ($parsed.tools -is [System.Array]) | Should -BeTrue
        }
        It -Name 'writes only that JSON to the stdout of a real process, and nothing to stderr' -Test {
            $manifestPath = Join-Path -Path (Split-Path -Path (Get-Module -Name $env:BHProjectName).Path -Parent) -ChildPath ('{0}.psd1' -f $env:BHProjectName)
            $command = "Import-Module -Name '{0}' -ErrorAction Stop; Start-JoplinMcpServer -ListTools" -f $manifestPath.Replace("'", "''")
            $startInfo = [System.Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
            foreach ($argument in '-NoProfile', '-NonInteractive', '-Command', $command) {
                $startInfo.ArgumentList.Add($argument)
            }
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $startInfo.UseShellExecute = $false
            $process = [System.Diagnostics.Process]::Start($startInfo)
            $stderrTask = $process.StandardError.ReadToEndAsync()
            $stdout = $process.StandardOutput.ReadToEnd()
            $process.WaitForExit()
            $process.ExitCode | Should -Be 0
            $stdout.Trim() | Should -Be $script:golden
            $stderrTask.Result | Should -BeNullOrEmpty
        }
        It -Name 'sends verbose output to stderr, keeping stdout to the JSON, when the caller passes -Verbose' -Test {
            $run = & $script:runCommand 'Start-JoplinMcpServer -ListTools -Verbose'
            $run.ExitCode | Should -Be 0
            $run.Stdout.Trim() | Should -Be $script:golden
            $run.Stderr | Should -BeLike '*Starting Start-JoplinMcpServer*'
        }
        It -Name 'leaves Console.Out as it found it' -Test {
            $before = [System.Console]::Out
            Start-JoplinMcpServer -ListTools | Out-Null
            [System.Object]::ReferenceEquals([System.Console]::Out, $before) | Should -BeTrue
        }
    }
    Context -Name 'after the server stops' -Fixture {
        It -Name 'gives the session back its stdout and its output rendering' -Test {
            $command = '$before = $PSStyle.OutputRendering; Start-JoplinMcpServer; [System.Console]::Out.WriteLine(''AFTER-RETURN''); [System.Console]::Out.WriteLine(($PSStyle.OutputRendering -eq $before))'
            $run = & $script:runCommand $command
            $run.ExitCode | Should -Be 0
            @($run.Stdout.Trim() -split '\r?\n') | Should -Be @('AFTER-RETURN', 'True')
        }
    }
    Context -Name 'importing the module' -Fixture {
        It -Name 'exports only Start-JoplinMcpServer' -Test {
            @((Get-Module -Name $env:BHProjectName).ExportedFunctions.Keys) | Should -Be @('Start-JoplinMcpServer')
        }
        It -Name 'exports no variable, alias or cmdlet, so no tool is a PowerShell command' -Test {
            $module = Get-Module -Name $env:BHProjectName
            $module.ExportedVariables.Count | Should -Be 0
            $module.ExportedAliases.Count | Should -Be 0
            $module.ExportedCmdlets.Count | Should -Be 0
        }
        It -Name 'declares every class and enum in Private/Classes.ps1, which loads first (ADR 12)' -Test {
            $moduleRoot = Split-Path -Path (Get-Module -Name $env:BHProjectName).Path -Parent
            $sources = Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Public'), (Join-Path -Path $moduleRoot -ChildPath 'Private') -Filter '*.ps1' -Recurse
            foreach ($source in $sources.Where({ $_.Name -ne 'Classes.ps1' })) {
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($source.FullName, [ref] $null, [ref] $null)
                $typeDefinitions = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.TypeDefinitionAst] }, $true)
                @($typeDefinitions).Count | Should -Be 0 -Because ('{0} must not declare a class or enum' -f $source.Name)
            }
        }
        It -Name 'writes nothing to any stream' -Test {
            $manifestPath = Join-Path -Path (Split-Path -Path (Get-Module -Name $env:BHProjectName).Path -Parent) -ChildPath ('{0}.psd1' -f $env:BHProjectName)
            $output = & {
                Import-Module -Name $manifestPath -Force -ErrorAction Stop
            } *>&1
            $output | Should -BeNullOrEmpty
        }
    }
}
