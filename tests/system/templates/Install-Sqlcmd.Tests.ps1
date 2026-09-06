BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_Helpers.ps1')
    $script:detected = Test-SystemCommand -Name 'sqlcmd'
}

Describe 'Install-Sqlcmd' -Skip:(-not $script:detected) {
    It 'when installed, should resolve sqlcmd and print its help' {
        $output = & sqlcmd '-?' 2>&1
        ($output -join "`n") | Should -Match 'Version'
    }
}
