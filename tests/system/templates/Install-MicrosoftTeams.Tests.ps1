BeforeDiscovery {
    $script:detected = [bool](Get-AppxPackage -AllUsers -Name 'MSTeams' -ErrorAction Ignore)
}

Describe 'Install-MicrosoftTeams' -Skip:(-not $script:detected) {
    It 'when installed, should provision the MSTeams app package' {
        Get-AppxPackage -AllUsers -Name 'MSTeams' | Should -Not -BeNullOrEmpty
    }
}
