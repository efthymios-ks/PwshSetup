BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_Helpers.ps1')
    $script:detected = Test-SystemCommand -Name 'podman'
}

Describe 'Install-PodmanCli' -Skip:(-not $script:detected) {
    It 'when installed, should resolve podman and report a version' {
        $version = & podman --version 2>&1
        $LASTEXITCODE | Should -Be 0
        $version | Should -Match '^podman version \d+\.\d+'
    }
}
