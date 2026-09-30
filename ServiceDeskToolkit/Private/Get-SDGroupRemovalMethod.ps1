function Get-SDGroupRemovalMethod {
    <#
    .SYNOPSIS
        Decides how a user can be removed from a group: via Graph, via Exchange Online, or not at all.
    .DESCRIPTION
        - Excluded groups (-ExcludeGroupId) are skipped.
        - Groups synced from on-premises AD must be changed in AD.
        - Dynamic groups are rule based; removing a member has no effect.
        - Microsoft 365 groups (Unified) and plain security groups are changed with Graph.
        - Distribution lists and mail-enabled security groups can only be changed in Exchange Online.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Group,

        [string[]]$ExcludeGroupId = @()
    )

    $groupTypes = @(Get-SDPropertyValue -InputObject $Group -Name 'GroupTypes')
    $result = {
        param($Method, $Reason)
        [pscustomobject]@{ Method = $Method; Reason = $Reason }
    }

    if ($ExcludeGroupId -contains $Group.Id) {
        return & $result 'Skip' 'excluded by -ExcludeGroupId'
    }
    if (Get-SDPropertyValue -InputObject $Group -Name 'OnPremisesSyncEnabled') {
        return & $result 'Skip' 'synced from on-premises AD - remove the membership in AD'
    }
    if ($groupTypes -contains 'DynamicMembership') {
        return & $result 'Skip' 'dynamic membership - adjust the rule or user attributes instead'
    }
    if ($groupTypes -contains 'Unified') {
        return & $result 'Graph' 'Microsoft 365 group'
    }
    if (Get-SDPropertyValue -InputObject $Group -Name 'MailEnabled') {
        return & $result 'Exchange' 'distribution list or mail-enabled security group'
    }
    & $result 'Graph' 'security group'
}
