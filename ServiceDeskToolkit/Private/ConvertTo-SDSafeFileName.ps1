function ConvertTo-SDSafeFileName {
    <#
    .SYNOPSIS
        Replaces characters that are invalid in file names (on any platform) with '_'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $invalid = [IO.Path]::GetInvalidFileNameChars() + [char[]]'<>:"/\|?*'
    $builder = New-Object -TypeName System.Text.StringBuilder
    foreach ($char in $Name.ToCharArray()) {
        if ($invalid -contains $char) { [void]$builder.Append('_') } else { [void]$builder.Append($char) }
    }
    $builder.ToString()
}
