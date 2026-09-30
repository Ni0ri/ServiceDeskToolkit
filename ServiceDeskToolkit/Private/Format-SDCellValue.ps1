function Format-SDCellValue {
    <#
    .SYNOPSIS
        Formats a value for CSV/HTML output: ISO dates, joined lists, empty string for $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) { return $Value.ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture) }
    if ($Value -is [datetimeoffset]) { return $Value.UtcDateTime.ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture) }
    if ($Value -is [string]) { return $Value }
    if ($Value -is [System.Collections.IEnumerable]) {
        return (@($Value) | ForEach-Object { Format-SDCellValue -Value $_ }) -join '; '
    }
    [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $Value)
}
