BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_Helpers.ps1')
    $script:detected = Test-SystemCommand -Name 'nvm'
}

Describe 'Install-Nvm' -Skip:(-not $script:detected) {
    It 'when installed, should resolve nvm and report a version' {
        $output = & nvm version 2>&1
        $LASTEXITCODE | Should -Be 0
        $output | Should -Match '\d+\.\d+'
    }
}
