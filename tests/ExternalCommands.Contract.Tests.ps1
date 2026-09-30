<#
    Contract tests: the stubs in Stubs/ExternalCommands.ps1 must match the real cmdlets.
    Runs only where the Microsoft Graph / ExchangeOnlineManagement modules are installed (no sign-in needed);
    otherwise the tests are skipped. Remote Exchange cmdlets (Set-Mailbox, ...) exist only after
    Connect-ExchangeOnline and cannot be checked offline.
#>
BeforeDiscovery {
    $contracts = @(
        @{ Module = 'Microsoft.Graph.Authentication'; Command = 'Get-MgContext'; Parameters = @() }
        @{ Module = 'Microsoft.Graph.Users'; Command = 'Get-MgUser'; Parameters = @('UserId', 'Property') }
        @{ Module = 'Microsoft.Graph.Users'; Command = 'Update-MgUser'; Parameters = @('UserId', 'AccountEnabled') }
        @{ Module = 'Microsoft.Graph.Users'; Command = 'Get-MgUserMemberOf'; Parameters = @('UserId', 'All') }
        @{ Module = 'Microsoft.Graph.Users'; Command = 'Get-MgUserLicenseDetail'; Parameters = @('UserId', 'All') }
        @{ Module = 'Microsoft.Graph.Users.Actions'; Command = 'Revoke-MgUserSignInSession'; Parameters = @('UserId') }
        @{ Module = 'Microsoft.Graph.Users.Actions'; Command = 'Set-MgUserLicense'; Parameters = @('UserId', 'AddLicenses', 'RemoveLicenses') }
        @{ Module = 'Microsoft.Graph.Groups'; Command = 'Remove-MgGroupMemberDirectoryObjectByRef'; Parameters = @('GroupId', 'DirectoryObjectId') }
        @{ Module = 'Microsoft.Graph.DeviceManagement'; Command = 'Get-MgDeviceManagementManagedDevice'; Parameters = @('Filter', 'Property', 'All') }
        @{ Module = 'Microsoft.Graph.DeviceManagement'; Command = 'Get-MgDeviceManagementManagedDeviceCompliancePolicyState'; Parameters = @('ManagedDeviceId', 'All') }
        @{ Module = 'ExchangeOnlineManagement'; Command = 'Get-ConnectionInformation'; Parameters = @() }
        @{ Module = 'ExchangeOnlineManagement'; Command = 'Get-EXOMailbox'; Parameters = @('Identity', 'Properties', 'RecipientTypeDetails', 'ResultSize') }
        @{ Module = 'ExchangeOnlineManagement'; Command = 'Get-EXOMailboxPermission'; Parameters = @('Identity') }
        @{ Module = 'ExchangeOnlineManagement'; Command = 'Get-EXORecipientPermission'; Parameters = @('Identity', 'AccessRights') }
        @{ Module = 'ExchangeOnlineManagement'; Command = 'Get-EXORecipient'; Parameters = @('Identity') }
    )
}

Describe 'External command contract' -Tag 'Contract' {
    It '<Command> (<Module>) has the parameters the module uses' -ForEach $contracts {
        if (-not (Get-Module -ListAvailable -Name $Module)) {
            Set-ItResult -Skipped -Because "$Module is not installed"
            return
        }
        $real = Get-Command -Name $Command -Module $Module -ErrorAction SilentlyContinue
        $real | Should -Not -BeNullOrEmpty -Because "$Command must exist in $Module"
        foreach ($parameter in $Parameters) {
            $real.Parameters.Keys | Should -Contain $parameter
        }
    }
}
