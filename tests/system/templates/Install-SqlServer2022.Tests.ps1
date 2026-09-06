BeforeDiscovery {
    $script:detected = [bool](Get-Service -Name 'MSSQLSERVER' -ErrorAction Ignore)
}

Describe 'Install-SqlServer2022' -Skip:(-not $script:detected) {
    It 'when installed, should have the MSSQLSERVER service start with Windows' {
        $service = Get-Service -Name 'MSSQLSERVER' -ErrorAction Stop
        $service | Should -Not -BeNullOrEmpty
        # StartType, not Status: the service can be stopped right after a restart without the install being wrong.
        $service.StartType | Should -Be 'Automatic'
    }
}
