BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_Helpers.ps1')
    $script:detected = Test-SystemCommand -Name 'choco'
}

Describe 'Install-Chocolatey' -Skip:(-not $script:detected) {
    It 'when installed, should resolve choco and report a version' {
        $version = & choco --version 2>&1
        $LASTEXITCODE | Should -Be 0
        $version | Should -Match '^\d+\.\d+\.\d+'
    }
}
