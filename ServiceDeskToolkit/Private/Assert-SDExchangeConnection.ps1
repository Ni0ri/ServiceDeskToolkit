function Assert-SDExchangeConnection {
    <#
    .SYNOPSIS
        Throws if there is no active Exchange Online connection (ExchangeOnlineManagement v3+).
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-Command -Name 'Get-ConnectionInformation' -ErrorAction SilentlyContinue)) {
        throw 'ExchangeOnlineManagement v3 or later not found. Install it with: Install-Module ExchangeOnlineManagement -Scope CurrentUser'
    }

    $connected = @(Get-ConnectionInformation | Where-Object { (Get-SDPropertyValue -InputObject $_ -Name 'State') -eq 'Connected' })
    if ($connected.Count -eq 0) {
        throw 'Not connected to Exchange Online. Connect first, for example: Connect-ExchangeOnline -UserPrincipalName admin@contoso.com'
    }

    Write-SDLog -Message ('Exchange Online connection OK (organization: {0}).' -f (Get-SDPropertyValue -InputObject $connected[0] -Name 'TenantID'))
}
