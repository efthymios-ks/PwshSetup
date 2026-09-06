BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_Helpers.ps1')
    $script:detected = Test-InstalledApp -DisplayName 'Google Chrome'
}

Describe 'Install-GoogleChrome' -Skip:(-not $script:detected) {
    It 'when installed, should be listed in Installed apps' {
        Test-InstalledApp -DisplayName 'Google Chrome' | Should -BeTrue
    }
}
