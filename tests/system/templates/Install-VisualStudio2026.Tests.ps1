BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_Helpers.ps1')
    $vswhere = Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Microsoft Visual Studio\Installer\vswhere.exe'
    $script:detected = (Test-Path -LiteralPath $vswhere) -and
        (@(& $vswhere -version '[18.0,19.0)' -products 'Microsoft.VisualStudio.Product.Community' -property instanceId 2>$null)).Count -gt 0
}

Describe 'Install-VisualStudio2026' -Skip:(-not $script:detected) {
    BeforeAll {
        # Re-resolved here because BeforeDiscovery runs in a different Pester scope and its locals
        # do not reach BeforeAll / It.
        $vswhere = Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Microsoft Visual Studio\Installer\vswhere.exe'
    }

    It 'when installed, should be found by vswhere as 2026 Community' {
        $instances = @(& $vswhere -version '[18.0,19.0)' -products 'Microsoft.VisualStudio.Product.Community' -property instanceId 2>$null)
        $instances.Count | Should -BeGreaterThan 0
    }
}
