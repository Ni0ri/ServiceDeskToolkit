function Get-SDLicenseAssignment {
    <#
    .SYNOPSIS
        Splits a user's licenses into directly assigned and group-assigned SKU IDs.
    .DESCRIPTION
        Only direct assignments can be removed with Set-MgUserLicense. Group-based licenses
        disappear when the user leaves the licensing group.
        If licenseAssignmentStates is empty, all assignedLicenses are treated as direct.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()][object[]]$LicenseAssignmentStates,
        [AllowNull()][object[]]$AssignedLicenses
    )

    $states = @($LicenseAssignmentStates | Where-Object { $null -ne $_ })
    if ($states.Count -gt 0) {
        $direct = @($states | Where-Object { -not (Get-SDPropertyValue -InputObject $_ -Name 'AssignedByGroup') } |
                ForEach-Object { [string]$_.SkuId } | Select-Object -Unique)
        $inherited = @($states | Where-Object { Get-SDPropertyValue -InputObject $_ -Name 'AssignedByGroup' } |
                ForEach-Object { [string]$_.SkuId } | Where-Object { $direct -notcontains $_ } | Select-Object -Unique)
    }
    else {
        $direct = @($AssignedLicenses | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.SkuId } | Select-Object -Unique)
        $inherited = @()
    }

    [pscustomobject]@{
        Direct    = $direct
        Inherited = $inherited
    }
}
