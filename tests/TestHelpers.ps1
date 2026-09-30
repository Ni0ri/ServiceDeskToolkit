# Shared setup for all test files: stubs for external cmdlets and a fresh module import.
. (Join-Path $PSScriptRoot 'Stubs/ExternalCommands.ps1')

$manifestPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'ServiceDeskToolkit/ServiceDeskToolkit.psd1'
Get-Module ServiceDeskToolkit | Remove-Module -Force
Import-Module $manifestPath -Force -ErrorAction Stop

function New-TestGraphDictionary {
    param([hashtable]$Values)
    $dictionary = New-Object -TypeName 'System.Collections.Generic.Dictionary[string,object]'
    foreach ($key in $Values.Keys) { $dictionary[$key] = $Values[$key] }
    , $dictionary
}

function New-TestGraphGroup {
    param(
        [string]$Id,
        [string]$Name,
        [string[]]$GroupTypes = @(),
        [bool]$MailEnabled = $false,
        [string]$Mail = $null,
        [bool]$OnPremisesSyncEnabled = $false
    )
    # The Graph SDK returns AdditionalProperties as Dictionary[string,object], not as Hashtable.
    [pscustomobject]@{
        Id                   = $Id
        AdditionalProperties = New-TestGraphDictionary @{
            '@odata.type'         = '#microsoft.graph.group'
            displayName           = $Name
            groupTypes            = $GroupTypes
            mailEnabled           = $MailEnabled
            mail                  = $Mail
            securityEnabled       = -not $MailEnabled
            onPremisesSyncEnabled = $OnPremisesSyncEnabled
        }
    }
}
