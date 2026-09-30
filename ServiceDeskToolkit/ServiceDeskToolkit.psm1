#Requires -Version 5.1
<#
    ServiceDeskToolkit - root module.
    Loads private helpers first, then public functions, and exports only the public ones.
#>

Set-StrictMode -Version 3.0

# Default log directory. Log files are named Log_yyyy-MM-dd.log.
# Can be overridden per call (-LogDirectory) or per session ($env:SDTOOLKIT_LOG_DIR).
$script:SDLogDirectory = if ($env:SDTOOLKIT_LOG_DIR) {
    $env:SDTOOLKIT_LOG_DIR
}
else {
    $base = [Environment]::GetFolderPath('LocalApplicationData')
    if (-not $base) { $base = [IO.Path]::GetTempPath() }
    Join-Path -Path (Join-Path -Path $base -ChildPath 'ServiceDeskToolkit') -ChildPath 'Logs'
}

$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$public = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in @($private + $public)) {
    try {
        . $file.FullName
    }
    catch {
        throw "ServiceDeskToolkit: failed to load '$($file.FullName)': $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function $public.BaseName
