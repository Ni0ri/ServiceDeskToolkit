# ServiceDeskToolkit

PowerShell-Modul für wiederkehrende Microsoft-365-Aufgaben im IT-Service-Desk: Offboarding in Entra ID und Exchange Online, Intune-Compliance-Report und Audit der Postfachberechtigungen.

PowerShell module for recurring Microsoft 365 service desk tasks: Entra ID / Exchange Online offboarding, Intune compliance report and mailbox permission audit.

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/ServiceDeskToolkit?label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/ServiceDeskToolkit)

**[Deutsch](#deutsch) · [English](#english)**

---

## Deutsch

### Zweck

In vielen kleinen und mittleren Unternehmen werden Offboarding und Berechtigungsprüfungen noch per Hand im Admin Center erledigt. Das ist fehleranfällig: Sitzungen bleiben aktiv, Lizenzen laufen weiter, und die Mitgliedschaft in einer Verteilerliste wird übersehen. Dieses Modul erledigt die Schritte immer in derselben, sicheren Reihenfolge. Jede Änderung lässt sich vorher mit `-WhatIf` prüfen und wird protokolliert.

| Funktion | Zweck | Ändert etwas? |
|---|---|---|
| `Invoke-SDOffboarding` | Benutzer offboarden: Konto deaktivieren, Sitzungen widerrufen, Postfach in eine freigegebene Mailbox (Shared Mailbox) umwandeln, optional Vollzugriff, Weiterleitung und Abwesenheitsnotiz einrichten, Gruppen und Lizenzen entfernen | Ja (`-WhatIf`/`-Confirm`) |
| `Get-SDIntuneNoncompliantReport` | Nicht konforme Intune-Geräte als CSV und HTML, mit Tagen seit dem letzten Check-in und optional den fehlschlagenden Richtlinien | Nein |
| `Get-SDMailboxPermissionAudit` | Postfachberechtigungen (FullAccess, SendAs, SendOnBehalf) als CSV und HTML; Berechtigungen gelöschter Konten werden markiert | Nein |
| `Test-SDToolkit` | Selbsttest der Kernlogik ohne Tenant (`n/n Tests grün`) | Nein |

### Voraussetzungen

- Windows PowerShell 5.1 oder PowerShell 7.4+
- Module (je nach Funktion):
  ```powershell
  Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Users.Actions, Microsoft.Graph.Groups, Microsoft.Graph.DeviceManagement -Scope CurrentUser
  Install-Module ExchangeOnlineManagement -Scope CurrentUser   # Version 3.x
  ```
  Die Module sind bewusst nicht als `RequiredModules` eingetragen. Jede Funktion prüft beim Start selbst, ob ihre Module vorhanden sind und eine Verbindung besteht, und meldet sonst den passenden `Connect-*`-Befehl.

### Benötigte Berechtigungen

| Funktion | Microsoft Graph (Scopes) | Rolle (delegiert) |
|---|---|---|
| `Invoke-SDOffboarding` | `User.ReadWrite.All`, `GroupMember.ReadWrite.All` · Minimalvariante: `User.Read.All`, `User.EnableDisableAccount.All`, `User.RevokeSessions.All`, `LicenseAssignment.ReadWrite.All`, `GroupMember.ReadWrite.All` | Benutzeradministrator, Gruppenadministrator, Lizenzadministrator; Exchange-Empfängeradministrator. Für Admin-Konten: Administrator für privilegierte Authentifizierung |
| `Get-SDIntuneNoncompliantReport` | `DeviceManagementManagedDevices.Read.All` (+ `DeviceManagementConfiguration.Read.All` bei `-IncludePolicyDetails`) | Intune-Rolle mit Lesezugriff, z. B. Read Only Operator |
| `Get-SDMailboxPermissionAudit` | – (nur Exchange Online) | View-Only Organization Management oder Globaler Leser |

Mit der Minimalvariante erscheint beim Start eine Warnung, dass `User.ReadWrite.All` fehlt. Die Warnung ist dann unkritisch.
Für unbeaufsichtigte Läufe (App-only) werden die gleichen Scopes als Anwendungsberechtigungen vergeben. Für Exchange kommen `Exchange.ManageAsApp` und eine passende Entra-Rolle hinzu, die Anmeldung erfolgt per Zertifikat. Geheimnisse gehören nie ins Skript.

### Installation

Aus der [PowerShell Gallery](https://www.powershellgallery.com/packages/ServiceDeskToolkit):

```powershell
Install-PSResource ServiceDeskToolkit                    # PowerShell 7.4+ (PSResourceGet)
Install-Module ServiceDeskToolkit -Scope CurrentUser     # Windows PowerShell 5.1 (PowerShellGet)
Import-Module ServiceDeskToolkit
Test-SDToolkit
```

Die Microsoft-Graph- und Exchange-Module werden dabei nicht mitinstalliert (siehe Voraussetzungen).

Lokal aus dem Repository:

```powershell
git clone https://github.com/Ni0ri/ServiceDeskToolkit.git C:\Tools\ServiceDeskToolkit
Import-Module C:\Tools\ServiceDeskToolkit\ServiceDeskToolkit\ServiceDeskToolkit.psd1
Test-SDToolkit            # Summary: 13/13 Tests grün
Get-Help Invoke-SDOffboarding -Full
```

### Beispiele

```powershell
# 1. Offboarding - immer zuerst mit -WhatIf
Connect-MgGraph -Scopes User.ReadWrite.All, GroupMember.ReadWrite.All
Connect-ExchangeOnline -UserPrincipalName admin@contoso.com

Invoke-SDOffboarding -UserPrincipalName max.muster@contoso.com -WhatIf

# ... dann wirklich ausführen: Vorgesetzte erhält Zugriff, Absender bekommen eine Abwesenheitsnotiz
$result = Invoke-SDOffboarding -UserPrincipalName max.muster@contoso.com `
    -GrantFullAccessTo erika.chef@contoso.com `
    -AutoReplyMessage 'Herr Muster ist nicht mehr im Unternehmen. Bitte wenden Sie sich an info@contoso.com.' `
    -Confirm:$false
$result.Steps | Format-Table Step, Target, Status, Detail -AutoSize

# Mehrere Benutzer aus einer CSV-Datei (Spalte UserPrincipalName), nur Fehler anzeigen
Import-Csv .\austritte.csv | Invoke-SDOffboarding -Confirm:$false | Where-Object { -not $_.Succeeded }

# 2. Intune-Report für deutsches Excel (Semikolon)
Connect-MgGraph -Scopes DeviceManagementManagedDevices.Read.All, DeviceManagementConfiguration.Read.All
Get-SDIntuneNoncompliantReport -OutputDirectory C:\Reports -IncludePolicyDetails -Delimiter ';' -Verbose

# 3. Berechtigungsaudit aller freigegebenen Postfächer, nur verwaiste Einträge anzeigen
Get-SDMailboxPermissionAudit -RecipientTypeDetails SharedMailbox -OutputDirectory C:\Reports | Where-Object Orphaned
```

### Ablauf des Offboardings

1. **Sicherung:** Ein JSON-Snapshot mit Gruppen, Lizenzen und Postfachstatus wird geschrieben, bevor sich irgendetwas ändert (auch bei `-WhatIf`).
2. **Konto deaktivieren:** Aus dem lokalen AD synchronisierte Konten werden übersprungen, mit Hinweis, sie im AD zu deaktivieren.
3. **Sitzungen widerrufen**
4. **Postfach in eine Shared Mailbox umwandeln**, danach optional Vollzugriff, Weiterleitung und Abwesenheitsnotiz. Weiterleitungen an interne Empfänger werden als `ForwardingAddress` gesetzt, an externe Adressen als `ForwardingSmtpAddress`.
5. **Gruppen entfernen:** Sicherheits- und Microsoft-365-Gruppen per Graph, Verteilerlisten und E-Mail-aktivierte Sicherheitsgruppen per Exchange Online. Dynamische Gruppen, aus dem AD synchronisierte Gruppen und `-ExcludeGroupId` werden übersprungen. Verzeichnisrollen werden nur gemeldet, nie automatisch entfernt.
6. **Lizenzen entfernen**, und zwar nur die direkt zugewiesenen. Gruppenbasierte Lizenzen enden mit der Gruppenmitgliedschaft. Bei Litigation Hold oder aktivem Archiv erscheint eine Warnung, denn auch eine Shared Mailbox braucht dann eine Lizenz.

Scheitert Schritt 2 oder 3, bricht die Funktion ab. Fehler in späteren Schritten werden protokolliert und im Ergebnis als `Failed` markiert; die übrigen Schritte laufen weiter.

### Logs, Sicherungen und Datenschutz

- Log: `Log_yyyy-MM-dd.log` in `%LOCALAPPDATA%\ServiceDeskToolkit\Logs`. Abweichender Ordner über `-LogDirectory` oder `$env:SDTOOLKIT_LOG_DIR`.
- Laufzeit und Anzahl der verarbeiteten Objekte stehen am Ende jedes Laufs im Log.
- Logs, JSON-Sicherungen und Reports enthalten personenbezogene Daten (Namen, UPNs, Gruppen). Legen Sie sie nur an geschützten Orten ab und löschen Sie sie nach der Aufbewahrungsfrist (DSGVO).

### Tests und Qualität

```powershell
./scripts/Invoke-QualityGate.ps1 -InstallDependencies
```

- Pester 5: 137 Tests. Alle Graph- und Exchange-Cmdlets sind gemockt, es wird weder ein Tenant noch eine Anmeldung gebraucht.
- Die Contract-Tests prüfen die Stubs gegen die echten Module, sofern diese installiert sind (ohne Anmeldung).
- PSScriptAnalyzer mit `PSScriptAnalyzerSettings.psd1`: Jeder Fund lässt den Lauf scheitern.
- GitHub Actions (`.github/workflows/ci.yml`) testet mit PowerShell 7 unter Ubuntu und Windows sowie mit Windows PowerShell 5.1.

### Bekannte Grenzen

- Remote-Cmdlets von Exchange (`Set-Mailbox`, `Add-MailboxPermission`, `Set-MailboxAutoReplyConfiguration`, `Remove-DistributionGroupMember`) gibt es erst nach `Connect-ExchangeOnline`. Offline lassen sie sich deshalb nur über Mocks testen.
- Besitzerrechte an Gruppen, Teams, SharePoint und OneDrive werden nicht übertragen.
- Geräte des Benutzers werden nicht gesperrt oder gelöscht (Intune-Wipe bleibt bewusst manuell).

### Mehr Vorlagen

Antwortbausteine für Tickets, KB-Vorlagen und On-/Offboarding-Checklisten (Deutsch und Englisch, Word/PDF/CSV) gibt es als kostenpflichtiges Paket: [Service Desk Template Kit](https://warkentinartur.gumroad.com/l/bhulyv). Das Modul hier bleibt kostenlos und MIT-lizenziert.

### Lizenz

MIT, siehe [LICENSE](LICENSE). Autor: Artur Warkentin.

---

## English

### Purpose

Offboarding and permission reviews are still done by hand in many small and mid-sized companies. That is error-prone: sessions stay valid, licenses keep costing money, a distribution list gets forgotten. This module runs the steps in the same safe order every time. Every change can be previewed with `-WhatIf` and is logged.

| Function | Purpose | Changes anything? |
|---|---|---|
| `Invoke-SDOffboarding` | Offboard a user: disable, revoke sessions, convert mailbox to shared, optional FullAccess/forwarding/auto reply, remove groups and licenses | Yes (`-WhatIf`/`-Confirm`) |
| `Get-SDIntuneNoncompliantReport` | Non-compliant Intune devices as CSV and HTML, days since last check-in, optional failing policies | No |
| `Get-SDMailboxPermissionAudit` | Mailbox permissions (FullAccess, SendAs, SendOnBehalf) as CSV and HTML, flags permissions of deleted accounts | No |
| `Test-SDToolkit` | Offline self-test of the core logic | No |

### Requirements

- Windows PowerShell 5.1 or PowerShell 7.4+
- Modules (depending on the function):
  ```powershell
  Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Users.Actions, Microsoft.Graph.Groups, Microsoft.Graph.DeviceManagement -Scope CurrentUser
  Install-Module ExchangeOnlineManagement -Scope CurrentUser   # 3.x
  ```
  They are intentionally not listed as `RequiredModules`. Each function checks at startup that its modules are available and a connection exists, and prints the `Connect-*` command it needs otherwise.

### Required permissions

| Function | Microsoft Graph scopes | Role (delegated) |
|---|---|---|
| `Invoke-SDOffboarding` | `User.ReadWrite.All`, `GroupMember.ReadWrite.All` · least privilege: `User.Read.All`, `User.EnableDisableAccount.All`, `User.RevokeSessions.All`, `LicenseAssignment.ReadWrite.All`, `GroupMember.ReadWrite.All` | User Administrator, Groups Administrator, License Administrator; Exchange Recipient Administrator. For admin accounts: Privileged Authentication Administrator |
| `Get-SDIntuneNoncompliantReport` | `DeviceManagementManagedDevices.Read.All` (+ `DeviceManagementConfiguration.Read.All` for `-IncludePolicyDetails`) | Intune read role, e.g. Read Only Operator |
| `Get-SDMailboxPermissionAudit` | – (Exchange Online only) | View-Only Organization Management or Global Reader |

With the least-privilege set a start-up warning about the missing `User.ReadWrite.All` scope appears; it can be ignored.
For unattended (app-only) runs, grant the same scopes as application permissions. Exchange also needs `Exchange.ManageAsApp` plus a matching Entra role, with certificate-based sign-in. Never put secrets into scripts.

### Installation

From the [PowerShell Gallery](https://www.powershellgallery.com/packages/ServiceDeskToolkit):

```powershell
Install-PSResource ServiceDeskToolkit                    # PowerShell 7.4+ (PSResourceGet)
Install-Module ServiceDeskToolkit -Scope CurrentUser     # Windows PowerShell 5.1 (PowerShellGet)
Import-Module ServiceDeskToolkit
Test-SDToolkit
```

The Microsoft Graph and Exchange modules are not installed with it (see Requirements).

Local copy from the repository:

```powershell
git clone https://github.com/Ni0ri/ServiceDeskToolkit.git C:\Tools\ServiceDeskToolkit
Import-Module C:\Tools\ServiceDeskToolkit\ServiceDeskToolkit\ServiceDeskToolkit.psd1
Test-SDToolkit
Get-Help Invoke-SDOffboarding -Full
```

### Examples

```powershell
# 1. Offboarding - always start with -WhatIf
Connect-MgGraph -Scopes User.ReadWrite.All, GroupMember.ReadWrite.All
Connect-ExchangeOnline -UserPrincipalName admin@contoso.com

Invoke-SDOffboarding -UserPrincipalName max.muster@contoso.com -WhatIf

$result = Invoke-SDOffboarding -UserPrincipalName max.muster@contoso.com `
    -GrantFullAccessTo erika.chef@contoso.com -ForwardTo erika.chef@contoso.com -Confirm:$false
$result.Steps | Format-Table Step, Target, Status, Detail -AutoSize

# Entra ID steps only (user without mailbox)
Invoke-SDOffboarding -UserPrincipalName guest.worker@contoso.com -SkipMailbox -Confirm:$false

# 2. Intune report, stale devices on screen
Connect-MgGraph -Scopes DeviceManagementManagedDevices.Read.All
Get-SDIntuneNoncompliantReport -OperatingSystem Windows -StaleAfterDays 14 | Where-Object Stale

# 3. Permission audit for two mailboxes
'info@contoso.com', 'accounting@contoso.com' | Get-SDMailboxPermissionAudit -OutputDirectory C:\Reports
```

### Offboarding order

1. **Backup:** a JSON snapshot of groups, licenses and mailbox state is written before any change (even with `-WhatIf`).
2. **Disable account:** accounts synced from on-premises AD are skipped, with a hint to disable them in AD.
3. **Revoke sessions.**
4. **Convert the mailbox to shared**, then optional FullAccess, forwarding and auto reply. Internal forwarding targets are set as `ForwardingAddress`, external ones as `ForwardingSmtpAddress`.
5. **Remove groups:** security and Microsoft 365 groups via Graph, distribution lists and mail-enabled security groups via Exchange Online. Dynamic groups, on-premises synced groups and `-ExcludeGroupId` are skipped. Directory roles are reported, never removed automatically.
6. **Remove licenses**, direct assignments only. Group-based licenses end with the group membership. Litigation hold or an active archive triggers a warning, because the shared mailbox then still needs a license.

If step 2 or 3 fails, the function stops. Later failures are logged and marked `Failed` in the result, and the remaining steps still run.

### Logs, backups and privacy

- Log: `Log_yyyy-MM-dd.log` in `%LOCALAPPDATA%\ServiceDeskToolkit\Logs`. Override with `-LogDirectory` or `$env:SDTOOLKIT_LOG_DIR`.
- Logs, JSON backups and reports contain personal data (names, UPNs, groups). Store them in protected locations and delete them after your retention period (GDPR).

### Tests and quality

```powershell
./scripts/Invoke-QualityGate.ps1 -InstallDependencies
```

- Pester 5: 137 tests. All Graph and Exchange cmdlets are mocked, so no tenant or sign-in is needed.
- Contract tests compare the stubs with the real modules when they are installed (no sign-in).
- PSScriptAnalyzer with `PSScriptAnalyzerSettings.psd1`: any finding fails the run.
- GitHub Actions (`.github/workflows/ci.yml`): PowerShell 7 on Ubuntu and Windows, Windows PowerShell 5.1.

### Known limitations

- Exchange remote cmdlets (`Set-Mailbox`, `Add-MailboxPermission`, `Set-MailboxAutoReplyConfiguration`, `Remove-DistributionGroupMember`) only exist after `Connect-ExchangeOnline`, so offline they are covered by mocks only.
- Ownership of groups, Teams, SharePoint and OneDrive is not transferred.
- Devices of the user are not locked or wiped (Intune wipe is left as a deliberate manual step).

### More templates

Ticket response templates, KB article templates and on/offboarding checklists (English and German, Word/PDF/CSV) are available as a paid kit: [Service Desk Template Kit](https://warkentinartur.gumroad.com/l/bhulyv). This module stays free and MIT-licensed.

### License

MIT, see [LICENSE](LICENSE). Author: Artur Warkentin.
