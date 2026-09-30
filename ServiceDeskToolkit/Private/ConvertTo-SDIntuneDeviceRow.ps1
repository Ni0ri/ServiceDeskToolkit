function ConvertTo-SDIntuneDeviceRow {
    <#
    .SYNOPSIS
        Converts a Graph managedDevice object into a flat report row.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Device,

        [datetime]$Now = [datetime]::UtcNow,

        [int]$StaleAfterDays = 30,

        [AllowEmptyString()]
        [string]$NoncompliantPolicies = ''
    )

    $lastSync = Get-SDPropertyValue -InputObject $Device -Name 'LastSyncDateTime'
    $daysSinceSync = $null
    if ($lastSync -and ([datetime]$lastSync) -gt [datetime]'1901-01-01') {
        $lastSync = ([datetime]$lastSync).ToUniversalTime()
        $daysSinceSync = [int][math]::Floor(($Now - $lastSync).TotalDays)
    }
    else {
        $lastSync = $null
    }

    [pscustomobject]@{
        PSTypeName           = 'ServiceDeskToolkit.IntuneNoncompliantDevice'
        DeviceName           = Get-SDPropertyValue -InputObject $Device -Name 'DeviceName'
        UserPrincipalName    = Get-SDPropertyValue -InputObject $Device -Name 'UserPrincipalName'
        UserDisplayName      = Get-SDPropertyValue -InputObject $Device -Name 'UserDisplayName'
        OperatingSystem      = Get-SDPropertyValue -InputObject $Device -Name 'OperatingSystem'
        OSVersion            = Get-SDPropertyValue -InputObject $Device -Name 'OSVersion'
        ComplianceState      = [string](Get-SDPropertyValue -InputObject $Device -Name 'ComplianceState')
        LastSyncDateTime     = $lastSync
        DaysSinceLastSync    = $daysSinceSync
        Stale                = [bool]($null -eq $daysSinceSync -or $daysSinceSync -ge $StaleAfterDays)
        GracePeriodExpires   = Get-SDPropertyValue -InputObject $Device -Name 'ComplianceGracePeriodExpirationDateTime'
        NoncompliantPolicies = $NoncompliantPolicies
        Ownership            = [string](Get-SDPropertyValue -InputObject $Device -Name 'ManagedDeviceOwnerType')
        ManagementAgent      = [string](Get-SDPropertyValue -InputObject $Device -Name 'ManagementAgent')
        Manufacturer         = Get-SDPropertyValue -InputObject $Device -Name 'Manufacturer'
        Model                = Get-SDPropertyValue -InputObject $Device -Name 'Model'
        SerialNumber         = Get-SDPropertyValue -InputObject $Device -Name 'SerialNumber'
        EnrolledDateTime     = Get-SDPropertyValue -InputObject $Device -Name 'EnrolledDateTime'
        IntuneDeviceId       = Get-SDPropertyValue -InputObject $Device -Name 'Id'
        EntraDeviceId        = Get-SDPropertyValue -InputObject $Device -Name 'AzureAdDeviceId'
    }
}
