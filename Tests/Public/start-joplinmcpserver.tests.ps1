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
        It -Name 'writes nothing to any stream' -Test {
            $manifestPath = Join-Path -Path (Split-Path -Path (Get-Module -Name $env:BHProjectName).Path -Parent) -ChildPath ('{0}.psd1' -f $env:BHProjectName)
            $output = & {
                Import-Module -Name $manifestPath -Force -ErrorAction Stop
            } *>&1
            $output | Should -BeNullOrEmpty
        }
    }
}
