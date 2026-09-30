function Test-SDToolkit {
    <#
    .SYNOPSIS
        Self-test of the ServiceDeskToolkit core logic with fixed sample data (no tenant needed).

    .DESCRIPTION
        Runs the decision logic of the module against built-in examples: group removal rules,
        direct vs. group-based licenses, orphaned trustees, device staleness, HTML encoding and
        file name sanitizing. No Microsoft Graph or Exchange Online connection is used.

        Returns one summary object (Summary "n/n Tests gruen" with a real umlaut, Passed, Total) with the
        single results in the Results property.
        Use it after installing or changing the module; the full Pester suite lives in the repository.

    .PARAMETER PassThru
        Returns the individual test results instead of the summary object.

    .EXAMPLE
        (Test-SDToolkit).Summary

        Prints the result line, for example "13/13 Tests gruen" (with umlaut) when everything passes.

    .EXAMPLE
        Test-SDToolkit -PassThru | Where-Object { -not $_.Passed }

        Lists failed checks only.

    .INPUTS
        None.

    .OUTPUTS
        ServiceDeskToolkit.SelfTestSummary, or ServiceDeskToolkit.SelfTestResult with -PassThru.

    .NOTES
        Author:  Artur Warkentin
        Version: 0.1.0
        Date:    2026-09-30
        Changelog:
          0.1.0 (2026-09-30) Initial version.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [switch]$PassThru
    )

    $now = [datetime]'2026-09-30T12:00:00Z'
    $now = $now.ToUniversalTime()
    $group = { param($Types, $Mail, $Synced, $Id = 'g1') [pscustomobject]@{ Id = $Id; GroupTypes = $Types; MailEnabled = $Mail; OnPremisesSyncEnabled = $Synced } }

    $cases = @(
        @{ Name = 'Security group is removed via Graph'; Test = { (Get-SDGroupRemovalMethod -Group (& $group @() $false $false)).Method -eq 'Graph' } }
        @{ Name = 'Microsoft 365 group is removed via Graph'; Test = { (Get-SDGroupRemovalMethod -Group (& $group @('Unified') $true $false)).Method -eq 'Graph' } }
        @{ Name = 'Distribution list is removed via Exchange'; Test = { (Get-SDGroupRemovalMethod -Group (& $group @() $true $false)).Method -eq 'Exchange' } }
        @{ Name = 'Dynamic group is skipped'; Test = { (Get-SDGroupRemovalMethod -Group (& $group @('DynamicMembership') $false $false)).Method -eq 'Skip' } }
        @{ Name = 'On-premises synced group is skipped'; Test = { (Get-SDGroupRemovalMethod -Group (& $group @() $false $true)).Method -eq 'Skip' } }
        @{ Name = 'Excluded group is skipped'; Test = { (Get-SDGroupRemovalMethod -Group (& $group @() $false $false 'keep') -ExcludeGroupId 'keep').Method -eq 'Skip' } }
        @{ Name = 'Only direct licenses are removable'; Test = {
                $l = Get-SDLicenseAssignment -LicenseAssignmentStates @(
                    [pscustomobject]@{ SkuId = 'a'; AssignedByGroup = $null },
                    [pscustomobject]@{ SkuId = 'b'; AssignedByGroup = 'grp' })
                ((@($l.Direct) -join ',') -eq 'a') -and ((@($l.Inherited) -join ',') -eq 'b')
            }
        }
        @{ Name = 'Orphaned SID trustee is detected'; Test = { (Get-SDTrusteeInfo -Trustee 'S-1-5-21-111-222-333-1001').IsOrphaned } }
        @{ Name = 'NT AUTHORITY\SELF is ignored'; Test = { (Get-SDTrusteeInfo -Trustee 'NT AUTHORITY\SELF').IsBuiltIn } }
        @{ Name = 'Device without check-in for 45 days is stale'; Test = {
                $row = ConvertTo-SDIntuneDeviceRow -Device ([pscustomobject]@{ DeviceName = 'PC1'; LastSyncDateTime = $now.AddDays(-45) }) -Now $now -StaleAfterDays 30
                $row.Stale -and $row.DaysSinceLastSync -eq 45
            }
        }
        @{ Name = 'HTML report encodes values'; Test = {
                $html = ConvertTo-SDHtmlReport -Title 'T' -InputObject @([pscustomobject]@{ Name = '<script>x</script>' }) -Property 'Name'
                ($html -match '&lt;script&gt;') -and ($html -notmatch '<script>')
            }
        }
        @{ Name = 'File names are sanitized'; Test = { (ConvertTo-SDSafeFileName -Name 'a/b:c*d') -eq 'a_b_c_d' } }
        @{ Name = 'Graph AdditionalProperties dictionary is readable'; Test = {
                $dictionary = New-Object -TypeName 'System.Collections.Generic.Dictionary[string,object]'
                $dictionary['displayName'] = 'SG-Test'
                ((Get-SDPropertyValue -InputObject $dictionary -Name 'displayName') -eq 'SG-Test') -and ($null -eq (Get-SDPropertyValue -InputObject $dictionary -Name 'mail'))
            }
        }
    )

    $results = foreach ($case in $cases) {
        $passed = $false
        $message = ''
        try { $passed = [bool](& $case.Test) } catch { $message = $_.Exception.Message }
        [pscustomobject]@{
            PSTypeName = 'ServiceDeskToolkit.SelfTestResult'
            Name       = $case.Name
            Passed     = $passed
            Message    = $message
        }
    }

    if ($PassThru) { return $results }

    $passedCount = @($results | Where-Object Passed).Count
    [pscustomobject]@{
        PSTypeName = 'ServiceDeskToolkit.SelfTestSummary'
        Summary    = "{0}/{1} Tests gr$([char]0x00FC)n" -f $passedCount, @($results).Count
        Passed     = $passedCount
        Total      = @($results).Count
        Results    = @($results)
    }
}
