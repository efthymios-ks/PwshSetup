BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_Helpers.ps1')
    $script:detected = Test-InstalledApp -DisplayName 'Docker Desktop'
}

Describe 'Install-DockerDesktop' -Skip:(-not $script:detected) {
    It 'when installed, should be listed in Installed apps' {
        Test-InstalledApp -DisplayName 'Docker Desktop' | Should -BeTrue
    }
}
