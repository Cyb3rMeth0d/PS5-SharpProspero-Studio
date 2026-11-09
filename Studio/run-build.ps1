#requires -Version 5.1
param(
    [Parameter(Mandatory = $true)][string]$SdkRoot,
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][ValidateSet("Package", "Folder")][string]$Output,
    [Parameter(Mandatory = $true)][string]$ExitCodePath,
    [string]$TitleId = "",
    [string]$ModulesPath = ""
)

$ErrorActionPreference = "Stop"
$exitCode = 0

try {
    if ($TitleId) { Write-Output "Title ID asignado: $TitleId" }
    if ($ModulesPath) {
        $env:PROSPERO_MODULES = $ModulesPath
        Write-Output "Carpeta de modulos configurada: $ModulesPath"
    } elseif (Test-Path Env:\PROSPERO_MODULES) {
        Remove-Item Env:\PROSPERO_MODULES
    }
    & (Join-Path $SdkRoot "build\build-app.ps1") `
        -ProjectPath $ProjectPath `
        -Output $Output `
        -Configuration "Release" `
        -SystemVersionPolicy "Match" `
        -SdkRoot $SdkRoot `
        -TitleId $TitleId
} catch {
    [Console]::Error.WriteLine($_.ToString())
    $exitCode = 1
} finally {
    [System.IO.File]::WriteAllText($ExitCodePath, [string]$exitCode)
}

exit $exitCode
