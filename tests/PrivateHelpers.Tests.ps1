BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

AfterAll {
    Get-Module ServiceDeskToolkit | Remove-Module -Force
}

Describe 'Get-SDGroupRemovalMethod' {
    It '<Case> -> <Expected>' -ForEach @(
        @{ Case = 'security group'; Group = @{ Id = 'g'; GroupTypes = @(); MailEnabled = $false; OnPremisesSyncEnabled = $false }; Expected = 'Graph' }
        @{ Case = 'Microsoft 365 group'; Group = @{ Id = 'g'; GroupTypes = @('Unified'); MailEnabled = $true; OnPremisesSyncEnabled = $false }; Expected = 'Graph' }
        @{ Case = 'distribution list'; Group = @{ Id = 'g'; GroupTypes = @(); MailEnabled = $true; OnPremisesSyncEnabled = $false }; Expected = 'Exchange' }
        @{ Case = 'dynamic M365 group'; Group = @{ Id = 'g'; GroupTypes = @('Unified', 'DynamicMembership'); MailEnabled = $true; OnPremisesSyncEnabled = $false }; Expected = 'Skip' }
        @{ Case = 'synced group'; Group = @{ Id = 'g'; GroupTypes = @(); MailEnabled = $true; OnPremisesSyncEnabled = $true }; Expected = 'Skip' }
    ) {
        InModuleScope ServiceDeskToolkit -Parameters @{ Group = $Group; Expected = $Expected } {
            (Get-SDGroupRemovalMethod -Group ([pscustomobject]$Group)).Method | Should -Be $Expected
        }
    }
}

Describe 'Get-SDLicenseAssignment' {
    It 'keeps a SKU that is assigned directly and by group in the direct list only' {
        InModuleScope ServiceDeskToolkit {
            $result = Get-SDLicenseAssignment -LicenseAssignmentStates @(
                [pscustomobject]@{ SkuId = 'a'; AssignedByGroup = $null }
                [pscustomobject]@{ SkuId = 'a'; AssignedByGroup = 'grp' }
                [pscustomobject]@{ SkuId = 'b'; AssignedByGroup = 'grp' })
            $result.Direct | Should -Be @('a')
            $result.Inherited | Should -Be @('b')
        }
    }

    It 'returns empty lists for an unlicensed user' {
        InModuleScope ServiceDeskToolkit {
            $result = Get-SDLicenseAssignment -LicenseAssignmentStates $null -AssignedLicenses $null
            @($result.Direct).Count | Should -Be 0
            @($result.Inherited).Count | Should -Be 0
        }
    }
}

Describe 'Get-SDPropertyValue' {
    It 'reads properties, dictionary keys and returns $null for missing names' {
        InModuleScope ServiceDeskToolkit {
            Get-SDPropertyValue -InputObject ([pscustomobject]@{ A = 1 }) -Name 'A' | Should -Be 1
            Get-SDPropertyValue -InputObject ([pscustomobject]@{ A = 1 }) -Name 'B' | Should -BeNullOrEmpty
            $dict = New-Object 'System.Collections.Generic.Dictionary[string,object]'
            $dict['displayName'] = 'X'
            Get-SDPropertyValue -InputObject $dict -Name 'displayName' | Should -Be 'X'
            Get-SDPropertyValue -InputObject $dict -Name 'mail' | Should -BeNullOrEmpty
            Get-SDPropertyValue -InputObject $null -Name 'A' | Should -BeNullOrEmpty
        }
    }
}

Describe 'Format-SDCellValue' {
    It 'formats dates, lists and nulls' {
        InModuleScope ServiceDeskToolkit {
            Format-SDCellValue -Value ([datetime]'2026-09-30 14:05:00') | Should -Be '2026-09-30 14:05'
            Format-SDCellValue -Value @('a', 'b') | Should -Be 'a; b'
            Format-SDCellValue -Value $null | Should -Be ''
            Format-SDCellValue -Value 1.5 | Should -Be '1.5'
        }
    }
}

Describe 'Write-SDLog' {
    It 'writes timestamped lines with level to Log_yyyy-MM-dd.log' {
        InModuleScope ServiceDeskToolkit -Parameters @{ Dir = (Join-Path $TestDrive 'log') } {
            Write-SDLog -Message 'hello' -LogDirectory $Dir
            Write-SDLog -Message 'careful' -Level WARN -LogDirectory $Dir -WarningAction SilentlyContinue
            $lines = Get-Content -LiteralPath (Join-Path $Dir ('Log_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd')))
            $lines[0] | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[INFO\] hello$'
            $lines[1] | Should -Match '\[WARN\] careful$'
        }
    }

    It 'writes the log even while -WhatIf is active' {
        InModuleScope ServiceDeskToolkit -Parameters @{ Dir = (Join-Path $TestDrive 'whatif') } {
            $WhatIfPreference = $true
            Write-SDLog -Message 'planned' -LogDirectory $Dir
            Join-Path $Dir ('Log_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd')) | Should -Exist
        }
    }
}
