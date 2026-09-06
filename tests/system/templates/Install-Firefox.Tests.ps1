BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_Helpers.ps1')
    $script:detected = Test-InstalledApp -DisplayName 'Mozilla Firefox'
}

Describe 'Install-Firefox' -Skip:(-not $script:detected) {
    It 'when installed, should be listed in Installed apps' {
        Test-InstalledApp -DisplayName 'Mozilla Firefox' | Should -BeTrue
    }
}
