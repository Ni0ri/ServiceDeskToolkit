# Veröffentlichen in der PowerShell Gallery

Kurzanleitung für Artur. Der Modulname `ServiceDeskToolkit` war am 01.10.2026 in der Gallery noch frei.
PowerShell 7 liegt lokal unter `~/.local/opt/powershell` und ist als `pwsh` (`~/.local/bin/pwsh`) aufrufbar.

## a) Konto und API-Key anlegen

1. <https://www.powershellgallery.com> öffnen, oben rechts **Sign in** und mit einem Microsoft-Konto anmelden. Beim ersten Mal einen Benutzernamen wählen (er wird als Owner des Pakets angezeigt).
2. Oben rechts auf den Benutzernamen, dann **API Keys** und **Create**:
   - **Key Name:** `ServiceDeskToolkit-publish`
   - **Expires In:** 365 days
   - **Select Scopes:** nur *Push new packages and package versions*
   - **Select Packages / Glob Pattern:** `ServiceDeskToolkit` (genau dieser Name, kein `*`)
3. **Create** und den Key mit **Copy** kopieren. Er wird nur einmal angezeigt.

## b) Key ablegen (selbst, nie im Chat)

Im eigenen Terminal ausführen, nicht über Claude und nicht mit dem `!`-Präfix in einer Claude-Session.
Der Key wird verdeckt eingegeben und landet nicht in der Shell-History:

```bash
mkdir -p ~/.config/psgallery && chmod 700 ~/.config/psgallery
(umask 077; read -rsp 'API-Key: ' k; echo; printf '%s\n' "$k" > ~/.config/psgallery/key; unset k)
chmod 600 ~/.config/psgallery/key
```

Läuft der Key ab oder ist er womöglich bekannt geworden: in der Gallery unter **API Keys** neu erzeugen (*Regenerate*) bzw. löschen und die Datei überschreiben.

## c) Veröffentlichen

Vorher: Tests grün (`pwsh ./scripts/Invoke-QualityGate.ps1`) und den Commit mit README/CHANGELOG pushen, damit die Projektseite zur Gallery-Version passt. Dann genau dieser eine Befehl:

```bash
cd ~/code/ServiceDeskToolkit && pwsh -NoProfile -Command 'Publish-PSResource -Path ./ServiceDeskToolkit -Repository PSGallery -ApiKey (Get-Content -Raw ~/.config/psgallery/key).Trim()'
```

Der Key wird erst in PowerShell aus der Datei gelesen und steht deshalb weder in der History noch in der Prozessliste.

Danach dauert die Prüfung durch die Gallery einige Minuten. Kontrolle: <https://www.powershellgallery.com/packages/ServiceDeskToolkit> bzw. `pwsh -c 'Find-PSResource ServiceDeskToolkit -Repository PSGallery'`.

Wichtig: Eine veröffentlichte Version lässt sich nicht löschen, nur verstecken (*Unlist*). Jede weitere Veröffentlichung braucht eine neue `ModuleVersion` in `ServiceDeskToolkit/ServiceDeskToolkit.psd1` plus Eintrag in `ReleaseNotes` und `CHANGELOG.md`.

## Lokaler Trockenlauf (ohne Gallery, mit Dummy-Key)

So wurde der Befehl getestet: gleiche Befehlsform, aber mit einem Dummy-Key in einem Wegwerf-`HOME` und einem lokalen Ordner als Repository statt `PSGallery`.

```bash
T=$(mktemp -d); mkdir -p "$T/.config/psgallery" "$T/repo"
printf 'dummy-key\n' > "$T/.config/psgallery/key"; chmod 600 "$T/.config/psgallery/key"
HOME=$T pwsh -NoProfile -Command "Register-PSResourceRepository -Name SDTLocal -Uri '$T/repo' -Trusted"
cd ~/code/ServiceDeskToolkit && HOME=$T pwsh -NoProfile -Command 'Publish-PSResource -Path ./ServiceDeskToolkit -Repository SDTLocal -ApiKey (Get-Content -Raw ~/.config/psgallery/key).Trim()'
HOME=$T pwsh -NoProfile -Command 'Install-PSResource ServiceDeskToolkit -Repository SDTLocal; Import-Module ServiceDeskToolkit; Get-Command -Module ServiceDeskToolkit; (Test-SDToolkit).Summary'
rm -rf "$T"
```

Ergebnis am 01.10.2026: `ServiceDeskToolkit.1.0.0.nupkg` erzeugt (nur Modulordner, keine Abhängigkeiten im nuspec), Installation und Import ok, 4 Funktionen exportiert, `Test-SDToolkit`: 13/13.
