@{
    RootModule           = 'ServiceDeskToolkit.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = 'e2315571-1e81-4ed7-ab71-6363c98352d8'
    Author               = 'Artur Warkentin'
    CompanyName          = 'Artur Warkentin'
    Copyright            = '(c) 2026 Artur Warkentin. Licensed under the MIT License.'
    Description          = 'Microsoft 365 service desk automation for Entra ID, Exchange Online and Intune. Invoke-SDOffboarding disables the account, revokes sessions, converts the mailbox to a shared mailbox (optional FullAccess, forwarding and auto reply) and removes group memberships and direct licenses, with a JSON backup first and a per-step result. Get-SDIntuneNoncompliantReport exports non-compliant devices with days since last check-in and failing policies; Get-SDMailboxPermissionAudit exports FullAccess, SendAs and SendOnBehalf permissions and flags orphaned entries (CSV and HTML). Every change supports -WhatIf/-Confirm and is logged. Works with Windows PowerShell 5.1 and PowerShell 7. The Microsoft.Graph and ExchangeOnlineManagement modules are needed only by the functions that use them; they are checked at runtime and not installed automatically.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # Microsoft.Graph.* and ExchangeOnlineManagement are intentionally NOT listed in
    # RequiredModules: as hard dependencies, Install-Module/Install-PSResource would pull
    # all of them (and Import-Module would fail without them) even for users who only need
    # one function, and loading Graph and Exchange Online assemblies at import time is a
    # known source of version conflicts (MSAL). Each function checks for its own modules
    # and an active connection at runtime. They are listed below as
    # ExternalModuleDependencies for documentation only. See README.
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
            Tags                       = @('M365', 'Microsoft365', 'EntraID', 'AzureAD', 'Intune', 'ExchangeOnline', 'Offboarding', 'MicrosoftGraph', 'ServiceDesk', 'Helpdesk', 'Report', 'Audit', 'Compliance', 'MailboxPermissions', 'Windows', 'Linux', 'PSEdition_Desktop', 'PSEdition_Core')
            LicenseUri                 = 'https://github.com/Ni0ri/ServiceDeskToolkit/blob/main/LICENSE'
            ProjectUri                 = 'https://github.com/Ni0ri/ServiceDeskToolkit'
            ExternalModuleDependencies = @(
                'Microsoft.Graph.Authentication'
                'Microsoft.Graph.Users'
                'Microsoft.Graph.Users.Actions'
                'Microsoft.Graph.Groups'
                'Microsoft.Graph.DeviceManagement'
                'ExchangeOnlineManagement'
            )
            ReleaseNotes               = @'
1.0.0 (2026-10-01) - First PowerShell Gallery release. No functional changes since 0.1.0.
- Invoke-SDOffboarding: disable account, revoke sessions, convert mailbox to shared, optional FullAccess/forwarding/auto reply, remove groups (Graph and Exchange Online) and direct licenses; JSON backup before changes, -WhatIf/-Confirm, per-step result.
- Get-SDIntuneNoncompliantReport: non-compliant Intune devices as CSV and HTML, stale check-in detection, optional policy details.
- Get-SDMailboxPermissionAudit: FullAccess, SendAs and SendOnBehalf permissions as CSV and HTML, orphaned SID detection.
- Test-SDToolkit: offline self-test of the core logic.
Full changelog: https://github.com/Ni0ri/ServiceDeskToolkit/blob/main/CHANGELOG.md
'@
        }
    }
}
