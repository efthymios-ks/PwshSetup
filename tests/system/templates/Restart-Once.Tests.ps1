BeforeDiscovery {
    $marker = Join-Path -Path $env:ProgramData -ChildPath 'PwshSetup\restart-once.txt'
    $script:detected = Test-Path -LiteralPath $marker
}

Describe 'Restart-Once' -Skip:(-not $script:detected) {
    BeforeAll {
        # BeforeDiscovery variables live in a different Pester scope and do not reach It. Re-resolve here.
        $marker = Join-Path -Path $env:ProgramData -ChildPath 'PwshSetup\restart-once.txt'
    }

    It 'when restarted, should leave the marker file' {
        $marker | Should -Exist
    }

    It 'when restarted, should hold an ISO-8601 time in the marker' {
        $value = Get-Content -LiteralPath $marker -Raw
        [datetime]::Parse($value.Trim()) | Should -BeOfType [datetime]
    }
}
