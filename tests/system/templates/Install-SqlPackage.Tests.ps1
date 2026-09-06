BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_Helpers.ps1')
    $script:detected = Test-SystemCommand -Name 'sqlpackage'
}

Describe 'Install-SqlPackage' -Skip:(-not $script:detected) {
    It 'when installed, should resolve sqlpackage and report a version' {
        $output = & sqlpackage /Version 2>&1
        $LASTEXITCODE | Should -Be 0
        $output | Should -Match '\d+\.\d+'
    }
}
