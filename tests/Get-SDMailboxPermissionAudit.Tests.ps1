BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

AfterAll {
    Get-Module ServiceDeskToolkit | Remove-Module -Force
}

Describe 'Get-SDMailboxPermissionAudit' {
    BeforeEach {
        $outDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $logDir = Join-Path $outDir 'logs'

        Mock -ModuleName ServiceDeskToolkit Get-ConnectionInformation { [pscustomobject]@{ State = 'Connected'; TenantID = 'tenant-1' } }
        Mock -ModuleName ServiceDeskToolkit Get-EXOMailbox {
            [pscustomobject]@{ DisplayName = 'Info'; UserPrincipalName = 'info@contoso.com'; PrimarySmtpAddress = 'info@contoso.com'; RecipientTypeDetails = 'SharedMailbox'; GrantSendOnBehalfTo = @('Erika Chef') }
            [pscustomobject]@{ DisplayName = 'Max Muster'; UserPrincipalName = 'max@contoso.com'; PrimarySmtpAddress = 'max@contoso.com'; RecipientTypeDetails = 'UserMailbox'; GrantSendOnBehalfTo = @() }
        }
        Mock -ModuleName ServiceDeskToolkit Get-EXOMailbox -ParameterFilter { $Identity } {
            [pscustomobject]@{ DisplayName = $Identity; UserPrincipalName = $Identity; PrimarySmtpAddress = $Identity; RecipientTypeDetails = 'SharedMailbox'; GrantSendOnBehalfTo = @() }
        }
        Mock -ModuleName ServiceDeskToolkit Get-EXOMailboxPermission {
            [pscustomobject]@{ Identity = $Identity; User = 'NT AUTHORITY\SELF'; AccessRights = @('FullAccess', 'ReadPermission'); IsInherited = $false; Deny = $false }
            [pscustomobject]@{ Identity = $Identity; User = 'CONTOSO\Domain Admins'; AccessRights = @('FullAccess'); IsInherited = $true; Deny = $false }
            if ($Identity -eq 'info@contoso.com') {
                [pscustomobject]@{ Identity = $Identity; User = 'erika@contoso.com'; AccessRights = @('FullAccess'); IsInherited = $false; Deny = $false }
                [pscustomobject]@{ Identity = $Identity; User = 'S-1-5-21-1111111111-2222222222-3333333333-1105'; AccessRights = @('FullAccess'); IsInherited = $false; Deny = $false }
                [pscustomobject]@{ Identity = $Identity; User = 'tom@contoso.com'; AccessRights = @('FullAccess'); IsInherited = $false; Deny = $true }
                [pscustomobject]@{ Identity = $Identity; User = 'audit@contoso.com'; AccessRights = @('ReadPermission'); IsInherited = $false; Deny = $false }
            }
        }
        Mock -ModuleName ServiceDeskToolkit Get-EXORecipientPermission {
            [pscustomobject]@{ Identity = $Identity; Trustee = 'NT AUTHORITY\SELF'; AccessControlType = 'Allow'; AccessRights = @('SendAs'); IsInherited = $false }
            if ($Identity -eq 'info@contoso.com') {
                [pscustomobject]@{ Identity = $Identity; Trustee = 'erika@contoso.com'; AccessControlType = 'Allow'; AccessRights = @('SendAs'); IsInherited = $false }
            }
        }

        $params = @{ OutputDirectory = $outDir; LogDirectory = $logDir }
    }

    It 'audits all mailboxes of the default types' {
        $null = Get-SDMailboxPermissionAudit @params
        Should -Invoke -ModuleName ServiceDeskToolkit Get-EXOMailbox -Times 1 -Exactly -ParameterFilter {
            $ResultSize -eq 'Unlimited' -and $RecipientTypeDetails.Count -eq 4 -and $Properties -contains 'GrantSendOnBehalfTo'
        }
        Should -Invoke -ModuleName ServiceDeskToolkit Get-EXOMailboxPermission -Times 2 -Exactly
        Should -Invoke -ModuleName ServiceDeskToolkit Get-EXORecipientPermission -Times 2 -Exactly -ParameterFilter { $AccessRights -contains 'SendAs' }
    }

    It 'returns FullAccess, SendAs and SendOnBehalf entries' {
        $rows = @(Get-SDMailboxPermissionAudit @params)
        $rows.Count | Should -Be 5
        @($rows | Where-Object Permission -EQ 'FullAccess').Count | Should -Be 3
        ($rows | Where-Object Permission -EQ 'SendAs').Trustee | Should -Be 'erika@contoso.com'
        ($rows | Where-Object Permission -EQ 'SendOnBehalf').Trustee | Should -Be 'Erika Chef'
        $rows[0].PSObject.TypeNames | Should -Contain 'ServiceDeskToolkit.MailboxPermission'
        $rows[0].MailboxType | Should -Be 'SharedMailbox'
    }

    It 'ignores SELF, inherited entries and rights other than FullAccess' {
        $rows = @(Get-SDMailboxPermissionAudit @params)
        $rows.Trustee | Should -Not -Contain 'NT AUTHORITY\SELF'
        $rows.Trustee | Should -Not -Contain 'CONTOSO\Domain Admins'
        $rows.Trustee | Should -Not -Contain 'audit@contoso.com'
        $rows.Mailbox | Should -Not -Contain 'max@contoso.com'
    }

    It 'marks unresolved SIDs as orphaned and reports deny entries' {
        $rows = @(Get-SDMailboxPermissionAudit @params)
        $orphan = $rows | Where-Object Orphaned
        @($orphan).Count | Should -Be 1
        $orphan.Trustee | Should -Match '^S-1-5-21-'
        ($rows | Where-Object Trustee -EQ 'tom@contoso.com').AccessType | Should -Be 'Deny'
    }

    It 'audits only the given mailboxes, also from the pipeline' {
        $rows = @('info@contoso.com', 'max@contoso.com' | Get-SDMailboxPermissionAudit @params)
        Should -Invoke -ModuleName ServiceDeskToolkit Get-EXOMailbox -Times 2 -Exactly -ParameterFilter { $Identity }
        Should -Invoke -ModuleName ServiceDeskToolkit Get-EXOMailbox -Times 0 -ParameterFilter { $ResultSize }
        $rows.Mailbox | Should -Contain 'info@contoso.com'
    }

    It 'collects only the requested permission types' {
        $rows = @(Get-SDMailboxPermissionAudit @params -PermissionType FullAccess)
        Should -Invoke -ModuleName ServiceDeskToolkit Get-EXORecipientPermission -Times 0
        ($rows.Permission | Select-Object -Unique) | Should -Be 'FullAccess'
    }

    It 'continues when one mailbox cannot be read' {
        Mock -ModuleName ServiceDeskToolkit Get-EXOMailboxPermission { throw 'Mailbox is locked' } -ParameterFilter { $Identity -eq 'max@contoso.com' }
        $rows = @(Get-SDMailboxPermissionAudit @params -WarningAction SilentlyContinue)
        $rows.Count | Should -Be 5
        $log = Get-Content -LiteralPath (Join-Path $logDir ('Log_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd'))) -Raw
        $log | Should -Match '\[ERROR\] Permissions of max@contoso.com could not be read: Mailbox is locked'
        $html = Get-Content -LiteralPath (Get-ChildItem -Path $outDir -Filter '*.html').FullName -Raw
        $html | Should -Match '<dt>Failed mailboxes</dt><dd>1</dd>'
    }

    It 'logs a mailbox that does not exist and audits the rest' {
        Mock -ModuleName ServiceDeskToolkit Get-EXOMailbox { throw "Couldn't find object" } -ParameterFilter { $Identity -eq 'gone@contoso.com' }
        $rows = @(Get-SDMailboxPermissionAudit @params -Identity 'gone@contoso.com', 'info@contoso.com' -WarningAction SilentlyContinue)
        $rows.Mailbox | Should -Contain 'info@contoso.com'
        $log = Get-Content -LiteralPath (Join-Path $logDir ('Log_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd'))) -Raw
        $log | Should -Match "\[ERROR\] Mailbox 'gone@contoso.com' not found"
    }

    It 'writes CSV and HTML reports' {
        $null = Get-SDMailboxPermissionAudit @params -Delimiter ';'
        $csv = Get-ChildItem -Path $outDir -Filter 'MailboxPermissionAudit_*.csv'
        $csv.Count | Should -Be 1
        $data = @(Import-Csv -LiteralPath $csv.FullName -Delimiter ';')
        $data.Count | Should -Be 5
        @($data | Where-Object Orphaned -EQ 'True').Count | Should -Be 1

        $html = Get-Content -LiteralPath (Get-ChildItem -Path $outDir -Filter 'MailboxPermissionAudit_*.html').FullName -Raw
        $html | Should -Match '<dt>Mailboxes</dt><dd>2</dd>'
        $html | Should -Match '<dt>Orphaned</dt><dd>1</dd>'
        $html | Should -Match 'erika@contoso.com'
        ([regex]::Matches($html, '<tr class="flag">')).Count | Should -Be 1
    }

    It 'throws when Exchange Online is not connected' {
        Mock -ModuleName ServiceDeskToolkit Get-ConnectionInformation { }
        { Get-SDMailboxPermissionAudit @params } | Should -Throw '*Connect-ExchangeOnline*'
        Should -Invoke -ModuleName ServiceDeskToolkit Get-EXOMailbox -Times 0
    }
}
