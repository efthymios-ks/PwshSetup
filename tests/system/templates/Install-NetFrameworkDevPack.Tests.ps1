BeforeDiscovery {
    # The dev pack puts reference assemblies under this fixed path; file presence is cheap and accurate.
    $referenceRoot = Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8.1'
    $script:detected = Test-Path -LiteralPath (Join-Path -Path $referenceRoot -ChildPath 'mscorlib.dll')
}

Describe 'Install-NetFrameworkDevPack' -Skip:(-not $script:detected) {
    BeforeAll {
        # BeforeDiscovery variables live in a different Pester scope and do not reach It. Re-resolve here.
        $referenceRoot = Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8.1'
    }

    It 'when installed, should have the 4.8.1 reference assemblies on disk' {
        Join-Path -Path $referenceRoot -ChildPath 'mscorlib.dll' | Should -Exist
    }
}
