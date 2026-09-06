BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_Helpers.ps1')
    $script:detected = Test-SystemCommand -Name 'code'
}

Describe 'Install-VsCode' -Skip:(-not $script:detected) {
    It 'when installed, should resolve code and report a version' {
        $version = & code --version 2>&1
        $LASTEXITCODE | Should -Be 0
        ($version | Select-Object -First 1) | Should -Match '^\d+\.\d+\.\d+'
    }
}
