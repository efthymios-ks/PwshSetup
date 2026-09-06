BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_Helpers.ps1')
    $script:detected = (Test-WindowsFeature -FeatureName 'Microsoft-Windows-Subsystem-Linux') -and
        (Test-WindowsFeature -FeatureName 'VirtualMachinePlatform')
}

Describe 'Enable-Wsl' -Skip:(-not $script:detected) {
    It 'when enabled, should have the WSL feature on' {
        Test-WindowsFeature -FeatureName 'Microsoft-Windows-Subsystem-Linux' | Should -BeTrue
    }
    It 'when enabled, should have the Virtual Machine Platform on' {
        Test-WindowsFeature -FeatureName 'VirtualMachinePlatform' | Should -BeTrue
    }
}
