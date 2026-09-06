BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_Helpers.ps1')
    $script:detected = Test-InstalledApp -DisplayName 'Notepad++'
}

Describe 'Install-NotepadPlusPlus' -Skip:(-not $script:detected) {
    It 'when installed, should be listed in Installed apps' {
        Test-InstalledApp -DisplayName 'Notepad++' | Should -BeTrue
    }
}
