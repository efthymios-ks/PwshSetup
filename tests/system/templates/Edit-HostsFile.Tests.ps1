BeforeDiscovery {
    # Matches the entry the hyperv Setup step passes to Edit-HostsFile.
    $hosts = Join-Path -Path $env:SystemRoot -ChildPath 'System32\drivers\etc\hosts'
    $script:detected = (Test-Path -LiteralPath $hosts) -and
        ((Get-Content -LiteralPath $hosts -Raw -ErrorAction Ignore) -match '127\.0\.0\.1\s+pwshsetup\.test')
}

Describe 'Edit-HostsFile' -Skip:(-not $script:detected) {
    BeforeAll {
        $hosts = Join-Path -Path $env:SystemRoot -ChildPath 'System32\drivers\etc\hosts'
    }

    It 'when edited, should hold the pwshsetup.test entry' {
        (Get-Content -LiteralPath $hosts -Raw) | Should -Match '127\.0\.0\.1\s+pwshsetup\.test'
    }
}
