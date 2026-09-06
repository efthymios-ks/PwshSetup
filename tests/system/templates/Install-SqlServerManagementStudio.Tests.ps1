BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_Helpers.ps1')
    $script:detected = Test-InstalledApp -DisplayName 'SQL Server Management Studio'
}

Describe 'Install-SqlServerManagementStudio' -Skip:(-not $script:detected) {
    It 'when installed, should be listed in Installed apps' {
        Test-InstalledApp -DisplayName 'SQL Server Management Studio' | Should -BeTrue
    }
}
