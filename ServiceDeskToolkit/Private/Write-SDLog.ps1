function Write-SDLog {
    <#
    .SYNOPSIS
        Writes a timestamped log line (INFO/WARN/ERROR) to Log_yyyy-MM-dd.log and to the matching stream.
    .DESCRIPTION
        The log directory defaults to the module-wide setting. Public functions set it per call
        through $PSDefaultParameterValues['Write-SDLog:LogDirectory'].
        File writes use -WhatIf:$false so that a -WhatIf run is still fully logged.
        A log file that cannot be written only produces a warning; it never stops the calling task.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter(Position = 1)]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO',

        [string]$LogDirectory = $script:SDLogDirectory
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message

    if ($Level -eq 'WARN') {
        Write-Warning -Message $Message
    }
    else {
        Write-Verbose -Message $line
    }

    if (-not $LogDirectory) { return }

    try {
        if (-not (Test-Path -LiteralPath $LogDirectory)) {
            $null = New-Item -Path $LogDirectory -ItemType Directory -Force -WhatIf:$false -Confirm:$false -ErrorAction Stop
        }
        $logFile = Join-Path -Path $LogDirectory -ChildPath ('Log_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd'))
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 -WhatIf:$false -Confirm:$false -ErrorAction Stop
    }
    catch {
        Write-Warning -Message ("Could not write log file in '{0}': {1}" -f $LogDirectory, $_.Exception.Message)
    }
}
