BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_Helpers.ps1')
    $script:detected = Test-SystemCommand -Name 'k9s'
}

Describe 'Install-K9s' -Skip:(-not $script:detected) {
    It 'when installed, should resolve k9s and exit cleanly' {
        # k9s version output format varies across releases (sometimes a semver, sometimes a commit SHA line);
        # a clean exit with any output is a reliable signal the binary is on PATH and runnable.
        $output = & k9s version --short 2>&1
        $LASTEXITCODE | Should -Be 0
        $output | Should -Not -BeNullOrEmpty
    }
}
