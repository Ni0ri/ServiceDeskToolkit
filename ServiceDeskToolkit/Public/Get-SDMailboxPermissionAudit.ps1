function Get-SDMailboxPermissionAudit {
    <#
    .SYNOPSIS
        Audits Exchange Online mailbox permissions (FullAccess, SendAs, SendOnBehalf) and writes CSV and HTML.

    .DESCRIPTION
        Collects explicitly granted permissions for all mailboxes of the selected types, or for the
        mailboxes given with -Identity:

          - FullAccess    Get-EXOMailboxPermission (inherited entries and NT AUTHORITY\SELF are ignored)
          - SendAs        Get-EXORecipientPermission (NT AUTHORITY\SELF is ignored)
          - SendOnBehalf  GrantSendOnBehalfTo of the mailbox

        Trustees that only appear as a SID (S-1-5-21-...) usually belong to deleted accounts. They are
        marked as Orphaned and highlighted in the HTML report - a typical clean-up finding.

        If a single mailbox cannot be read, the error is logged and the audit continues.
        This function only reads data. It never changes permissions.

        Requirements:
          - Module: ExchangeOnlineManagement 3.x
          - Connect-ExchangeOnline with a role that can read recipients and permissions,
            e.g. View-Only Organization Management or Exchange Recipient Administrator.

    .PARAMETER Identity
        Mailbox(es) to audit (UPN, primary SMTP address or other Exchange identity).
        Accepts pipeline input. Without -Identity all mailboxes of -RecipientTypeDetails are audited.

    .PARAMETER RecipientTypeDetails
        Mailbox types to include when -Identity is not used.
        Default: UserMailbox, SharedMailbox, RoomMailbox, EquipmentMailbox.

    .PARAMETER PermissionType
        Permission types to collect. Default: FullAccess, SendAs, SendOnBehalf.

    .PARAMETER OutputDirectory
        Folder for the CSV and HTML files. Defaults to the current directory.
        File names: MailboxPermissionAudit_yyyy-MM-dd_HHmm.csv / .html

    .PARAMETER Delimiter
        CSV delimiter. Default ','. Use ';' for German Excel.

    .PARAMETER LogDirectory
        Folder for Log_yyyy-MM-dd.log. Defaults to %LOCALAPPDATA%\ServiceDeskToolkit\Logs.

    .EXAMPLE
        Connect-ExchangeOnline -UserPrincipalName admin@contoso.com
        Get-SDMailboxPermissionAudit -RecipientTypeDetails SharedMailbox -OutputDirectory C:\Reports -Verbose

        Audits all shared mailboxes and writes the report to C:\Reports.

    .EXAMPLE
        'info@contoso.com', 'buchhaltung@contoso.com' | Get-SDMailboxPermissionAudit -PermissionType FullAccess, SendAs

        Audits two mailboxes, FullAccess and SendAs only.

    .EXAMPLE
        Get-SDMailboxPermissionAudit -Delimiter ';' | Where-Object Orphaned

        Full audit with a CSV for German Excel; shows only permissions of deleted accounts.

    .INPUTS
        System.String. Mailbox identities, also by property name (Identity, PrimarySmtpAddress, UserPrincipalName).

    .OUTPUTS
        ServiceDeskToolkit.MailboxPermission

    .NOTES
        Author:  Artur Warkentin
        Version: 0.1.0
        Date:    2026-09-30
        Changelog:
          0.1.0 (2026-09-30) Initial version.

    .LINK
        https://learn.microsoft.com/powershell/module/exchange/get-exomailboxpermission
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('PrimarySmtpAddress', 'UserPrincipalName')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Identity,

        [ValidateSet('UserMailbox', 'SharedMailbox', 'RoomMailbox', 'EquipmentMailbox')]
        [string[]]$RecipientTypeDetails = @('UserMailbox', 'SharedMailbox', 'RoomMailbox', 'EquipmentMailbox'),

        [ValidateSet('FullAccess', 'SendAs', 'SendOnBehalf')]
        [string[]]$PermissionType = @('FullAccess', 'SendAs', 'SendOnBehalf'),

        [ValidateNotNullOrEmpty()]
        [string]$OutputDirectory = (Get-Location).Path,

        [char]$Delimiter = ',',

        [string]$LogDirectory = $script:SDLogDirectory
    )

    begin {
        $ErrorActionPreference = 'Stop'
        $PSDefaultParameterValues = @{ 'Write-SDLog:LogDirectory' = $LogDirectory }
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $requested = New-Object -TypeName 'System.Collections.Generic.List[string]'
        $mailboxProperties = 'DisplayName', 'UserPrincipalName', 'PrimarySmtpAddress', 'RecipientTypeDetails', 'GrantSendOnBehalfTo'

        try {
            Write-SDLog -Message 'Get-SDMailboxPermissionAudit started.'
            Assert-SDExchangeConnection
        }
        catch {
            Write-SDLog -Level ERROR -Message $_.Exception.Message
            throw
        }
    }

    process {
        foreach ($id in @($Identity | Where-Object { $_ })) { $requested.Add($id) }
    }

    end {
        try {
            $failedMailboxes = 0
            if ($requested.Count -gt 0) {
                $mailboxes = New-Object -TypeName 'System.Collections.Generic.List[object]'
                foreach ($id in $requested) {
                    try {
                        $mailboxes.Add((Get-EXOMailbox -Identity $id -Properties $mailboxProperties -ErrorAction Stop))
                    }
                    catch {
                        $failedMailboxes++
                        Write-SDLog -Level ERROR -Message ("Mailbox '{0}' not found: {1}" -f $id, $_.Exception.Message)
                    }
                }
                $mailboxes = $mailboxes.ToArray()
            }
            else {
                $mailboxes = @(Get-EXOMailbox -ResultSize Unlimited -RecipientTypeDetails $RecipientTypeDetails -Properties $mailboxProperties)
            }
            Write-SDLog -Message ('{0} mailbox(es) to audit; permission types: {1}.' -f $mailboxes.Count, ($PermissionType -join ', '))

            $rows = New-Object -TypeName 'System.Collections.Generic.List[object]'
            $index = 0
            foreach ($mailbox in $mailboxes) {
                $index++
                $address = [string]$mailbox.PrimarySmtpAddress
                Write-Progress -Activity 'Auditing mailbox permissions' -Status $address -PercentComplete ([int](100 * $index / [math]::Max($mailboxes.Count, 1)))

                $addRow = {
                    param($Permission, $Trustee, $AccessType)
                    $info = Get-SDTrusteeInfo -Trustee ([string]$Trustee)
                    if ($info.IsBuiltIn) { return }
                    $rows.Add([pscustomobject]@{
                            PSTypeName  = 'ServiceDeskToolkit.MailboxPermission'
                            Mailbox     = $address
                            DisplayName = [string]$mailbox.DisplayName
                            MailboxType = [string]$mailbox.RecipientTypeDetails
                            Permission  = $Permission
                            Trustee     = [string]$Trustee
                            AccessType  = $AccessType
                            Orphaned    = $info.IsOrphaned
                        })
                }

                try {
                    if ($PermissionType -contains 'FullAccess') {
                        foreach ($entry in @(Get-EXOMailboxPermission -Identity $address)) {
                            if ($entry.IsInherited) { continue }
                            if ((@($entry.AccessRights) -join ',') -notmatch 'FullAccess') { continue }
                            $accessType = if ($entry.Deny) { 'Deny' } else { 'Allow' }
                            & $addRow 'FullAccess' $entry.User $accessType
                        }
                    }
                    if ($PermissionType -contains 'SendAs') {
                        foreach ($entry in @(Get-EXORecipientPermission -Identity $address -AccessRights SendAs)) {
                            if ($entry.IsInherited) { continue }
                            & $addRow 'SendAs' $entry.Trustee ([string]$entry.AccessControlType)
                        }
                    }
                    if ($PermissionType -contains 'SendOnBehalf') {
                        foreach ($trustee in @(Get-SDPropertyValue -InputObject $mailbox -Name 'GrantSendOnBehalfTo')) {
                            if ($trustee) { & $addRow 'SendOnBehalf' $trustee 'Allow' }
                        }
                    }
                }
                catch {
                    $failedMailboxes++
                    Write-SDLog -Level ERROR -Message ('Permissions of {0} could not be read: {1}' -f $address, $_.Exception.Message)
                }
            }
            Write-Progress -Activity 'Auditing mailbox permissions' -Completed

            $sorted = @($rows | Sort-Object -Property Mailbox, Permission, Trustee)
            $summary = [ordered]@{
                'Mailboxes'   = $mailboxes.Count
                'Permissions' = $sorted.Count
            }
            foreach ($type in $PermissionType) { $summary[$type] = @($sorted | Where-Object Permission -EQ $type).Count }
            $summary['Orphaned'] = @($sorted | Where-Object Orphaned).Count
            if ($failedMailboxes -gt 0) { $summary['Failed mailboxes'] = $failedMailboxes }

            $columns = 'Mailbox', 'DisplayName', 'MailboxType', 'Permission', 'Trustee', 'AccessType', 'Orphaned'
            $files = Export-SDReport -InputObject $sorted -Property $columns -OutputDirectory $OutputDirectory -BaseName 'MailboxPermissionAudit' `
                -Title 'Exchange Online - mailbox permissions' -Summary $summary -HighlightProperty 'Orphaned' -Delimiter $Delimiter `
                -Description 'Explicit FullAccess, SendAs and SendOnBehalf permissions. Inherited and built-in system entries are excluded. Orphaned = trustee is an unresolved SID (deleted account).'

            Write-SDLog -Message ('CSV report: {0}' -f $files.CsvPath)
            Write-SDLog -Message ('HTML report: {0}' -f $files.HtmlPath)
            if ($failedMailboxes -gt 0) {
                Write-SDLog -Level WARN -Message ('{0} mailbox(es) could not be audited - see log.' -f $failedMailboxes)
            }

            $sorted | ForEach-Object { $_ }
        }
        catch {
            Write-SDLog -Level ERROR -Message ('Get-SDMailboxPermissionAudit failed: {0}' -f $_.Exception.Message)
            throw
        }
        finally {
            $stopwatch.Stop()
            Write-SDLog -Message ('Get-SDMailboxPermissionAudit finished: {0:N1} s.' -f $stopwatch.Elapsed.TotalSeconds)
        }
    }
}
