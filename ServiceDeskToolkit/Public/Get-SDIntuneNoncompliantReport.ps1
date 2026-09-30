function Get-SDIntuneNoncompliantReport {
    <#
    .SYNOPSIS
        Creates a CSV and HTML report of Intune managed devices that are not compliant.

    .DESCRIPTION
        Reads managed devices with complianceState 'noncompliant' (optionally also 'inGracePeriod')
        from Microsoft Graph, adds the days since the last check-in and marks stale devices, and
        writes the result as CSV (UTF-8 with BOM for Excel) and as a self-contained HTML page.
        The report rows are also returned to the pipeline.

        With -IncludePolicyDetails the names of the failing compliance policies are added per device.
        This needs one extra Graph call per device, so it takes longer in large tenants.

        This function only reads data. It never changes devices or policies.

        Requirements:
          - Modules: Microsoft.Graph.Authentication, Microsoft.Graph.DeviceManagement
          - Connect-MgGraph -Scopes DeviceManagementManagedDevices.Read.All
            (plus DeviceManagementConfiguration.Read.All for -IncludePolicyDetails)
          - Intune license in the tenant and an Intune role with read access (e.g. Read Only Operator).

    .PARAMETER OutputDirectory
        Folder for the CSV and HTML files. Defaults to the current directory.
        File names: IntuneNoncompliant_yyyy-MM-dd_HHmm.csv / .html

    .PARAMETER OperatingSystem
        Only include these platforms (Windows, iOS, iPadOS, Android, macOS, Linux).

    .PARAMETER IncludeInGracePeriod
        Also include devices in the grace period (complianceState 'inGracePeriod').

    .PARAMETER IncludePolicyDetails
        Adds the names of the non-compliant policies per device (one extra Graph call per device).

    .PARAMETER StaleAfterDays
        Devices without a check-in for this many days are marked as Stale (highlighted in HTML). Default 30.

    .PARAMETER Delimiter
        CSV delimiter. Default ','. Use ';' for German Excel.

    .PARAMETER LogDirectory
        Folder for Log_yyyy-MM-dd.log. Defaults to %LOCALAPPDATA%\ServiceDeskToolkit\Logs.

    .EXAMPLE
        Connect-MgGraph -Scopes DeviceManagementManagedDevices.Read.All
        Get-SDIntuneNoncompliantReport -OutputDirectory C:\Reports -Verbose

        Writes the report to C:\Reports and shows the file paths in the verbose output.

    .EXAMPLE
        Get-SDIntuneNoncompliantReport -OperatingSystem Windows -IncludePolicyDetails -Delimiter ';' |
            Where-Object Stale | Select-Object DeviceName, UserPrincipalName, DaysSinceLastSync

        Windows devices only, with policy names, CSV for German Excel; lists stale devices on screen.

    .EXAMPLE
        Get-SDIntuneNoncompliantReport -IncludeInGracePeriod -StaleAfterDays 14 |
            Group-Object OperatingSystem | Sort-Object Count -Descending

        Counts non-compliant and grace-period devices per platform.

    .INPUTS
        None.

    .OUTPUTS
        ServiceDeskToolkit.IntuneNoncompliantDevice

    .NOTES
        Author:  Artur Warkentin
        Version: 0.1.0
        Date:    2026-09-30
        Changelog:
          0.1.0 (2026-09-30) Initial version.

    .LINK
        https://learn.microsoft.com/graph/api/intune-devices-manageddevice-list
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$OutputDirectory = (Get-Location).Path,

        [ValidateSet('Windows', 'iOS', 'iPadOS', 'Android', 'macOS', 'Linux')]
        [string[]]$OperatingSystem,

        [switch]$IncludeInGracePeriod,

        [switch]$IncludePolicyDetails,

        [ValidateRange(1, 3650)]
        [int]$StaleAfterDays = 30,

        [char]$Delimiter = ',',

        [string]$LogDirectory = $script:SDLogDirectory
    )

    $ErrorActionPreference = 'Stop'
    $PSDefaultParameterValues = @{ 'Write-SDLog:LogDirectory' = $LogDirectory }
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        Write-SDLog -Message 'Get-SDIntuneNoncompliantReport started.'
        $scopes = @('DeviceManagementManagedDevices.Read.All')
        if ($IncludePolicyDetails) { $scopes += 'DeviceManagementConfiguration.Read.All' }
        Assert-SDGraphConnection -RequiredScope $scopes

        $filter = "complianceState eq 'noncompliant'"
        if ($IncludeInGracePeriod) { $filter = "($filter) or complianceState eq 'inGracePeriod'" }

        $properties = 'id', 'deviceName', 'userPrincipalName', 'userDisplayName', 'operatingSystem', 'osVersion',
        'complianceState', 'lastSyncDateTime', 'enrolledDateTime', 'complianceGracePeriodExpirationDateTime',
        'managedDeviceOwnerType', 'managementAgent', 'manufacturer', 'model', 'serialNumber', 'azureADDeviceId'

        $devices = @(Get-MgDeviceManagementManagedDevice -Filter $filter -Property $properties -All)
        Write-SDLog -Message ('{0} device(s) returned by Graph (filter: {1}).' -f $devices.Count, $filter)

        if ($OperatingSystem) {
            $devices = @($devices | Where-Object { $OperatingSystem -contains [string](Get-SDPropertyValue -InputObject $_ -Name 'OperatingSystem') })
            Write-SDLog -Message ('{0} device(s) after platform filter ({1}).' -f $devices.Count, ($OperatingSystem -join ', '))
        }

        $now = [datetime]::UtcNow
        $policyErrors = 0
        $rows = New-Object -TypeName 'System.Collections.Generic.List[object]'
        $index = 0
        foreach ($device in $devices) {
            $index++
            $policies = ''
            if ($IncludePolicyDetails) {
                Write-Progress -Activity 'Reading compliance policy states' -Status $device.DeviceName -PercentComplete ([int](100 * $index / $devices.Count))
                try {
                    $states = @(Get-MgDeviceManagementManagedDeviceCompliancePolicyState -ManagedDeviceId $device.Id -All)
                    $policies = (@($states | Where-Object { @('nonCompliant', 'error', 'conflict') -contains [string]$_.State } |
                                ForEach-Object { '{0} ({1})' -f $_.DisplayName, $_.State }) -join '; ')
                }
                catch {
                    $policyErrors++
                    $policies = 'n/a'
                    Write-SDLog -Level WARN -Message ('Policy states for {0} could not be read: {1}' -f $device.DeviceName, $_.Exception.Message)
                }
            }
            $rows.Add((ConvertTo-SDIntuneDeviceRow -Device $device -Now $now -StaleAfterDays $StaleAfterDays -NoncompliantPolicies $policies))
        }
        if ($IncludePolicyDetails) { Write-Progress -Activity 'Reading compliance policy states' -Completed }

        $sorted = @($rows | Sort-Object -Property @{ Expression = 'Stale'; Descending = $true }, OperatingSystem, DeviceName)

        $summary = [ordered]@{ 'Devices' = $sorted.Count; ('Stale (>= {0} days)' -f $StaleAfterDays) = @($sorted | Where-Object Stale).Count }
        foreach ($group in ($sorted | Group-Object -Property OperatingSystem | Sort-Object -Property Count -Descending)) {
            $label = if ($group.Name) { $group.Name } else { 'Unknown' }
            $summary[$label] = $group.Count
        }

        $columns = 'DeviceName', 'UserPrincipalName', 'UserDisplayName', 'OperatingSystem', 'OSVersion', 'ComplianceState',
        'LastSyncDateTime', 'DaysSinceLastSync', 'Stale', 'GracePeriodExpires', 'NoncompliantPolicies', 'Ownership',
        'ManagementAgent', 'Manufacturer', 'Model', 'SerialNumber', 'EnrolledDateTime', 'IntuneDeviceId', 'EntraDeviceId'
        if (-not $IncludePolicyDetails) { $columns = @($columns | Where-Object { $_ -ne 'NoncompliantPolicies' }) }

        $files = Export-SDReport -InputObject $sorted -Property $columns -OutputDirectory $OutputDirectory -BaseName 'IntuneNoncompliant' `
            -Title 'Intune - non-compliant devices' -Summary $summary -HighlightProperty 'Stale' -Delimiter $Delimiter `
            -Description ('Compliance filter: {0}. Stale = no check-in for {1} days or more. Times in UTC.' -f $filter, $StaleAfterDays)

        Write-SDLog -Message ('CSV report: {0}' -f $files.CsvPath)
        Write-SDLog -Message ('HTML report: {0}' -f $files.HtmlPath)
        if ($policyErrors -gt 0) {
            Write-SDLog -Level WARN -Message ('Policy details missing for {0} device(s).' -f $policyErrors)
        }

        $sorted | ForEach-Object { $_ }
    }
    catch {
        Write-SDLog -Level ERROR -Message ('Get-SDIntuneNoncompliantReport failed: {0}' -f $_.Exception.Message)
        throw
    }
    finally {
        $stopwatch.Stop()
        Write-SDLog -Message ('Get-SDIntuneNoncompliantReport finished in {0:N1} s.' -f $stopwatch.Elapsed.TotalSeconds)
    }
}
