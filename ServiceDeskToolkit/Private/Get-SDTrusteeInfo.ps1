function Get-SDTrusteeInfo {
    <#
    .SYNOPSIS
        Classifies a permission trustee: built-in system principal (ignored) or orphaned SID.
    .DESCRIPTION
        A trustee shown as a raw S-1-5-21-... SID usually belongs to a deleted account
        and is a typical clean-up finding in a permission audit.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Trustee
    )

    [pscustomobject]@{
        IsBuiltIn  = [bool]($Trustee -match '^(NT AUTHORITY\\|S-1-5-(10|18|19|20)$)')
        IsOrphaned = [bool]($Trustee -match '^S-1-5-21-')
    }
}
