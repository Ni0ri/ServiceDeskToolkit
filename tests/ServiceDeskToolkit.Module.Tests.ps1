BeforeDiscovery {
    $manifestPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'ServiceDeskToolkit/ServiceDeskToolkit.psd1'
    Import-Module $manifestPath -Force
    $exportedFunctions = @((Get-Module ServiceDeskToolkit).ExportedFunctions.Keys | ForEach-Object { @{ Name = $_ } })
    $sourceFiles = @(Get-ChildItem -Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'ServiceDeskToolkit') -Recurse -Include '*.ps1', '*.psm1', '*.psd1' |
            ForEach-Object { @{ Name = $_.Name; FullName = $_.FullName } })
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $manifestPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'ServiceDeskToolkit/ServiceDeskToolkit.psd1'
}

AfterAll {
    Get-Module ServiceDeskToolkit | Remove-Module -Force
}

Describe 'Module manifest' {
    It 'is valid' {
        { Test-ModuleManifest -Path $manifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'names Artur Warkentin as author and supports Windows PowerShell 5.1 and PowerShell 7' {
        $manifest = Import-PowerShellDataFile -Path $manifestPath
        $manifest.Author | Should -Be 'Artur Warkentin'
        $manifest.PowerShellVersion | Should -Be '5.1'
        $manifest.CompatiblePSEditions | Should -Be @('Desktop', 'Core')
    }

    It 'exports exactly the public functions' {
        $exported = (Get-Module ServiceDeskToolkit).ExportedFunctions.Keys | Sort-Object
        $exported | Should -Be @('Get-SDIntuneNoncompliantReport', 'Get-SDMailboxPermissionAudit', 'Invoke-SDOffboarding', 'Test-SDToolkit')
    }

    It 'has a public file for every exported function' {
        $publicFiles = Get-ChildItem -Path (Join-Path (Split-Path $manifestPath -Parent) 'Public') -Filter '*.ps1' | ForEach-Object BaseName | Sort-Object
        $manifest = Import-PowerShellDataFile -Path $manifestPath
        $publicFiles | Should -Be ($manifest.FunctionsToExport | Sort-Object)
    }
}

Describe 'Source files' {
    It '<Name> contains only ASCII characters (safe for Windows PowerShell 5.1 without BOM)' -ForEach $sourceFiles {
        $content = [IO.File]::ReadAllText($FullName)
        $content | Should -Not -Match '[^\x00-\x7F]'
    }
}

Describe 'Help for <Name>' -ForEach $exportedFunctions {
    BeforeAll {
        $help = Get-Help -Name $Name -Full
        $command = Get-Command -Name $Name
        $commonParameters = [System.Management.Automation.PSCmdlet]::CommonParameters + [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
    }

    It 'has a synopsis and a description' {
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Synopsis | Should -Not -Match "^\s*$Name"
        ($help.Description | Out-String).Trim().Length | Should -BeGreaterThan 40
    }

    It 'has at least two examples with explanation' {
        @($help.Examples.Example).Count | Should -BeGreaterOrEqual 2
        foreach ($example in $help.Examples.Example) {
            $example.Code | Should -Not -BeNullOrEmpty
            ($example.Remarks | Out-String).Trim() | Should -Not -BeNullOrEmpty
        }
    }

    It 'documents every parameter' {
        foreach ($parameter in $command.Parameters.Keys | Where-Object { $commonParameters -notcontains $_ }) {
            $parameterHelp = $help.Parameters.Parameter | Where-Object Name -EQ $parameter
            ($parameterHelp.Description | Out-String).Trim() | Should -Not -BeNullOrEmpty -Because "parameter -$parameter needs a description"
        }
    }

    It 'has notes with author, version and changelog' {
        $notes = $help.alertSet | Out-String
        $notes | Should -Match 'Author:\s+Artur Warkentin'
        $notes | Should -Match 'Version:\s+\d+\.\d+\.\d+'
        $notes | Should -Match 'Changelog'
    }
}

Describe 'Safety settings' {
    It 'Invoke-SDOffboarding supports -WhatIf/-Confirm with high confirm impact' {
        $command = Get-Command Invoke-SDOffboarding
        $command.Parameters.Keys | Should -Contain 'WhatIf'
        $command.Parameters.Keys | Should -Contain 'Confirm'
        $binding = $command.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
        $binding.ConfirmImpact | Should -Be 'High'
    }

    It 'report functions do not change anything and therefore have no -WhatIf' {
        (Get-Command Get-SDIntuneNoncompliantReport).Parameters.Keys | Should -Not -Contain 'WhatIf'
        (Get-Command Get-SDMailboxPermissionAudit).Parameters.Keys | Should -Not -Contain 'WhatIf'
    }
}

Describe 'Test-SDToolkit' {
    It 'passes all built-in self tests' {
        $result = Test-SDToolkit
        $result.Passed | Should -Be $result.Total
        $result.Total | Should -BeGreaterThan 10
        $result.Summary | Should -Match "^$($result.Total)/$($result.Total) Tests gr"
    }

    It 'returns single results with -PassThru' {
        $results = @(Test-SDToolkit -PassThru)
        $results.Count | Should -BeGreaterThan 10
        $results | Where-Object { -not $_.Passed } | Should -BeNullOrEmpty
    }
}
