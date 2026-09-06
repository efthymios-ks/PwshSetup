BeforeDiscovery {
    # Matches the DestinationPath the hyperv Setup step passes to Copy-Repository.
    $target = 'C:\TestRepos\PwshAnsi'
    $script:detected = Test-Path -LiteralPath (Join-Path -Path $target -ChildPath '.git') -PathType Container
}

Describe 'Copy-Repository' -Skip:(-not $script:detected) {
    BeforeAll {
        $target = 'C:\TestRepos\PwshAnsi'
    }

    It 'when cloned, should have a .git folder' {
        Join-Path -Path $target -ChildPath '.git' | Should -Exist
    }
}
