BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_Helpers.ps1')
    $script:detected = Test-SystemCommand -Name 'git'
}

Describe 'Install-Git' -Skip:(-not $script:detected) {
    It 'when installed, should resolve git and report a version' {
        $version = & git --version 2>&1
        $LASTEXITCODE | Should -Be 0
        $version | Should -Match '^git version \d+\.\d+'
    }
}
