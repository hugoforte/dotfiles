# Add-HighDpiAwareLayer, the decision behind a manifest entry's HighDpiAware programs.
# Set-HighDpiAware applies it to the real user registry and is not run here.

BeforeAll {
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'powershell\high-dpi.ps1')
}

Describe 'Add-HighDpiAwareLayer' {
    It 'starts the value the way Windows writes it when the program has none' {
        Add-HighDpiAwareLayer -Layers $null | Should -Be '~ HIGHDPIAWARE'
    }

    It 'returns nothing when the program already runs DPI-aware' {
        Add-HighDpiAwareLayer -Layers '~ HIGHDPIAWARE' | Should -BeNullOrEmpty
    }

    It 'matches the flag whatever its case' {
        Add-HighDpiAwareLayer -Layers '~ HighDpiAware' | Should -BeNullOrEmpty
    }

    It 'keeps the flags already there' {
        Add-HighDpiAwareLayer -Layers '~ RUNASADMIN' | Should -Be '~ RUNASADMIN HIGHDPIAWARE'
    }

    It 'returns nothing when the flag sits among others' {
        Add-HighDpiAwareLayer -Layers '~ RUNASADMIN HIGHDPIAWARE WIN8RTM' | Should -BeNullOrEmpty
    }

    It 'replaces scaling performed by the system' {
        Add-HighDpiAwareLayer -Layers '~ RUNASADMIN DPIUNAWARE' | Should -Be '~ RUNASADMIN HIGHDPIAWARE'
    }

    It 'replaces scaling performed by the system, enhanced' {
        Add-HighDpiAwareLayer -Layers '~ GDIDPISCALING DPIUNAWARE' | Should -Be '~ HIGHDPIAWARE'
    }

    It 'drops another scaling answer left beside the flag' {
        Add-HighDpiAwareLayer -Layers '~ HIGHDPIAWARE DPIUNAWARE' | Should -Be '~ HIGHDPIAWARE'
    }
}
