function ConvertTo-SDStepResult {
    <#
    .SYNOPSIS
        Builds one step record for an offboarding result.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Step,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Done', 'WhatIf', 'Skipped', 'NoChange', 'Failed')]
        [string]$Status,
        [string]$Detail = ''
    )

    [pscustomobject]@{
        PSTypeName = 'ServiceDeskToolkit.StepResult'
        Step       = $Step
        Target     = $Target
        Status     = $Status
        Detail     = $Detail
    }
}

function Invoke-SDStep {
    <#
    .SYNOPSIS
        Runs one change step (already approved by ShouldProcess), logs it and returns a step record.
    .DESCRIPTION
        The action script block should return a short description of what it did.
        On failure the error is logged. Critical steps rethrow the error, all other
        steps return a 'Failed' record so the remaining steps can still run.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$StepName,
        [Parameter(Mandatory = $true)][string]$StepTarget,
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [switch]$Critical
    )

    try {
        $stepOutput = & $Action
        $stepDetail = (@($stepOutput) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ }) -join '; '
        Write-SDLog -Message ('[{0}] {1}: {2}' -f $StepName, $StepTarget, $stepDetail)
        ConvertTo-SDStepResult -Step $StepName -Target $StepTarget -Status Done -Detail $stepDetail
    }
    catch {
        Write-SDLog -Level ERROR -Message ('[{0}] {1} failed: {2}' -f $StepName, $StepTarget, $_.Exception.Message)
        if ($Critical) { throw }
        ConvertTo-SDStepResult -Step $StepName -Target $StepTarget -Status Failed -Detail $_.Exception.Message
    }
}
