function Get-SDPropertyValue {
    <#
    .SYNOPSIS
        Returns a property or dictionary value, or $null if it does not exist (safe under Set-StrictMode).
    .DESCRIPTION
        Graph SDK objects keep unmapped properties in the AdditionalProperties dictionary.
        This helper reads both kinds without throwing on missing names.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Collections.IDictionary]) {
        # Works for Hashtable and Dictionary[string,object] (Graph AdditionalProperties), case-insensitive.
        foreach ($key in $InputObject.Keys) {
            if ([string]$key -eq $Name) { return $InputObject[$key] }
        }
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}
