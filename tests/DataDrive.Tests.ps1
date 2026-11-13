# data-drive.ps1: which drive a machine names, where a store goes, and the move itself, on folders
# under TestDrive. install-data-drive.ps1, which sets the user's real variables, is not run here.

BeforeAll {
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'powershell\native.ps1')
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

    It 'lets an earlier file turn a later one off with an empty value' {
        Set-Content "TestDrive:\local.psd1" "@{ DataDrive = '' }"
        Set-Content "TestDrive:\machine.psd1" "@{ DataDrive = 'D:' }"
        Get-DataDrive -Path "TestDrive:\local.psd1", "TestDrive:\machine.psd1" | Should -BeNullOrEmpty
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

    It "gives the profile's own folder for no relative path" {
        Get-DataDriveTarget -DataDrive 'D:' -ProfilePath 'C:\Users\me' -Relative '' | Should -Be 'D:\Users\me'
    }
}

Describe 'ConvertTo-DataDrive' {
    It 'refuses a folder, naming where the value came from' {
        { ConvertTo-DataDrive -Value 'D:\Data' -Source '-DataDrive' } | Should -Throw "*-DataDrive*D:\Data*"
    }
}

Describe 'Get-StoreVariableAction' {
    It 'sets an unset variable' {
        Get-StoreVariableAction -Current '' -Path 'C:\u\.cache\hf' -Target 'D:\u\.cache\hf' | Should -Be 'Set'
    }

    It 'sets a variable that names the store on the system drive' {
        Get-StoreVariableAction -Current 'C:\u\.cache\hf\' -Path 'C:\u\.cache\hf' -Target 'D:\u\.cache\hf' | Should -Be 'Set'
    }

    It 'keeps a variable that already names the target' {
        Get-StoreVariableAction -Current 'd:\u\.cache\hf' -Path 'C:\u\.cache\hf' -Target 'D:\u\.cache\hf' | Should -Be 'Ok'
    }

    It 'leaves a variable someone pointed elsewhere' {
        Get-StoreVariableAction -Current 'E:\models' -Path 'C:\u\.cache\hf' -Target 'D:\u\.cache\hf' | Should -Be 'Foreign'
    }
}

Describe 'Initialize-DataDriveProfile' {
    It "gives the root the profile's access list, not the drive's" {
        $profileDir = (New-Item -ItemType Directory -Path "TestDrive:\profile-$([guid]::NewGuid())").FullName
        $acl = Get-Acl $profileDir
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($rule in @($acl.Access)) { [void]$acl.RemoveAccessRule($rule) }
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($me, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
        Set-Acl $profileDir $acl
        $root = Join-Path (Split-Path $profileDir) "data-$([guid]::NewGuid())\Users\me"

        Initialize-DataDriveProfile -ProfilePath $profileDir -Root $root -Check | Should -Be 'Missing'
        Initialize-DataDriveProfile -ProfilePath $profileDir -Root $root | Should -Be 'Created'

        $result = Get-Acl $root
        $result.AreAccessRulesProtected | Should -BeTrue
        @($result.Access | ForEach-Object { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value }) | Should -Be @($me.Value)
        Initialize-DataDriveProfile -ProfilePath $profileDir -Root $root | Should -Be 'AlreadySecure'
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

    It 'touches neither copy when both drives hold the store' {
        New-Item -ItemType Directory -Path $path, $target -Force | Out-Null
        Set-Content "$path\state.db" 'fresh and empty'
        Set-Content "$target\state.db" 'real history'

        Move-StoreToDataDrive -Path $path -Target $target | Should -Be 'OnBoth'

        Get-Content "$target\state.db" | Should -Be 'real history'
        Get-Content "$path\state.db" | Should -Be 'fresh and empty'
    }

    It 'moves junctions and symlinks inside the store as links' {
        New-Item -ItemType Directory -Path "$path\blobs", "$path\snapshots", "$root\elsewhere" -Force | Out-Null
        Set-Content "$path\blobs\abc" 'weights'
        $null = cmd /c mklink "$path\snapshots\model.bin" '..\blobs\abc'
        $symlinked = $LASTEXITCODE -eq 0
        New-Item -ItemType Junction -Path "$path\workspace" -Target "$root\elsewhere" | Out-Null

        Move-StoreToDataDrive -Path $path -Target $target | Should -Be 'Moved'

        Get-JunctionTarget -Path "$target\workspace" | Should -Be "$root\elsewhere"
        if ($symlinked) {
            (Get-Item "$target\snapshots\model.bin" -Force).Attributes -band [IO.FileAttributes]::ReparsePoint | Should -BeTrue
            Get-Content "$target\snapshots\model.bin" | Should -Be 'weights'
        }
    }

    It 'finishes a move that stopped partway' {
        New-Item -ItemType Directory -Path "$path.moving-to-data-drive", $target -Force | Out-Null
        Set-Content "$path.moving-to-data-drive\rest.txt" 'not yet moved'
        Set-Content "$target\done.txt" 'moved'

        Get-StoreState -Path $path -Target $target | Should -Be 'Interrupted'
        Move-StoreToDataDrive -Path $path -Target $target | Should -Be 'Moved'

        Get-Content "$path\rest.txt" | Should -Be 'not yet moved'
        Get-Content "$path\done.txt" | Should -Be 'moved'
        Test-Path "$path.moving-to-data-drive" | Should -BeFalse
    }

    It 'links a store the data drive kept after the system drive was rebuilt' {
        New-Item -ItemType Directory -Path $target, (Split-Path $path) -Force | Out-Null
        Set-Content "$target\kept.txt" 'kept'

        Move-StoreToDataDrive -Path $path -Target $target | Should -Be 'Relinked'

        Get-Content "$path\kept.txt" | Should -Be 'kept'
    }

    It 'reports a junction whose target is gone' {
        New-Item -ItemType Directory -Path $target, (Split-Path $path) -Force | Out-Null
        New-Item -ItemType Junction -Path $path -Target $target | Out-Null
        [IO.Directory]::Delete($target)

        Move-StoreToDataDrive -Path $path -Target $target | Should -Be 'Broken'
    }

    It 'refuses a store linked somewhere else' {
        $elsewhere = Join-Path $root 'elsewhere'
        New-Item -ItemType Directory -Path $elsewhere, (Split-Path $path) -Force | Out-Null
        $null = cmd /c mklink /J $path $elsewhere

        { Move-StoreToDataDrive -Path $path -Target $target } | Should -Throw "*somewhere other than*"
    }

    It 'refuses to resume a move once the store exists again' {
        New-Item -ItemType Directory -Path $path, "$path.moving-to-data-drive" -Force | Out-Null
        { Move-StoreToDataDrive -Path $path -Target $target } | Should -Throw "*did not finish*exists again*"
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
