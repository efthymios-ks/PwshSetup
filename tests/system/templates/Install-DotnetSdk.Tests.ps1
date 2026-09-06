BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_Helpers.ps1')
    $script:detected = Test-SystemCommand -Name 'dotnet'
}

Describe 'Install-DotnetSdk' -Skip:(-not $script:detected) {
    It 'when installed, should list at least one SDK' {
        $sdks = & dotnet --list-sdks 2>&1
        $LASTEXITCODE | Should -Be 0
        # Lines look like "10.0.100 [C:\Program Files\dotnet\sdk]"; a version at the start is enough.
        ($sdks | Where-Object -FilterScript { $_ -match '^\d+\.\d+\.\d+' }).Count | Should -BeGreaterThan 0
    }
}
