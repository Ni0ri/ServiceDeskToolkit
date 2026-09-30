function Export-SDReport {
    <#
    .SYNOPSIS
        Writes report rows as CSV (UTF-8 with BOM, opens cleanly in Excel) and as HTML.
    .DESCRIPTION
        File names get a timestamp suffix, e.g. IntuneNoncompliant_2026-09-30_1415.csv.
        Returns an object with CsvPath and HtmlPath.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$InputObject = @(),

        [Parameter(Mandatory = $true)]
        [string[]]$Property,

        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory,

        [Parameter(Mandatory = $true)]
        [string]$BaseName,

        [Parameter(Mandatory = $true)]
        [string]$Title,

        [System.Collections.IDictionary]$Summary,

        [string]$Description = '',

        [string]$HighlightProperty,

        [char]$Delimiter = ',',

        [datetime]$Timestamp = (Get-Date)
    )

    $rows = @($InputObject | Where-Object { $null -ne $_ })

    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        $null = New-Item -Path $OutputDirectory -ItemType Directory -Force -WhatIf:$false -Confirm:$false
    }

    $stamp = $Timestamp.ToString('yyyy-MM-dd_HHmm', [Globalization.CultureInfo]::InvariantCulture)
    $csvPath = Join-Path -Path $OutputDirectory -ChildPath ('{0}_{1}.csv' -f $BaseName, $stamp)
    $htmlPath = Join-Path -Path $OutputDirectory -ChildPath ('{0}_{1}.html' -f $BaseName, $stamp)

    # Windows PowerShell 'UTF8' already writes a BOM; PowerShell 7 needs 'utf8BOM' for Excel.
    $csvEncoding = 'UTF8'
    if ($PSVersionTable.PSVersion.Major -ge 6) { $csvEncoding = 'utf8BOM' }

    if ($rows.Count -gt 0) {
        $rows | ForEach-Object {
            $row = $_
            $flat = [ordered]@{}
            foreach ($name in $Property) { $flat[$name] = Format-SDCellValue -Value (Get-SDPropertyValue -InputObject $row -Name $name) }
            [pscustomobject]$flat
        } | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Delimiter $Delimiter -Encoding $csvEncoding -WhatIf:$false -Confirm:$false
    }
    else {
        $header = ($Property | ForEach-Object { '"{0}"' -f $_ }) -join $Delimiter
        Set-Content -LiteralPath $csvPath -Value $header -Encoding $csvEncoding -WhatIf:$false -Confirm:$false
    }

    $html = ConvertTo-SDHtmlReport -Title $Title -InputObject $rows -Property $Property -Summary $Summary -Description $Description -HighlightProperty $HighlightProperty -GeneratedAt $Timestamp
    Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8 -WhatIf:$false -Confirm:$false

    [pscustomobject]@{
        CsvPath  = $csvPath
        HtmlPath = $htmlPath
    }
}
