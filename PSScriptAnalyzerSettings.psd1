@{
    # Used locally (scripts/Invoke-QualityGate.ps1) and in CI. Every finding fails the build.
    Severity     = @('Error', 'Warning', 'Information')
    IncludeDefaultRules = $true
    ExcludeRules = @()
    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.4')
        }
        PSPlaceOpenBrace      = @{ Enable = $true; OnSameLine = $true; NewLineAfter = $true; IgnoreOneLineBlock = $true }
        PSUseConsistentIndentation = @{ Enable = $true; IndentationSize = 4; Kind = 'space' }
    }
}
