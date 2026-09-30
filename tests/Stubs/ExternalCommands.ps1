<#
    Stand-ins for Microsoft Graph and Exchange Online cmdlets.

    Pester can only mock commands that exist. These global stubs make the tests independent of the
    real modules (and of any tenant). Each stub only declares the parameters the module uses.
    ExternalCommands.Contract.Tests.ps1 checks these parameters against the real modules when installed.
    A stub that is called without a mock throws, so no test can silently "succeed" without a mock.
#>

$stubs = [ordered]@{
    # Microsoft.Graph.Authentication
    'Get-MgContext'                                        = 'param()'
    # Microsoft.Graph.Users / Users.Actions / Groups
    'Get-MgUser'                                           = 'param([string]$UserId, [string[]]$Property)'
    'Update-MgUser'                                        = 'param([string]$UserId, [switch]$AccountEnabled)'
    'Revoke-MgUserSignInSession'                           = 'param([string]$UserId)'
    'Get-MgUserMemberOf'                                   = 'param([string]$UserId, [switch]$All)'
    'Get-MgUserLicenseDetail'                              = 'param([string]$UserId, [switch]$All)'
    'Set-MgUserLicense'                                    = 'param([string]$UserId, [object[]]$AddLicenses, [string[]]$RemoveLicenses)'
    'Remove-MgGroupMemberDirectoryObjectByRef'                            = 'param([string]$GroupId, [string]$DirectoryObjectId)'
    # Microsoft.Graph.DeviceManagement
    'Get-MgDeviceManagementManagedDevice'                  = 'param([string]$Filter, [string[]]$Property, [switch]$All)'
    'Get-MgDeviceManagementManagedDeviceCompliancePolicyState' = 'param([string]$ManagedDeviceId, [switch]$All)'
    # ExchangeOnlineManagement (REST cmdlets inside the module)
    'Get-ConnectionInformation'                            = 'param()'
    'Get-EXOMailbox'                                       = 'param([string]$Identity, [string[]]$Properties, [string[]]$RecipientTypeDetails, [object]$ResultSize)'
    'Get-EXOMailboxPermission'                             = 'param([string]$Identity)'
    'Get-EXORecipientPermission'                           = 'param([string]$Identity, [string[]]$AccessRights)'
    'Get-EXORecipient'                                     = 'param([string]$Identity)'
    # ExchangeOnlineManagement (remote cmdlets, only available after Connect-ExchangeOnline)
    'Set-Mailbox'                                          = 'param([string]$Identity, [string]$Type, [string]$ForwardingAddress, [string]$ForwardingSmtpAddress, [bool]$DeliverToMailboxAndForward)'
    'Add-MailboxPermission'                                = 'param([string]$Identity, [string]$User, [string[]]$AccessRights, [string]$InheritanceType, [bool]$AutoMapping)'
    'Set-MailboxAutoReplyConfiguration'                    = 'param([string]$Identity, [string]$AutoReplyState, [string]$InternalMessage, [string]$ExternalMessage, [string]$ExternalAudience)'
    'Remove-DistributionGroupMember'                       = 'param([string]$Identity, [string]$Member, [switch]$BypassSecurityGroupManagerCheck)'
}

foreach ($name in $stubs.Keys) {
    $body = "[CmdletBinding(SupportsShouldProcess = `$true)] $($stubs[$name]) throw 'Stub $name was called without a Pester mock.'"
    Set-Item -Path "Function:\global:$name" -Value ([scriptblock]::Create($body))
}
