function Invoke-SDOffboarding {
    <#
    .SYNOPSIS
        Offboards a Microsoft Entra ID user: disable, revoke sessions, convert mailbox, remove groups and licenses.

    .DESCRIPTION
        Runs the usual offboarding steps for one or more users in a fixed, safe order:

          1. Backup      Writes a JSON snapshot (groups, licenses, mailbox) BEFORE any change,
                         so memberships can be restored. Written even with -WhatIf.
          2. Disable     Sets accountEnabled = false (skipped for users synced from on-premises AD).
          3. Sessions    Revokes all refresh tokens / sign-in sessions.
          4. Mailbox     Converts the user mailbox to a shared mailbox.
          5. Access      Optional: grants FullAccess to the given users (-GrantFullAccessTo).
          6. Forwarding  Optional: forwards mail (-ForwardTo), keeping a copy in the mailbox.
          7. Auto reply  Optional: sets an out-of-office message (-AutoReplyMessage).
          8. Groups      Removes the user from security groups and Microsoft 365 groups (Graph) and from
                         distribution lists / mail-enabled security groups (Exchange Online).
                         Dynamic groups, on-premises synced groups and -ExcludeGroupId are skipped.
                         Directory role assignments are only reported, never removed.
          9. Licenses    Removes directly assigned licenses. Group-based licenses go away with the group.

        Every change is guarded by ShouldProcess, so -WhatIf shows the full plan without changing anything.
        Because ConfirmImpact is High, PowerShell asks for confirmation unless -Confirm:$false is given.

        Error handling: if the account cannot be found, disabled or its sessions revoked, the function
        stops (throws). Later steps are independent: a failure is logged, recorded as 'Failed' in the
        result and the remaining steps still run. Check the Succeeded property of the result.

        Requirements:
          - Modules: Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Users.Actions,
            Microsoft.Graph.Groups; ExchangeOnlineManagement 3.x (unless -SkipMailbox).
          - Connect-MgGraph -Scopes User.ReadWrite.All, GroupMember.ReadWrite.All
            (least privilege alternatives: see README).
          - Connect-ExchangeOnline with the Exchange Recipient Administrator role or higher.
          - Disabling an administrator account needs the Privileged Authentication Administrator role.

    .PARAMETER UserPrincipalName
        UPN (or object ID) of the user(s) to offboard. Accepts pipeline input, e.g. from Get-MgUser.

    .PARAMETER ForwardTo
        Optional e-mail address to forward incoming mail to. Internal recipients are set as
        ForwardingAddress, external addresses as ForwardingSmtpAddress (outbound spam policy must allow it).

    .PARAMETER AutoReplyMessage
        Optional automatic reply (text or HTML) for internal senders. Also used for external senders
        unless -ExternalAutoReplyMessage is given.

    .PARAMETER ExternalAutoReplyMessage
        Optional separate automatic reply for external senders.

    .PARAMETER GrantFullAccessTo
        Optional user(s) who get FullAccess (with AutoMapping) to the converted shared mailbox,
        typically the manager or the successor.

    .PARAMETER ExcludeGroupId
        Object IDs of groups the user should stay in (for example an "Alumni" or legal hold group).

    .PARAMETER SkipMailbox
        Skips all Exchange Online steps (mailbox conversion, forwarding, auto reply, distribution lists).
        No Exchange Online connection is needed then.

    .PARAMETER SkipGroupRemoval
        Keeps all group memberships.

    .PARAMETER SkipLicenseRemoval
        Keeps all licenses (for example when the mailbox has a litigation hold or an archive).

    .PARAMETER BackupDirectory
        Folder for the JSON snapshot. Defaults to the log directory.

    .PARAMETER LogDirectory
        Folder for Log_yyyy-MM-dd.log. Defaults to %LOCALAPPDATA%\ServiceDeskToolkit\Logs
        (or $env:SDTOOLKIT_LOG_DIR).

    .EXAMPLE
        Invoke-SDOffboarding -UserPrincipalName max.muster@contoso.com -WhatIf

        Shows every planned change for the user without changing anything. The JSON snapshot
        and the log are written anyway. Always start with this.

    .EXAMPLE
        Invoke-SDOffboarding -UserPrincipalName max.muster@contoso.com -GrantFullAccessTo erika.chef@contoso.com -AutoReplyMessage 'Max Muster no longer works for Contoso. Please contact info@contoso.com.' -Confirm:$false

        Full offboarding without prompts. The manager gets access to the shared mailbox and senders
        receive an automatic reply.

    .EXAMPLE
        Import-Csv .\leavers.csv | Invoke-SDOffboarding -ForwardTo helpdesk@contoso.com -ExcludeGroupId 'a1b2c3d4-0000-0000-0000-000000000000' -Confirm:$false |
            Where-Object { -not $_.Succeeded }

        Offboards every user in the CSV (column UserPrincipalName) and lists only users with failed steps.

    .EXAMPLE
        $result = Invoke-SDOffboarding -UserPrincipalName max.muster@contoso.com -SkipMailbox -Confirm:$false
        $result.Steps | Format-Table Step, Target, Status, Detail -AutoSize

        Entra ID steps only (e.g. user without mailbox) and a table of all step results.

    .INPUTS
        System.String. UserPrincipalName, also by property name.

    .OUTPUTS
        ServiceDeskToolkit.OffboardingResult with UserPrincipalName, UserId, DisplayName, Succeeded,
        BackupPath and Steps (Step, Target, Status = Done|WhatIf|Skipped|NoChange|Failed, Detail).

    .NOTES
        Author:  Artur Warkentin
        Version: 1.0.0
        Date:    2026-10-01
        Changelog:
          1.0.0 (2026-10-01) First PowerShell Gallery release, no functional changes.
          0.1.0 (2026-09-30) Initial version.

    .LINK
        https://learn.microsoft.com/graph/api/user-revokesigninsessions
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('UPN')]
        [ValidateNotNullOrEmpty()]
        [string[]]$UserPrincipalName,

        [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
        [string]$ForwardTo,

        [ValidateNotNullOrEmpty()]
        [string]$AutoReplyMessage,

        [ValidateNotNullOrEmpty()]
        [string]$ExternalAutoReplyMessage,

        [ValidateNotNullOrEmpty()]
        [string[]]$GrantFullAccessTo,

        [string[]]$ExcludeGroupId = @(),

        [switch]$SkipMailbox,

        [switch]$SkipGroupRemoval,

        [switch]$SkipLicenseRemoval,

        [string]$BackupDirectory,

        [string]$LogDirectory = $script:SDLogDirectory
    )

    begin {
        $ErrorActionPreference = 'Stop'
        $PSDefaultParameterValues = @{ 'Write-SDLog:LogDirectory' = $LogDirectory }
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $userCount = 0
        $failedStepCount = 0

        if ($SkipMailbox -and ($ForwardTo -or $AutoReplyMessage -or $ExternalAutoReplyMessage -or $GrantFullAccessTo)) {
            throw '-ForwardTo, -AutoReplyMessage, -ExternalAutoReplyMessage and -GrantFullAccessTo cannot be combined with -SkipMailbox.'
        }
        if ($ExternalAutoReplyMessage -and -not $AutoReplyMessage) {
            throw '-ExternalAutoReplyMessage requires -AutoReplyMessage.'
        }
        if (-not $BackupDirectory) { $BackupDirectory = $LogDirectory }

        Write-SDLog -Message ('Invoke-SDOffboarding started (WhatIf: {0}).' -f [bool]$WhatIfPreference)

        try {
            Assert-SDGraphConnection -RequiredScope 'User.ReadWrite.All', 'GroupMember.ReadWrite.All'
            if (-not $SkipMailbox) { Assert-SDExchangeConnection }
        }
        catch {
            Write-SDLog -Level ERROR -Message $_.Exception.Message
            throw
        }

        # Status used when ShouldProcess returns $false (-WhatIf or "No" at the confirmation prompt).
        $notApprovedStatus = if ($WhatIfPreference) { 'WhatIf' } else { 'Skipped' }
    }

    process {
        foreach ($upn in $UserPrincipalName) {
            $userCount++
            $steps = New-Object -TypeName 'System.Collections.Generic.List[object]'
            Write-SDLog -Message ('--- Offboarding {0} ---' -f $upn)

            try {
                # --- Read current state (no changes) ------------------------------------------
                $user = Get-MgUser -UserId $upn -Property 'id', 'displayName', 'userPrincipalName', 'accountEnabled', 'onPremisesSyncEnabled', 'assignedLicenses', 'licenseAssignmentStates'
                if (-not $user) { throw "User '$upn' not found." }
                $target = [string]$user.UserPrincipalName

                $groups = New-Object -TypeName 'System.Collections.Generic.List[object]'
                foreach ($entry in @(Get-MgUserMemberOf -UserId $user.Id -All)) {
                    $props = Get-SDPropertyValue -InputObject $entry -Name 'AdditionalProperties'
                    $odataType = Get-SDPropertyValue -InputObject $props -Name '@odata.type'
                    $name = Get-SDPropertyValue -InputObject $props -Name 'displayName'
                    if ($odataType -eq '#microsoft.graph.group') {
                        $groups.Add([pscustomobject]@{
                                Id                    = [string]$entry.Id
                                DisplayName           = [string]$name
                                Mail                  = [string](Get-SDPropertyValue -InputObject $props -Name 'mail')
                                GroupTypes            = @(Get-SDPropertyValue -InputObject $props -Name 'groupTypes')
                                MailEnabled           = [bool](Get-SDPropertyValue -InputObject $props -Name 'mailEnabled')
                                SecurityEnabled       = [bool](Get-SDPropertyValue -InputObject $props -Name 'securityEnabled')
                                OnPremisesSyncEnabled = [bool](Get-SDPropertyValue -InputObject $props -Name 'onPremisesSyncEnabled')
                            })
                    }
                    elseif ($odataType -eq '#microsoft.graph.directoryRole') {
                        Write-SDLog -Level WARN -Message ("{0} holds the directory role '{1}'. Review and remove it manually." -f $target, $name)
                        $steps.Add((ConvertTo-SDStepResult -Step 'ReviewRole' -Target $target -Status Skipped -Detail "Directory role '$name' - remove manually"))
                    }
                }

                $licenses = Get-SDLicenseAssignment -LicenseAssignmentStates (Get-SDPropertyValue -InputObject $user -Name 'LicenseAssignmentStates') -AssignedLicenses (Get-SDPropertyValue -InputObject $user -Name 'AssignedLicenses')
                $skuNames = @{}
                foreach ($detail in @(Get-MgUserLicenseDetail -UserId $user.Id -All)) {
                    $skuNames[[string]$detail.SkuId] = [string]$detail.SkuPartNumber
                }
                $skuLabel = { param($SkuId) if ($skuNames.ContainsKey($SkuId)) { $skuNames[$SkuId] } else { $SkuId } }

                $mailbox = $null
                if (-not $SkipMailbox) {
                    try {
                        $mailbox = Get-EXOMailbox -Identity $target -Properties 'RecipientTypeDetails', 'LitigationHoldEnabled', 'ArchiveStatus', 'ForwardingAddress', 'ForwardingSmtpAddress' -ErrorAction Stop
                    }
                    catch {
                        Write-SDLog -Level WARN -Message ('No mailbox found for {0} ({1}). Mailbox steps are skipped.' -f $target, $_.Exception.Message)
                    }
                }

                # --- 1. Backup before any change -------------------------------------------------
                $backup = [ordered]@{
                    CreatedAt         = (Get-Date).ToString('o')
                    UserPrincipalName = $target
                    UserId            = [string]$user.Id
                    DisplayName       = [string]$user.DisplayName
                    AccountEnabled    = [bool]$user.AccountEnabled
                    Groups            = $groups.ToArray()
                    DirectLicenses    = @($licenses.Direct | ForEach-Object { [pscustomobject]@{ SkuId = $_; SkuPartNumber = (& $skuLabel $_) } })
                    GroupLicenses     = @($licenses.Inherited | ForEach-Object { [pscustomobject]@{ SkuId = $_; SkuPartNumber = (& $skuLabel $_) } })
                    Mailbox           = $null
                }
                if ($mailbox) {
                    $backup.Mailbox = [ordered]@{
                        RecipientTypeDetails  = [string](Get-SDPropertyValue -InputObject $mailbox -Name 'RecipientTypeDetails')
                        LitigationHoldEnabled = [bool](Get-SDPropertyValue -InputObject $mailbox -Name 'LitigationHoldEnabled')
                        ArchiveStatus         = [string](Get-SDPropertyValue -InputObject $mailbox -Name 'ArchiveStatus')
                        ForwardingAddress     = [string](Get-SDPropertyValue -InputObject $mailbox -Name 'ForwardingAddress')
                        ForwardingSmtpAddress = [string](Get-SDPropertyValue -InputObject $mailbox -Name 'ForwardingSmtpAddress')
                    }
                }
                if (-not (Test-Path -LiteralPath $BackupDirectory)) {
                    $null = New-Item -Path $BackupDirectory -ItemType Directory -Force -WhatIf:$false -Confirm:$false
                }
                $backupPath = Join-Path -Path $BackupDirectory -ChildPath ('Offboarding_{0}_{1}.json' -f (ConvertTo-SDSafeFileName -Name $target), (Get-Date -Format 'yyyyMMdd_HHmmss'))
                [pscustomobject]$backup | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $backupPath -Encoding UTF8 -WhatIf:$false -Confirm:$false
                Write-SDLog -Message ('Backup written: {0} ({1} group(s), {2} direct license(s)).' -f $backupPath, $groups.Count, @($licenses.Direct).Count)

                # --- 2. Disable account (critical) -----------------------------------------------
                if (Get-SDPropertyValue -InputObject $user -Name 'OnPremisesSyncEnabled') {
                    Write-SDLog -Level WARN -Message ('{0} is synced from on-premises AD. Disable the account in AD; the change syncs to Entra ID.' -f $target)
                    $steps.Add((ConvertTo-SDStepResult -Step 'DisableAccount' -Target $target -Status Skipped -Detail 'Synced from on-premises AD - disable in AD'))
                }
                elseif (-not $user.AccountEnabled) {
                    $steps.Add((ConvertTo-SDStepResult -Step 'DisableAccount' -Target $target -Status NoChange -Detail 'Account already disabled'))
                }
                elseif ($PSCmdlet.ShouldProcess($target, 'Disable Entra ID account')) {
                    $steps.Add((Invoke-SDStep -StepName 'DisableAccount' -StepTarget $target -Critical -Action {
                                Update-MgUser -UserId $user.Id -AccountEnabled:$false
                                'Account disabled'
                            }))
                }
                else {
                    $steps.Add((ConvertTo-SDStepResult -Step 'DisableAccount' -Target $target -Status $notApprovedStatus -Detail 'Would disable the account'))
                }

                # --- 3. Revoke sessions (critical) -----------------------------------------------
                if ($PSCmdlet.ShouldProcess($target, 'Revoke all sign-in sessions')) {
                    $steps.Add((Invoke-SDStep -StepName 'RevokeSessions' -StepTarget $target -Critical -Action {
                                $null = Revoke-MgUserSignInSession -UserId $user.Id
                                'Sign-in sessions revoked'
                            }))
                }
                else {
                    $steps.Add((ConvertTo-SDStepResult -Step 'RevokeSessions' -Target $target -Status $notApprovedStatus -Detail 'Would revoke all sign-in sessions'))
                }

                # --- 4.-7. Mailbox ---------------------------------------------------------------
                if ($mailbox) {
                    $mailboxType = [string](Get-SDPropertyValue -InputObject $mailbox -Name 'RecipientTypeDetails')
                    $onHold = [bool](Get-SDPropertyValue -InputObject $mailbox -Name 'LitigationHoldEnabled')
                    $hasArchive = [string](Get-SDPropertyValue -InputObject $mailbox -Name 'ArchiveStatus') -eq 'Active'
                    if (($onHold -or $hasArchive) -and -not $SkipLicenseRemoval) {
                        Write-SDLog -Level WARN -Message ('Mailbox of {0} has a litigation hold or an archive. As a shared mailbox it still needs an Exchange Online Plan 2 (or archive) license. Consider -SkipLicenseRemoval.' -f $target)
                    }

                    if ($mailboxType -eq 'SharedMailbox') {
                        $steps.Add((ConvertTo-SDStepResult -Step 'ConvertToShared' -Target $target -Status NoChange -Detail 'Already a shared mailbox'))
                    }
                    elseif ($PSCmdlet.ShouldProcess($target, "Convert mailbox ($mailboxType) to shared mailbox")) {
                        $steps.Add((Invoke-SDStep -StepName 'ConvertToShared' -StepTarget $target -Action {
                                    Set-Mailbox -Identity $target -Type Shared
                                    "Converted $mailboxType to SharedMailbox"
                                }))
                    }
                    else {
                        $steps.Add((ConvertTo-SDStepResult -Step 'ConvertToShared' -Target $target -Status $notApprovedStatus -Detail "Would convert $mailboxType to SharedMailbox"))
                    }

                    foreach ($trustee in @($GrantFullAccessTo | Where-Object { $_ })) {
                        if ($PSCmdlet.ShouldProcess($target, "Grant FullAccess to $trustee")) {
                            $steps.Add((Invoke-SDStep -StepName 'GrantFullAccess' -StepTarget $target -Action {
                                        $null = Add-MailboxPermission -Identity $target -User $trustee -AccessRights FullAccess -InheritanceType All -AutoMapping $true
                                        "FullAccess granted to $trustee"
                                    }))
                        }
                        else {
                            $steps.Add((ConvertTo-SDStepResult -Step 'GrantFullAccess' -Target $target -Status $notApprovedStatus -Detail "Would grant FullAccess to $trustee"))
                        }
                    }

                    if ($ForwardTo) {
                        if ($PSCmdlet.ShouldProcess($target, "Forward mail to $ForwardTo")) {
                            $steps.Add((Invoke-SDStep -StepName 'Forwarding' -StepTarget $target -Action {
                                        $recipient = $null
                                        try { $recipient = Get-EXORecipient -Identity $ForwardTo -ErrorAction Stop } catch { $recipient = $null }
                                        if ($recipient) {
                                            Set-Mailbox -Identity $target -ForwardingAddress $ForwardTo -DeliverToMailboxAndForward $true
                                            "Forwarding to internal recipient $ForwardTo (copy kept)"
                                        }
                                        else {
                                            Set-Mailbox -Identity $target -ForwardingSmtpAddress "smtp:$ForwardTo" -DeliverToMailboxAndForward $true
                                            "Forwarding to external address $ForwardTo (copy kept)"
                                        }
                                    }))
                        }
                        else {
                            $steps.Add((ConvertTo-SDStepResult -Step 'Forwarding' -Target $target -Status $notApprovedStatus -Detail "Would forward mail to $ForwardTo"))
                        }
                    }

                    if ($AutoReplyMessage) {
                        $externalMessage = if ($ExternalAutoReplyMessage) { $ExternalAutoReplyMessage } else { $AutoReplyMessage }
                        if ($PSCmdlet.ShouldProcess($target, 'Enable automatic reply')) {
                            $steps.Add((Invoke-SDStep -StepName 'AutoReply' -StepTarget $target -Action {
                                        Set-MailboxAutoReplyConfiguration -Identity $target -AutoReplyState Enabled -InternalMessage $AutoReplyMessage -ExternalMessage $externalMessage -ExternalAudience All
                                        'Automatic reply enabled for internal and external senders'
                                    }))
                        }
                        else {
                            $steps.Add((ConvertTo-SDStepResult -Step 'AutoReply' -Target $target -Status $notApprovedStatus -Detail 'Would enable automatic reply'))
                        }
                    }
                }
                elseif (-not $SkipMailbox) {
                    $steps.Add((ConvertTo-SDStepResult -Step 'ConvertToShared' -Target $target -Status Skipped -Detail 'No mailbox found'))
                }

                # --- 8. Group memberships --------------------------------------------------------
                if ($SkipGroupRemoval) {
                    $steps.Add((ConvertTo-SDStepResult -Step 'RemoveGroups' -Target $target -Status Skipped -Detail '-SkipGroupRemoval'))
                }
                else {
                    foreach ($group in $groups) {
                        $groupLabel = '{0} ({1})' -f $group.DisplayName, $group.Id
                        $plan = Get-SDGroupRemovalMethod -Group $group -ExcludeGroupId $ExcludeGroupId

                        if ($plan.Method -eq 'Exchange' -and $SkipMailbox) {
                            $plan = [pscustomobject]@{ Method = 'Skip'; Reason = 'mail-enabled group needs Exchange Online (-SkipMailbox is set)' }
                        }

                        if ($plan.Method -eq 'Skip') {
                            Write-SDLog -Message ('[RemoveGroup] {0}: skipped {1} - {2}' -f $target, $groupLabel, $plan.Reason)
                            $steps.Add((ConvertTo-SDStepResult -Step 'RemoveGroup' -Target $groupLabel -Status Skipped -Detail $plan.Reason))
                        }
                        elseif ($PSCmdlet.ShouldProcess($target, "Remove from group $groupLabel [$($plan.Reason)]")) {
                            if ($plan.Method -eq 'Graph') {
                                $steps.Add((Invoke-SDStep -StepName 'RemoveGroup' -StepTarget $groupLabel -Action {
                                            Remove-MgGroupMemberDirectoryObjectByRef -GroupId $group.Id -DirectoryObjectId $user.Id
                                            "Removed $target ($($plan.Reason))"
                                        }))
                            }
                            else {
                                $groupIdentity = if ($group.Mail) { $group.Mail } else { $group.Id }
                                $steps.Add((Invoke-SDStep -StepName 'RemoveGroup' -StepTarget $groupLabel -Action {
                                            Remove-DistributionGroupMember -Identity $groupIdentity -Member $target -BypassSecurityGroupManagerCheck -Confirm:$false
                                            "Removed $target ($($plan.Reason))"
                                        }))
                            }
                        }
                        else {
                            $steps.Add((ConvertTo-SDStepResult -Step 'RemoveGroup' -Target $groupLabel -Status $notApprovedStatus -Detail "Would remove $target ($($plan.Reason))"))
                        }
                    }
                }

                # --- 9. Licenses (last, after the mailbox was converted) -------------------------
                foreach ($skuId in @($licenses.Inherited)) {
                    Write-SDLog -Message ('[RemoveLicenses] {0}: {1} is group-based and ends with the group membership.' -f $target, (& $skuLabel $skuId))
                }
                $direct = @($licenses.Direct)
                $directLabel = (@($direct | ForEach-Object { & $skuLabel $_ })) -join ', '
                if ($SkipLicenseRemoval) {
                    $steps.Add((ConvertTo-SDStepResult -Step 'RemoveLicenses' -Target $target -Status Skipped -Detail '-SkipLicenseRemoval'))
                }
                elseif ($direct.Count -eq 0) {
                    $steps.Add((ConvertTo-SDStepResult -Step 'RemoveLicenses' -Target $target -Status NoChange -Detail 'No directly assigned licenses'))
                }
                elseif ($PSCmdlet.ShouldProcess($target, "Remove licenses: $directLabel")) {
                    $steps.Add((Invoke-SDStep -StepName 'RemoveLicenses' -StepTarget $target -Action {
                                $null = Set-MgUserLicense -UserId $user.Id -AddLicenses @() -RemoveLicenses $direct
                                "Removed $directLabel"
                            }))
                }
                else {
                    $steps.Add((ConvertTo-SDStepResult -Step 'RemoveLicenses' -Target $target -Status $notApprovedStatus -Detail "Would remove $directLabel"))
                }

                $failed = @($steps | Where-Object { $_.Status -eq 'Failed' })
                $failedStepCount += $failed.Count
                if ($failed.Count -gt 0) {
                    Write-SDLog -Level WARN -Message ('{0}: {1} step(s) failed - see log and result.' -f $target, $failed.Count)
                }

                [pscustomobject]@{
                    PSTypeName        = 'ServiceDeskToolkit.OffboardingResult'
                    UserPrincipalName = $target
                    UserId            = [string]$user.Id
                    DisplayName       = [string]$user.DisplayName
                    Succeeded         = ($failed.Count -eq 0)
                    WhatIf            = [bool]$WhatIfPreference
                    BackupPath        = $backupPath
                    Steps             = $steps.ToArray()
                }
            }
            catch {
                Write-SDLog -Level ERROR -Message ('Offboarding of {0} stopped: {1}' -f $upn, $_.Exception.Message)
                throw
            }
        }
    }

    end {
        $stopwatch.Stop()
        Write-SDLog -Message ('Invoke-SDOffboarding finished: {0} user(s), {1} failed step(s), duration {2:N1} s.' -f $userCount, $failedStepCount, $stopwatch.Elapsed.TotalSeconds)
    }
}
