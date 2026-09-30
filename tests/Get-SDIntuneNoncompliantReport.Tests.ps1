BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

AfterAll {
    Get-Module ServiceDeskToolkit | Remove-Module -Force
}

Describe 'Get-SDIntuneNoncompliantReport' {
    BeforeEach {
        $outDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $logDir = Join-Path $outDir 'logs'

        Mock -ModuleName ServiceDeskToolkit Get-MgContext {
            [pscustomobject]@{ Account = 'admin@contoso.com'; TenantId = 'tenant-1'; AuthType = 'Delegated'; Scopes = @('DeviceManagementManagedDevices.Read.All', 'DeviceManagementConfiguration.Read.All') }
        }
        Mock -ModuleName ServiceDeskToolkit Get-MgDeviceManagementManagedDevice {
            $now = [datetime]::UtcNow
            [pscustomobject]@{ Id = 'dev-1'; DeviceName = 'PC-0815'; UserPrincipalName = 'max@contoso.com'; UserDisplayName = 'Max Muster'; OperatingSystem = 'Windows'; OSVersion = '10.0.26100.1'; ComplianceState = 'noncompliant'; LastSyncDateTime = $now.AddDays(-45); EnrolledDateTime = $now.AddDays(-400); ComplianceGracePeriodExpirationDateTime = $null; ManagedDeviceOwnerType = 'company'; ManagementAgent = 'mdm'; Manufacturer = 'Lenovo'; Model = 'T14'; SerialNumber = 'SN1'; AzureAdDeviceId = 'aad-1' }
            [pscustomobject]@{ Id = 'dev-2'; DeviceName = 'iPhone <Erika>'; UserPrincipalName = 'erika@contoso.com'; UserDisplayName = 'Erika'; OperatingSystem = 'iOS'; OSVersion = '19.0'; ComplianceState = 'noncompliant'; LastSyncDateTime = $now.AddHours(-3); EnrolledDateTime = $now.AddDays(-30); ComplianceGracePeriodExpirationDateTime = $null; ManagedDeviceOwnerType = 'personal'; ManagementAgent = 'mdm'; Manufacturer = 'Apple'; Model = 'iPhone 17'; SerialNumber = 'SN2'; AzureAdDeviceId = 'aad-2' }
            [pscustomobject]@{ Id = 'dev-3'; DeviceName = 'Pixel'; UserPrincipalName = 'tom@contoso.com'; UserDisplayName = 'Tom'; OperatingSystem = 'Android'; OSVersion = '16'; ComplianceState = 'noncompliant'; LastSyncDateTime = [datetime]'0001-01-01'; EnrolledDateTime = $now.AddDays(-5); ComplianceGracePeriodExpirationDateTime = $null; ManagedDeviceOwnerType = 'company'; ManagementAgent = 'mdm'; Manufacturer = 'Google'; Model = 'Pixel 10'; SerialNumber = 'SN3'; AzureAdDeviceId = 'aad-3' }
        }
        Mock -ModuleName ServiceDeskToolkit Get-MgDeviceManagementManagedDeviceCompliancePolicyState {
            [pscustomobject]@{ DisplayName = 'Win - BitLocker'; State = 'nonCompliant' }
            [pscustomobject]@{ DisplayName = 'Win - Defender'; State = 'compliant' }
            [pscustomobject]@{ DisplayName = 'Win - Firewall'; State = 'error' }
        }

        $params = @{ OutputDirectory = $outDir; LogDirectory = $logDir }
    }

    It 'queries only non-compliant devices with a property selection' {
        $null = Get-SDIntuneNoncompliantReport @params
        Should -Invoke -ModuleName ServiceDeskToolkit Get-MgDeviceManagementManagedDevice -Times 1 -Exactly -ParameterFilter {
            $Filter -eq "complianceState eq 'noncompliant'" -and $All -and $Property -contains 'lastSyncDateTime'
        }
    }

    It 'includes the grace period when asked' {
        $null = Get-SDIntuneNoncompliantReport @params -IncludeInGracePeriod
        Should -Invoke -ModuleName ServiceDeskToolkit Get-MgDeviceManagementManagedDevice -Times 1 -Exactly -ParameterFilter { $Filter -match "inGracePeriod" }
    }

    It 'returns one row per device, stale devices first' {
        $rows = @(Get-SDIntuneNoncompliantReport @params)
        $rows.Count | Should -Be 3
        $rows[0].Stale | Should -BeTrue
        $rows[-1].DeviceName | Should -Be 'iPhone <Erika>'
        $rows[-1].Stale | Should -BeFalse
        $rows[0].PSObject.TypeNames | Should -Contain 'ServiceDeskToolkit.IntuneNoncompliantDevice'
    }

    It 'calculates the days since the last check-in' {
        $rows = @(Get-SDIntuneNoncompliantReport @params)
        ($rows | Where-Object DeviceName -EQ 'PC-0815').DaysSinceLastSync | Should -Be 45
        ($rows | Where-Object DeviceName -EQ 'iPhone <Erika>').DaysSinceLastSync | Should -Be 0
    }

    It 'treats a device that never checked in as stale' {
        $pixel = @(Get-SDIntuneNoncompliantReport @params) | Where-Object DeviceName -EQ 'Pixel'
        $pixel.LastSyncDateTime | Should -BeNullOrEmpty
        $pixel.DaysSinceLastSync | Should -BeNullOrEmpty
        $pixel.Stale | Should -BeTrue
    }

    It 'respects -StaleAfterDays' {
        $rows = @(Get-SDIntuneNoncompliantReport @params -StaleAfterDays 60)
        ($rows | Where-Object DeviceName -EQ 'PC-0815').Stale | Should -BeFalse
    }

    It 'filters by operating system' {
        $rows = @(Get-SDIntuneNoncompliantReport @params -OperatingSystem Windows, Android)
        $rows.DeviceName | Should -Not -Contain 'iPhone <Erika>'
        $rows.Count | Should -Be 2
    }

    It 'writes a CSV with all devices and a header' {
        $null = Get-SDIntuneNoncompliantReport @params
        $csv = Get-ChildItem -Path $outDir -Filter 'IntuneNoncompliant_*.csv'
        $csv.Count | Should -Be 1
        $csv.Name | Should -Match '^IntuneNoncompliant_\d{4}-\d{2}-\d{2}_\d{4}\.csv$'
        $data = @(Import-Csv -LiteralPath $csv.FullName)
        $data.Count | Should -Be 3
        $data[0].PSObject.Properties.Name | Should -Contain 'DaysSinceLastSync'
        $data[0].PSObject.Properties.Name | Should -Not -Contain 'NoncompliantPolicies'
        ($data | Where-Object DeviceName -EQ 'PC-0815').LastSyncDateTime | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$'
    }

    It 'writes the CSV with a BOM so Excel detects UTF-8' {
        $null = Get-SDIntuneNoncompliantReport @params
        $csv = Get-ChildItem -Path $outDir -Filter 'IntuneNoncompliant_*.csv'
        $bytes = [IO.File]::ReadAllBytes($csv.FullName)
        $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
    }

    It 'uses the given CSV delimiter' {
        $null = Get-SDIntuneNoncompliantReport @params -Delimiter ';'
        $csv = Get-ChildItem -Path $outDir -Filter 'IntuneNoncompliant_*.csv'
        (Get-Content -LiteralPath $csv.FullName -TotalCount 1) | Should -Match '^"DeviceName";"UserPrincipalName";'
    }

    It 'writes an HTML report with encoded values, summary and highlighted stale rows' {
        $null = Get-SDIntuneNoncompliantReport @params
        $html = Get-Content -LiteralPath (Get-ChildItem -Path $outDir -Filter 'IntuneNoncompliant_*.html').FullName -Raw
        $html | Should -Match '<title>Intune - non-compliant devices</title>'
        $html | Should -Match 'iPhone &lt;Erika&gt;'
        $html | Should -Not -Match 'iPhone <Erika>'
        $html | Should -Match '<dt>Devices</dt><dd>3</dd>'
        $html | Should -Match '<dt>Windows</dt><dd>1</dd>'
        ([regex]::Matches($html, '<tr class="flag">')).Count | Should -Be 2
    }

    It 'adds the failing policies with -IncludePolicyDetails' {
        $rows = @(Get-SDIntuneNoncompliantReport @params -IncludePolicyDetails)
        Should -Invoke -ModuleName ServiceDeskToolkit Get-MgDeviceManagementManagedDeviceCompliancePolicyState -Times 3 -Exactly
        $rows[0].NoncompliantPolicies | Should -Be 'Win - BitLocker (nonCompliant); Win - Firewall (error)'
        $csv = Import-Csv -LiteralPath (Get-ChildItem -Path $outDir -Filter 'IntuneNoncompliant_*.csv').FullName
        $csv[0].PSObject.Properties.Name | Should -Contain 'NoncompliantPolicies'
    }

    It 'continues when policy details of one device cannot be read' {
        Mock -ModuleName ServiceDeskToolkit Get-MgDeviceManagementManagedDeviceCompliancePolicyState { throw 'Forbidden' } -ParameterFilter { $ManagedDeviceId -eq 'dev-2' }
        $rows = @(Get-SDIntuneNoncompliantReport @params -IncludePolicyDetails -WarningAction SilentlyContinue)
        $rows.Count | Should -Be 3
        ($rows | Where-Object IntuneDeviceId -EQ 'dev-2').NoncompliantPolicies | Should -Be 'n/a'
    }

    It 'writes empty reports when every device is compliant' {
        Mock -ModuleName ServiceDeskToolkit Get-MgDeviceManagementManagedDevice { }
        $rows = @(Get-SDIntuneNoncompliantReport @params)
        $rows.Count | Should -Be 0
        $csv = Get-ChildItem -Path $outDir -Filter 'IntuneNoncompliant_*.csv'
        (Get-Content -LiteralPath $csv.FullName) | Should -Match '^"DeviceName","UserPrincipalName"'
        (Get-Content -LiteralPath (Get-ChildItem -Path $outDir -Filter 'IntuneNoncompliant_*.html').FullName -Raw) | Should -Match 'No entries found'
    }

    It 'logs the file paths' {
        $null = Get-SDIntuneNoncompliantReport @params
        $log = Get-Content -LiteralPath (Join-Path $logDir ('Log_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd'))) -Raw
        $log | Should -Match '\[INFO\] CSV report: .*IntuneNoncompliant_.*\.csv'
        $log | Should -Match '\[INFO\] HTML report: .*IntuneNoncompliant_.*\.html'
    }

    It 'throws when Microsoft Graph is not connected' {
        Mock -ModuleName ServiceDeskToolkit Get-MgContext { $null }
        { Get-SDIntuneNoncompliantReport @params } | Should -Throw '*Connect-MgGraph*'
        Should -Invoke -ModuleName ServiceDeskToolkit Get-MgDeviceManagementManagedDevice -Times 0
    }

    It 'rethrows Graph errors after logging them' {
        Mock -ModuleName ServiceDeskToolkit Get-MgDeviceManagementManagedDevice { throw 'Request throttled' }
        { Get-SDIntuneNoncompliantReport @params } | Should -Throw '*Request throttled*'
        $log = Get-Content -LiteralPath (Join-Path $logDir ('Log_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd'))) -Raw
        $log | Should -Match '\[ERROR\] Get-SDIntuneNoncompliantReport failed: Request throttled'
    }
}
