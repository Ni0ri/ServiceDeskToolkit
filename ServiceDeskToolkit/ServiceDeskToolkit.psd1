@{
    RootModule           = 'ServiceDeskToolkit.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'e2315571-1e81-4ed7-ab71-6363c98352d8'
    Author               = 'Artur Warkentin'
    CompanyName          = 'Artur Warkentin'
    Copyright            = '(c) 2026 Artur Warkentin. Licensed under the MIT License.'
    Description          = 'Service desk automation for Microsoft 365: Entra ID user offboarding, Intune non-compliant device report and Exchange Online mailbox permission audit. Every change supports -WhatIf and is logged.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # Microsoft.Graph.* and ExchangeOnlineManagement are intentionally NOT listed in
    # RequiredModules: each function only needs the modules for its own task and checks
    # for them (and for an active connection) at runtime. See README.
    FunctionsToExport    = @(
        'Invoke-SDOffboarding'
        'Get-SDIntuneNoncompliantReport'
        'Get-SDMailboxPermissionAudit'
        'Test-SDToolkit'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags                       = @('M365', 'Microsoft365', 'EntraID', 'AzureAD', 'Intune', 'ExchangeOnline', 'Offboarding', 'MicrosoftGraph', 'ServiceDesk', 'Report', 'PSEdition_Desktop', 'PSEdition_Core')
            LicenseUri = 'https://github.com/Ni0ri/ServiceDeskToolkit/blob/main/LICENSE'
            ProjectUri = 'https://github.com/Ni0ri/ServiceDeskToolkit'
            ExternalModuleDependencies = @(
                'Microsoft.Graph.Authentication'
                'Microsoft.Graph.Users'
                'Microsoft.Graph.Users.Actions'
                'Microsoft.Graph.Groups'
                'Microsoft.Graph.DeviceManagement'
                'ExchangeOnlineManagement'
            )
            ReleaseNotes               = '0.1.0 - Initial version: Invoke-SDOffboarding, Get-SDIntuneNoncompliantReport, Get-SDMailboxPermissionAudit, Test-SDToolkit.'
        }
    }
}
