function Assert-SDGraphConnection {
    <#
    .SYNOPSIS
        Throws if there is no Microsoft Graph connection; warns if expected scopes are missing.
    .DESCRIPTION
        Scope names are only compared literally. A broader permission (for example
        Directory.ReadWrite.All instead of User.ReadWrite.All) also works, so missing scopes
        produce a warning, not an error.
    #>
    [CmdletBinding()]
    param(
        [string[]]$RequiredScope = @()
    )

    if (-not (Get-Command -Name 'Get-MgContext' -ErrorAction SilentlyContinue)) {
        throw 'Microsoft Graph PowerShell SDK not found. Install it with: Install-Module Microsoft.Graph -Scope CurrentUser'
    }

    $context = Get-MgContext
    if (-not $context) {
        throw ('Not connected to Microsoft Graph. Connect first, for example: Connect-MgGraph -Scopes {0}' -f ($RequiredScope -join ','))
    }

    $granted = @(Get-SDPropertyValue -InputObject $context -Name 'Scopes')
    $missing = @($RequiredScope | Where-Object { $granted -notcontains $_ })
    if ($missing.Count -gt 0) {
        Write-SDLog -Level WARN -Message ('Graph context does not list the scope(s) {0}. Calls may fail unless a broader permission is granted.' -f ($missing -join ', '))
    }

    Write-SDLog -Message ('Graph connection OK (account/app: {0}, tenant: {1}).' -f (Get-SDPropertyValue -InputObject $context -Name 'Account'), (Get-SDPropertyValue -InputObject $context -Name 'TenantId'))
}
