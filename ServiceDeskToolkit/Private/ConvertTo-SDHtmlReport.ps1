function ConvertTo-SDHtmlReport {
    <#
    .SYNOPSIS
        Builds a self-contained HTML report (inline CSS, no external resources) from report rows.
    .DESCRIPTION
        Every value is HTML-encoded. Rows whose -HighlightProperty is $true get the CSS class "flag".
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$InputObject = @(),

        [Parameter(Mandatory = $true)]
        [string[]]$Property,

        [System.Collections.IDictionary]$Summary,

        [string]$Description = '',

        [string]$HighlightProperty,

        [datetime]$GeneratedAt = (Get-Date)
    )

    $encode = { param($Text) [System.Net.WebUtility]::HtmlEncode([string]$Text) }
    $rows = @($InputObject | Where-Object { $null -ne $_ })
    $version = '0.0.0'
    if ($MyInvocation.MyCommand.Module) { $version = [string]$MyInvocation.MyCommand.Module.Version }

    $sb = New-Object -TypeName System.Text.StringBuilder
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="en">')
    [void]$sb.AppendLine('<head>')
    [void]$sb.AppendLine('<meta charset="utf-8">')
    [void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
    [void]$sb.AppendLine(('<title>{0}</title>' -f (& $encode $Title)))
    [void]$sb.AppendLine(@'
<style>
:root { --bg:#ffffff; --fg:#1f2328; --muted:#59636e; --line:#d1d9e0; --head:#f6f8fa; --zebra:#fbfcfd; --flag:#fff4e5; --accent:#0969da; }
@media (prefers-color-scheme: dark) {
  :root { --bg:#0d1117; --fg:#e6edf3; --muted:#9198a1; --line:#30363d; --head:#161b22; --zebra:#11161d; --flag:#3a2a12; --accent:#4493f8; }
}
* { box-sizing: border-box; }
body { margin:0; padding:24px 16px; background:var(--bg); color:var(--fg); font:14px/1.45 "Segoe UI", system-ui, -apple-system, sans-serif; }
h1 { font-size:22px; margin:0 0 4px; }
p.meta { color:var(--muted); margin:0 0 16px; }
.cards { display:flex; flex-wrap:wrap; gap:12px; margin:0 0 20px; padding:0; }
.card { border:1px solid var(--line); border-radius:8px; padding:10px 14px; min-width:140px; }
.card dt { color:var(--muted); font-size:12px; }
.card dd { margin:2px 0 0; font-size:20px; font-weight:600; font-variant-numeric:tabular-nums; }
.wrap { overflow-x:auto; border:1px solid var(--line); border-radius:8px; }
table { border-collapse:collapse; width:100%; }
th, td { text-align:left; padding:6px 10px; border-bottom:1px solid var(--line); white-space:nowrap; }
th { position:sticky; top:0; background:var(--head); font-weight:600; }
tbody tr:nth-child(even) { background:var(--zebra); }
tr.flag td { background:var(--flag); }
.empty { padding:16px; color:var(--muted); }
footer { color:var(--muted); font-size:12px; margin-top:16px; }
</style>
'@)
    [void]$sb.AppendLine('</head>')
    [void]$sb.AppendLine('<body>')
    [void]$sb.AppendLine(('<h1>{0}</h1>' -f (& $encode $Title)))
    if ($Description) {
        [void]$sb.AppendLine(('<p class="meta">{0}</p>' -f (& $encode $Description)))
    }

    if ($Summary -and $Summary.Count -gt 0) {
        [void]$sb.AppendLine('<dl class="cards">')
        foreach ($key in $Summary.Keys) {
            [void]$sb.AppendLine(('<div class="card"><dt>{0}</dt><dd>{1}</dd></div>' -f (& $encode $key), (& $encode (Format-SDCellValue -Value $Summary[$key]))))
        }
        [void]$sb.AppendLine('</dl>')
    }

    [void]$sb.AppendLine('<div class="wrap">')
    if ($rows.Count -eq 0) {
        [void]$sb.AppendLine('<p class="empty">No entries found.</p>')
    }
    else {
        [void]$sb.AppendLine('<table>')
        [void]$sb.Append('<thead><tr>')
        foreach ($name in $Property) { [void]$sb.Append(('<th scope="col">{0}</th>' -f (& $encode $name))) }
        [void]$sb.AppendLine('</tr></thead>')
        [void]$sb.AppendLine('<tbody>')
        foreach ($row in $rows) {
            $flagged = $HighlightProperty -and ((Get-SDPropertyValue -InputObject $row -Name $HighlightProperty) -eq $true)
            if ($flagged) { [void]$sb.Append('<tr class="flag">') } else { [void]$sb.Append('<tr>') }
            foreach ($name in $Property) {
                $cell = Format-SDCellValue -Value (Get-SDPropertyValue -InputObject $row -Name $name)
                [void]$sb.Append(('<td>{0}</td>' -f (& $encode $cell)))
            }
            [void]$sb.AppendLine('</tr>')
        }
        [void]$sb.AppendLine('</tbody>')
        [void]$sb.AppendLine('</table>')
    }
    [void]$sb.AppendLine('</div>')
    [void]$sb.AppendLine(('<footer>Generated {0} by ServiceDeskToolkit {1}. {2} row(s).</footer>' -f (& $encode $GeneratedAt.ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture)), (& $encode $version), $rows.Count))
    [void]$sb.AppendLine('</body>')
    [void]$sb.AppendLine('</html>')
    $sb.ToString()
}
