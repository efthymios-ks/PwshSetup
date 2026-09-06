Describe 'PwshSetup source' {
    BeforeAll {
        $script:repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
        $script:srcRoot = Join-Path -Path $script:repoRoot -ChildPath 'src'
    }

    It 'when listed, should hold module files' {
        Test-Path -LiteralPath $script:srcRoot -PathType Container | Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:srcRoot -Filter '*.psm1').Count | Should -BeGreaterThan 0
    }

    It 'when parsed, should have no errors' {
        $errors = foreach ($file in Get-ChildItem -LiteralPath $script:srcRoot -Filter '*.psm1' -Recurse)
        {
            $parseErrors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile(
                $file.FullName, [ref]$null, [ref]$parseErrors
            )
            if ($parseErrors)
            {
                foreach ($parseError in $parseErrors)
                {
                    '{0}:{1}  {2}' -f $file.Name, $parseError.Extent.StartLineNumber, $parseError.Message
                }
            }
        }
        $errors | Should -BeNullOrEmpty
    }
}
