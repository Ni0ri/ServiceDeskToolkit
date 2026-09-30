BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

AfterAll {
    Get-Module ServiceDeskToolkit | Remove-Module -Force
}

Describe 'Invoke-SDOffboarding' {
    BeforeEach {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))

        Mock -ModuleName ServiceDeskToolkit Get-MgContext {
            [pscustomobject]@{ Account = 'admin@contoso.com'; TenantId = 'tenant-1'; AuthType = 'Delegated'; Scopes = @('User.ReadWrite.All', 'GroupMember.ReadWrite.All') }
        }
        Mock -ModuleName ServiceDeskToolkit Get-ConnectionInformation { [pscustomobject]@{ State = 'Connected'; TenantID = 'tenant-1' } }
        Mock -ModuleName ServiceDeskToolkit Get-MgUser {
            [pscustomobject]@{
                Id                      = 'user-1'
                DisplayName             = 'Max Muster'
                UserPrincipalName       = $UserId
                AccountEnabled          = $true
                OnPremisesSyncEnabled   = $null
                AssignedLicenses        = @([pscustomobject]@{ SkuId = 'sku-e3' }, [pscustomobject]@{ SkuId = 'sku-ems' })
                LicenseAssignmentStates = @(
                    [pscustomobject]@{ SkuId = 'sku-e3'; AssignedByGroup = $null; State = 'Active' }
                    [pscustomobject]@{ SkuId = 'sku-ems'; AssignedByGroup = 'group-lic'; State = 'Active' }
                )
            }
        }
        Mock -ModuleName ServiceDeskToolkit Get-MgUserMemberOf {
            New-TestGraphGroup -Id 'group-sec' -Name 'SG-Finance'
            New-TestGraphGroup -Id 'group-m365' -Name 'Team Finance' -GroupTypes 'Unified' -MailEnabled $true -Mail 'team-finance@contoso.com'
            New-TestGraphGroup -Id 'group-dl' -Name 'DL All Staff' -MailEnabled $true -Mail 'all-staff@contoso.com'
            New-TestGraphGroup -Id 'group-dyn' -Name 'DYN Germany' -GroupTypes 'DynamicMembership'
            New-TestGraphGroup -Id 'group-sync' -Name 'AD-VPN-Users' -OnPremisesSyncEnabled $true
            [pscustomobject]@{ Id = 'role-1'; AdditionalProperties = (New-TestGraphDictionary @{ '@odata.type' = '#microsoft.graph.directoryRole'; displayName = 'Helpdesk Administrator' }) }
        }
        Mock -ModuleName ServiceDeskToolkit Get-MgUserLicenseDetail {
            [pscustomobject]@{ SkuId = 'sku-e3'; SkuPartNumber = 'SPE_E3' }
            [pscustomobject]@{ SkuId = 'sku-ems'; SkuPartNumber = 'EMS' }
        }
        Mock -ModuleName ServiceDeskToolkit Get-EXOMailbox {
            [pscustomobject]@{ RecipientTypeDetails = 'UserMailbox'; LitigationHoldEnabled = $false; ArchiveStatus = 'None'; ForwardingAddress = $null; ForwardingSmtpAddress = $null }
        }
        Mock -ModuleName ServiceDeskToolkit Get-EXORecipient { [pscustomobject]@{ PrimarySmtpAddress = $Identity } }
        Mock -ModuleName ServiceDeskToolkit Update-MgUser { }
        Mock -ModuleName ServiceDeskToolkit Revoke-MgUserSignInSession { $true }
        Mock -ModuleName ServiceDeskToolkit Set-Mailbox { }
        Mock -ModuleName ServiceDeskToolkit Add-MailboxPermission { }
        Mock -ModuleName ServiceDeskToolkit Set-MailboxAutoReplyConfiguration { }
        Mock -ModuleName ServiceDeskToolkit Remove-MgGroupMemberDirectoryObjectByRef { }
        Mock -ModuleName ServiceDeskToolkit Remove-DistributionGroupMember { }
        Mock -ModuleName ServiceDeskToolkit Set-MgUserLicense { }

        $params = @{
            UserPrincipalName = 'max@contoso.com'
            LogDirectory      = $logDir
            Confirm           = $false
            WarningAction     = 'SilentlyContinue'
        }
    }

    Context 'Default run for a cloud user' {
        BeforeEach {
            $result = Invoke-SDOffboarding @params
        }

        It 'returns a successful result object' {
            $result.UserPrincipalName | Should -Be 'max@contoso.com'
            $result.UserId | Should -Be 'user-1'
            $result.Succeeded | Should -BeTrue
            $result.WhatIf | Should -BeFalse
            $result.PSObject.TypeNames | Should -Contain 'ServiceDeskToolkit.OffboardingResult'
        }

        It 'disables the account and revokes sessions' {
            Should -Invoke -ModuleName ServiceDeskToolkit Update-MgUser -Times 1 -Exactly -ParameterFilter { $UserId -eq 'user-1' -and $AccountEnabled -is [switch] -and -not $AccountEnabled }
            Should -Invoke -ModuleName ServiceDeskToolkit Revoke-MgUserSignInSession -Times 1 -Exactly -ParameterFilter { $UserId -eq 'user-1' }
        }

        It 'converts the mailbox to a shared mailbox' {
            Should -Invoke -ModuleName ServiceDeskToolkit Set-Mailbox -Times 1 -Exactly -ParameterFilter { $Identity -eq 'max@contoso.com' -and $Type -eq 'Shared' }
        }

        It 'removes security and Microsoft 365 groups via Graph' {
            Should -Invoke -ModuleName ServiceDeskToolkit Remove-MgGroupMemberDirectoryObjectByRef -Times 2 -Exactly
            Should -Invoke -ModuleName ServiceDeskToolkit Remove-MgGroupMemberDirectoryObjectByRef -Times 1 -Exactly -ParameterFilter { $GroupId -eq 'group-sec' -and $DirectoryObjectId -eq 'user-1' }
            Should -Invoke -ModuleName ServiceDeskToolkit Remove-MgGroupMemberDirectoryObjectByRef -Times 1 -Exactly -ParameterFilter { $GroupId -eq 'group-m365' }
        }

        It 'removes distribution lists via Exchange Online using the group address' {
            Should -Invoke -ModuleName ServiceDeskToolkit Remove-DistributionGroupMember -Times 1 -Exactly -ParameterFilter { $Identity -eq 'all-staff@contoso.com' -and $Member -eq 'max@contoso.com' }
        }

        It 'skips dynamic and on-premises synced groups' {
            $skipped = @($result.Steps | Where-Object { $_.Step -eq 'RemoveGroup' -and $_.Status -eq 'Skipped' })
            $skipped.Target | Should -Contain 'DYN Germany (group-dyn)'
            $skipped.Target | Should -Contain 'AD-VPN-Users (group-sync)'
            Should -Invoke -ModuleName ServiceDeskToolkit Remove-MgGroupMemberDirectoryObjectByRef -Times 0 -ParameterFilter { $GroupId -in 'group-dyn', 'group-sync' }
        }

        It 'reports directory roles without removing them' {
            ($result.Steps | Where-Object Step -EQ 'ReviewRole').Detail | Should -Match 'Helpdesk Administrator'
        }

        It 'removes only directly assigned licenses' {
            Should -Invoke -ModuleName ServiceDeskToolkit Set-MgUserLicense -Times 1 -Exactly -ParameterFilter {
                ($RemoveLicenses -join ',') -eq 'sku-e3' -and @($AddLicenses).Count -eq 0
            }
            ($result.Steps | Where-Object Step -EQ 'RemoveLicenses').Detail | Should -Be 'Removed SPE_E3'
        }

        It 'runs the steps in a safe order (disable first, licenses last)' {
            $order = @($result.Steps | Where-Object Step -NE 'ReviewRole' | ForEach-Object Step | Select-Object -Unique)
            $order[0] | Should -Be 'DisableAccount'
            $order[1] | Should -Be 'RevokeSessions'
            $order.IndexOf('ConvertToShared') | Should -BeLessThan $order.IndexOf('RemoveLicenses')
            $order[-1] | Should -Be 'RemoveLicenses'
        }

        It 'writes a JSON backup with groups and licenses' {
            $result.BackupPath | Should -Exist
            $backup = Get-Content -LiteralPath $result.BackupPath -Raw | ConvertFrom-Json
            $backup.UserId | Should -Be 'user-1'
            @($backup.Groups).Count | Should -Be 5
            $backup.DirectLicenses[0].SkuPartNumber | Should -Be 'SPE_E3'
            $backup.GroupLicenses[0].SkuPartNumber | Should -Be 'EMS'
            $backup.Mailbox.RecipientTypeDetails | Should -Be 'UserMailbox'
        }

        It 'writes a daily log file with start and end entries' {
            $logFile = Join-Path $logDir ('Log_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd'))
            $logFile | Should -Exist
            $log = Get-Content -LiteralPath $logFile -Raw
            $log | Should -Match '\[INFO\] Invoke-SDOffboarding started'
            $log | Should -Match '\[INFO\] \[DisableAccount\] max@contoso.com: Account disabled'
            $log | Should -Match 'finished: 1 user\(s\), 0 failed step\(s\)'
        }

        It 'does not touch forwarding, auto reply or permissions unless asked' {
            Should -Invoke -ModuleName ServiceDeskToolkit Set-Mailbox -Times 0 -ParameterFilter { $ForwardingAddress -or $ForwardingSmtpAddress }
            Should -Invoke -ModuleName ServiceDeskToolkit Set-MailboxAutoReplyConfiguration -Times 0
            Should -Invoke -ModuleName ServiceDeskToolkit Add-MailboxPermission -Times 0
        }
    }

    Context '-WhatIf' {
        BeforeEach {
            $params.Remove('Confirm')
            $result = Invoke-SDOffboarding @params -WhatIf
        }

        It 'changes nothing' {
            foreach ($command in 'Update-MgUser', 'Revoke-MgUserSignInSession', 'Set-Mailbox', 'Remove-MgGroupMemberDirectoryObjectByRef', 'Remove-DistributionGroupMember', 'Set-MgUserLicense') {
                Should -Invoke -ModuleName ServiceDeskToolkit $command -Times 0 -Exactly
            }
        }

        It 'reports every planned change as WhatIf' {
            $result.WhatIf | Should -BeTrue
            $planned = @($result.Steps | Where-Object Status -EQ 'WhatIf')
            $planned.Step | Should -Contain 'DisableAccount'
            $planned.Step | Should -Contain 'RevokeSessions'
            $planned.Step | Should -Contain 'ConvertToShared'
            $planned.Step | Should -Contain 'RemoveLicenses'
            @($planned | Where-Object Step -EQ 'RemoveGroup').Count | Should -Be 3
        }

        It 'still writes the backup and the log' {
            $result.BackupPath | Should -Exist
            Join-Path $logDir ('Log_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd')) | Should -Exist
        }
    }

    Context 'Optional mailbox steps' {
        It 'sets forwarding to an internal recipient as ForwardingAddress' {
            $null = Invoke-SDOffboarding @params -ForwardTo 'erika@contoso.com'
            Should -Invoke -ModuleName ServiceDeskToolkit Set-Mailbox -Times 1 -Exactly -ParameterFilter { $ForwardingAddress -eq 'erika@contoso.com' -and $DeliverToMailboxAndForward }
        }

        It 'sets forwarding to an external address as ForwardingSmtpAddress' {
            Mock -ModuleName ServiceDeskToolkit Get-EXORecipient { throw 'not found' }
            $null = Invoke-SDOffboarding @params -ForwardTo 'max.private@example.org'
            Should -Invoke -ModuleName ServiceDeskToolkit Set-Mailbox -Times 1 -Exactly -ParameterFilter { $ForwardingSmtpAddress -eq 'smtp:max.private@example.org' }
        }

        It 'rejects an invalid forwarding address' {
            { Invoke-SDOffboarding @params -ForwardTo 'not-an-address' } | Should -Throw
        }

        It 'enables the automatic reply with separate external text' {
            $null = Invoke-SDOffboarding @params -AutoReplyMessage 'intern' -ExternalAutoReplyMessage 'extern'
            Should -Invoke -ModuleName ServiceDeskToolkit Set-MailboxAutoReplyConfiguration -Times 1 -Exactly -ParameterFilter {
                $AutoReplyState -eq 'Enabled' -and $InternalMessage -eq 'intern' -and $ExternalMessage -eq 'extern' -and $ExternalAudience -eq 'All'
            }
        }

        It 'uses the internal text for external senders by default' {
            $null = Invoke-SDOffboarding @params -AutoReplyMessage 'hello'
            Should -Invoke -ModuleName ServiceDeskToolkit Set-MailboxAutoReplyConfiguration -Times 1 -Exactly -ParameterFilter { $ExternalMessage -eq 'hello' }
        }

        It 'grants FullAccess to each given user' {
            $null = Invoke-SDOffboarding @params -GrantFullAccessTo 'erika@contoso.com', 'tom@contoso.com'
            Should -Invoke -ModuleName ServiceDeskToolkit Add-MailboxPermission -Times 2 -Exactly
            Should -Invoke -ModuleName ServiceDeskToolkit Add-MailboxPermission -Times 1 -Exactly -ParameterFilter { $User -eq 'tom@contoso.com' -and $AccessRights -contains 'FullAccess' -and $AutoMapping }
        }

        It 'does not convert a mailbox that is already shared' {
            Mock -ModuleName ServiceDeskToolkit Get-EXOMailbox { [pscustomobject]@{ RecipientTypeDetails = 'SharedMailbox'; LitigationHoldEnabled = $false; ArchiveStatus = 'None'; ForwardingAddress = $null; ForwardingSmtpAddress = $null } }
            $result = Invoke-SDOffboarding @params
            ($result.Steps | Where-Object Step -EQ 'ConvertToShared').Status | Should -Be 'NoChange'
            Should -Invoke -ModuleName ServiceDeskToolkit Set-Mailbox -Times 0
        }

        It 'skips mailbox steps when the user has no mailbox' {
            Mock -ModuleName ServiceDeskToolkit Get-EXOMailbox { throw "Couldn't find object" }
            $result = Invoke-SDOffboarding @params -AutoReplyMessage 'hello'
            ($result.Steps | Where-Object Step -EQ 'ConvertToShared').Status | Should -Be 'Skipped'
            Should -Invoke -ModuleName ServiceDeskToolkit Set-Mailbox -Times 0
            Should -Invoke -ModuleName ServiceDeskToolkit Set-MailboxAutoReplyConfiguration -Times 0
            $result.Succeeded | Should -BeTrue
        }

        It 'warns about litigation hold before removing licenses' {
            Mock -ModuleName ServiceDeskToolkit Get-EXOMailbox { [pscustomobject]@{ RecipientTypeDetails = 'UserMailbox'; LitigationHoldEnabled = $true; ArchiveStatus = 'None'; ForwardingAddress = $null; ForwardingSmtpAddress = $null } }
            $params.Remove('WarningAction')
            $null = Invoke-SDOffboarding @params -WarningVariable warnings -WarningAction SilentlyContinue
            ($warnings -join "`n") | Should -Match 'litigation hold'
        }
    }

    Context 'Switches and exclusions' {
        It '-SkipMailbox needs no Exchange connection and skips distribution lists' {
            $result = Invoke-SDOffboarding @params -SkipMailbox
            Should -Invoke -ModuleName ServiceDeskToolkit Get-ConnectionInformation -Times 0
            Should -Invoke -ModuleName ServiceDeskToolkit Get-EXOMailbox -Times 0
            Should -Invoke -ModuleName ServiceDeskToolkit Remove-DistributionGroupMember -Times 0
            ($result.Steps | Where-Object Target -EQ 'DL All Staff (group-dl)').Status | Should -Be 'Skipped'
            Should -Invoke -ModuleName ServiceDeskToolkit Remove-MgGroupMemberDirectoryObjectByRef -Times 2 -Exactly
        }

        It '-SkipMailbox cannot be combined with mailbox options' {
            { Invoke-SDOffboarding @params -SkipMailbox -ForwardTo 'erika@contoso.com' } | Should -Throw '*cannot be combined*'
        }

        It '-ExternalAutoReplyMessage requires -AutoReplyMessage' {
            { Invoke-SDOffboarding @params -ExternalAutoReplyMessage 'extern' } | Should -Throw '*requires -AutoReplyMessage*'
        }

        It '-SkipGroupRemoval keeps all groups' {
            $null = Invoke-SDOffboarding @params -SkipGroupRemoval
            Should -Invoke -ModuleName ServiceDeskToolkit Remove-MgGroupMemberDirectoryObjectByRef -Times 0
            Should -Invoke -ModuleName ServiceDeskToolkit Remove-DistributionGroupMember -Times 0
        }

        It '-SkipLicenseRemoval keeps all licenses' {
            $result = Invoke-SDOffboarding @params -SkipLicenseRemoval
            Should -Invoke -ModuleName ServiceDeskToolkit Set-MgUserLicense -Times 0
            ($result.Steps | Where-Object Step -EQ 'RemoveLicenses').Status | Should -Be 'Skipped'
        }

        It '-ExcludeGroupId keeps the listed group' {
            $result = Invoke-SDOffboarding @params -ExcludeGroupId 'group-sec'
            Should -Invoke -ModuleName ServiceDeskToolkit Remove-MgGroupMemberDirectoryObjectByRef -Times 0 -ParameterFilter { $GroupId -eq 'group-sec' }
            ($result.Steps | Where-Object Target -EQ 'SG-Finance (group-sec)').Detail | Should -Match 'excluded'
        }
    }

    Context 'Special accounts' {
        It 'does not disable an account that is already disabled' {
            Mock -ModuleName ServiceDeskToolkit Get-MgUser { [pscustomobject]@{ Id = 'user-1'; DisplayName = 'Max'; UserPrincipalName = 'max@contoso.com'; AccountEnabled = $false; OnPremisesSyncEnabled = $null; AssignedLicenses = @(); LicenseAssignmentStates = @() } }
            $result = Invoke-SDOffboarding @params
            Should -Invoke -ModuleName ServiceDeskToolkit Update-MgUser -Times 0
            ($result.Steps | Where-Object Step -EQ 'DisableAccount').Status | Should -Be 'NoChange'
            ($result.Steps | Where-Object Step -EQ 'RemoveLicenses').Status | Should -Be 'NoChange'
        }

        It 'skips disabling for on-premises synced users but still revokes sessions' {
            Mock -ModuleName ServiceDeskToolkit Get-MgUser { [pscustomobject]@{ Id = 'user-1'; DisplayName = 'Max'; UserPrincipalName = 'max@contoso.com'; AccountEnabled = $true; OnPremisesSyncEnabled = $true; AssignedLicenses = @(); LicenseAssignmentStates = @() } }
            $result = Invoke-SDOffboarding @params
            Should -Invoke -ModuleName ServiceDeskToolkit Update-MgUser -Times 0
            Should -Invoke -ModuleName ServiceDeskToolkit Revoke-MgUserSignInSession -Times 1 -Exactly
            ($result.Steps | Where-Object Step -EQ 'DisableAccount').Detail | Should -Match 'on-premises'
        }

        It 'treats all assigned licenses as direct when licenseAssignmentStates is empty' {
            Mock -ModuleName ServiceDeskToolkit Get-MgUser { [pscustomobject]@{ Id = 'user-1'; DisplayName = 'Max'; UserPrincipalName = 'max@contoso.com'; AccountEnabled = $true; OnPremisesSyncEnabled = $null; AssignedLicenses = @([pscustomobject]@{ SkuId = 'sku-a' }, [pscustomobject]@{ SkuId = 'sku-b' }); LicenseAssignmentStates = @() } }
            $null = Invoke-SDOffboarding @params
            Should -Invoke -ModuleName ServiceDeskToolkit Set-MgUserLicense -Times 1 -Exactly -ParameterFilter { ($RemoveLicenses -join ',') -eq 'sku-a,sku-b' }
        }
    }

    Context 'Error handling' {
        It 'throws when Microsoft Graph is not connected' {
            Mock -ModuleName ServiceDeskToolkit Get-MgContext { $null }
            { Invoke-SDOffboarding @params } | Should -Throw '*Connect-MgGraph*'
            Should -Invoke -ModuleName ServiceDeskToolkit Get-MgUser -Times 0
        }

        It 'throws when Exchange Online is not connected' {
            Mock -ModuleName ServiceDeskToolkit Get-ConnectionInformation { $null }
            { Invoke-SDOffboarding @params } | Should -Throw '*Connect-ExchangeOnline*'
        }

        It 'throws and changes nothing when the user does not exist' {
            Mock -ModuleName ServiceDeskToolkit Get-MgUser { throw "Resource 'nobody@contoso.com' does not exist" }
            { Invoke-SDOffboarding @params } | Should -Throw '*does not exist*'
            Should -Invoke -ModuleName ServiceDeskToolkit Update-MgUser -Times 0
        }

        It 'stops when the account cannot be disabled (critical step) and logs the error' {
            Mock -ModuleName ServiceDeskToolkit Update-MgUser { throw 'Insufficient privileges' }
            { Invoke-SDOffboarding @params } | Should -Throw '*Insufficient privileges*'
            Should -Invoke -ModuleName ServiceDeskToolkit Revoke-MgUserSignInSession -Times 0
            Should -Invoke -ModuleName ServiceDeskToolkit Set-MgUserLicense -Times 0
            $log = Get-Content -LiteralPath (Join-Path $logDir ('Log_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd'))) -Raw
            $log | Should -Match '\[ERROR\] \[DisableAccount\] max@contoso.com failed: Insufficient privileges'
            @(Get-ChildItem -Path $logDir -Filter 'Offboarding_*.json').Count | Should -Be 1
        }

        It 'continues after a non-critical failure and reports it' {
            Mock -ModuleName ServiceDeskToolkit Remove-MgGroupMemberDirectoryObjectByRef { throw 'Group is read-only' } -ParameterFilter { $GroupId -eq 'group-sec' }
            $result = Invoke-SDOffboarding @params
            $result.Succeeded | Should -BeFalse
            $failed = @($result.Steps | Where-Object Status -EQ 'Failed')
            $failed.Count | Should -Be 1
            $failed[0].Detail | Should -Be 'Group is read-only'
            Should -Invoke -ModuleName ServiceDeskToolkit Remove-MgGroupMemberDirectoryObjectByRef -Times 1 -Exactly -ParameterFilter { $GroupId -eq 'group-m365' }
            Should -Invoke -ModuleName ServiceDeskToolkit Set-MgUserLicense -Times 1 -Exactly
        }
    }

    Context 'Pipeline input' {
        It 'processes each piped user' {
            $results = @('a@contoso.com', 'b@contoso.com' | Invoke-SDOffboarding -LogDirectory $logDir -Confirm:$false -WarningAction SilentlyContinue)
            $results.Count | Should -Be 2
            $results.UserPrincipalName | Should -Be @('a@contoso.com', 'b@contoso.com')
            Should -Invoke -ModuleName ServiceDeskToolkit Update-MgUser -Times 2 -Exactly
        }

        It 'accepts objects with a UserPrincipalName property (e.g. Import-Csv)' {
            $results = @([pscustomobject]@{ UserPrincipalName = 'c@contoso.com' } | Invoke-SDOffboarding -LogDirectory $logDir -Confirm:$false -SkipMailbox -WarningAction SilentlyContinue)
            $results[0].UserPrincipalName | Should -Be 'c@contoso.com'
        }
    }
}
