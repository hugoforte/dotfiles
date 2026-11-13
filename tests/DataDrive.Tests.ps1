# data-drive.ps1: which drive a machine names, where a store goes, and the move itself, on folders
# under TestDrive. install-data-drive.ps1, which sets the user's real variables, is not run here.

BeforeAll {
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'powershell\data-drive.ps1')
}

Describe 'Get-DataDrive' {
    It 'reads the first file that names a drive' {
        Set-Content "TestDrive:\none.psd1" "@{ OptionalTools = @('dev') }"
        Set-Content "TestDrive:\machine.psd1" "@{ DataDrive = 'd' }"
        Get-DataDrive -Path "TestDrive:\missing.psd1", "TestDrive:\none.psd1", "TestDrive:\machine.psd1" | Should -Be 'D:'
    }

    It 'accepts a drive written with a colon and backslash' {
        Set-Content "TestDrive:\machine.psd1" "@{ DataDrive = 'E:\' }"
        Get-DataDrive -Path "TestDrive:\machine.psd1" | Should -Be 'E:'
    }

    It 'returns nothing when no file names one' {
        Get-DataDrive -Path @("TestDrive:\missing.psd1") | Should -BeNullOrEmpty
    }

    It 'refuses a value that is not a drive letter, naming the file' {
        Set-Content "TestDrive:\machine.psd1" "@{ DataDrive = 'D:\Data' }"
        { Get-DataDrive -Path "TestDrive:\machine.psd1" } | Should -Throw "*machine.psd1*D:\Data*"
    }
}

Describe 'Get-DataDriveTarget' {
    It 'keeps the path and swaps the drive' {
        Get-DataDriveTarget -DataDrive 'D:' -ProfilePath 'C:\Users\me' -Relative 'AppData\Local\npm-cache' |
            Should -Be 'D:\Users\me\AppData\Local\npm-cache'
    }
}

Describe 'Get-DataDriveStores' {
    It 'names each store once' {
        $relatives = @(Get-DataDriveStores | ForEach-Object { $_.Relative })
        ($relatives | Select-Object -Unique).Count | Should -Be $relatives.Count
    }
}

Describe 'Move-StoreToDataDrive' {
    BeforeEach {
        $root = (New-Item -ItemType Directory -Path "TestDrive:\$([guid]::NewGuid())").FullName
        $path = Join-Path $root 'system\store'
        $target = Join-Path $root 'data\store'
    }

    It 'moves the files and leaves a junction to them' {
        New-Item -ItemType Directory -Path "$path\sub" -Force | Out-Null
        Set-Content "$path\sub\file.txt" 'cached'

        Move-StoreToDataDrive -Path $path -Target $target | Should -Be 'Moved'

        Get-Content "$target\sub\file.txt" | Should -Be 'cached'
        Get-JunctionTarget -Path $path | Should -Be $target
        Get-Content "$path\sub\file.txt" | Should -Be 'cached'
        Test-Path "$path.moving-to-data-drive" | Should -BeFalse
    }

    It 'changes nothing on a second run' {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Move-StoreToDataDrive -Path $path -Target $target | Out-Null

        Move-StoreToDataDrive -Path $path -Target $target | Should -Be 'Moved'
        Get-StoreState -Path $path -Target $target | Should -Be 'Moved'
    }

    It 'makes nothing for a store that is not there' {
        Move-StoreToDataDrive -Path $path -Target $target | Should -Be 'Absent'
        Test-Path $path | Should -BeFalse
        Test-Path $target | Should -BeFalse
    }

    It 'leaves a store whose file is open where it is' {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Set-Content "$path\state.db" 'live'
        $handle = [IO.File]::Open("$path\state.db", 'Open', 'ReadWrite', 'Read')
        try {
            Move-StoreToDataDrive -Path $path -Target $target | Should -Be 'InUse'
        } finally {
            $handle.Close()
        }
        Get-StoreState -Path $path -Target $target | Should -Be 'OnSystem'
        Test-Path $target | Should -BeFalse
    }

    It 'keeps the newer copy when the data drive already has the store' {
        New-Item -ItemType Directory -Path $path, $target -Force | Out-Null
        Set-Content "$path\old.txt" 'from system'
        Set-Content "$target\old.txt" 'newer on data'
        (Get-Item "$path\old.txt").LastWriteTime = (Get-Date).AddDays(-1)

        Move-StoreToDataDrive -Path $path -Target $target | Should -Be 'Moved'

        Get-Content "$target\old.txt" | Should -Be 'newer on data'
    }

    It 'refuses a store linked somewhere else' {
        $elsewhere = Join-Path $root 'elsewhere'
        New-Item -ItemType Directory -Path $elsewhere, (Split-Path $path) -Force | Out-Null
        $null = cmd /c mklink /J $path $elsewhere

        { Move-StoreToDataDrive -Path $path -Target $target } | Should -Throw "*somewhere other than*"
    }

    It 'refuses to start over a move that did not finish' {
        New-Item -ItemType Directory -Path $path, "$path.moving-to-data-drive" -Force | Out-Null
        { Move-StoreToDataDrive -Path $path -Target $target } | Should -Throw "*did not finish*"
    }
}

Describe 'Get-StoreHolder' {
    It 'names a running program the store lists' {
        $self = (Get-Process -Id $PID).ProcessName
        Get-StoreHolder -Path 'TestDrive:\nowhere' -Processes @($self) | Should -Be $self
    }

    It 'names a program running from inside the store' {
        $self = Get-Process -Id $PID
        Get-StoreHolder -Path (Split-Path $self.Path) | Should -Not -BeNullOrEmpty
    }

    It 'returns nothing when no program holds it' {
        Get-StoreHolder -Path 'TestDrive:\nowhere' -Processes @('no-such-program') | Should -BeNullOrEmpty
    }
}
