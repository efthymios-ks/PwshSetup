BeforeDiscovery {
    # The folder the sample setup unpacks into, and the file its test ZIP holds.
    $target = 'C:\TestArchive\unpacked\hello.txt'
    $script:detected = Test-Path -LiteralPath $target
}

Describe 'Expand-Archive' -Skip:(-not $script:detected) {
    BeforeAll {
        $target = 'C:\TestArchive\unpacked\hello.txt'
    }

    It 'when expanded, should leave hello.txt on disk' {
        $target | Should -Exist
    }
}
