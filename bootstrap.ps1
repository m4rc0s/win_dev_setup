#Requires -Version 5.1
<#
.SYNOPSIS
    Replicates the dev setup by applying the declarative configuration (winget DSC).

.DESCRIPTION
    1. Checks that winget is available (ships with "App Installer" on Windows 11).
    2. Ensures winget's Configuration feature is enabled (requires admin the first time).
    3. Applies configuration.dsc.yaml via `winget configure`.

    Run from the project folder:
        .\bootstrap.ps1

    Tip: some packages require elevation; winget triggers the UAC prompt when needed.

.NOTES
    You don't need to edit this file. The program list lives in configuration.dsc.yaml.
#>

[CmdletBinding()]
param(
    # Path to the configuration file (default: next to this script).
    [string]$ConfigFile = (Join-Path $PSScriptRoot 'configuration.dsc.yaml')
)

$ErrorActionPreference = 'Stop'

function Resolve-Winget {
    # Try PATH first; otherwise fall back to the known App Installer path.
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $fallback = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path $fallback) { return $fallback }

    return $null
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

Write-Host '==> Checking winget...' -ForegroundColor Cyan
$winget = Resolve-Winget

if (-not $winget) {
    Write-Warning 'winget not found.'
    Write-Host 'Install "App Installer" from the Microsoft Store and run again:' -ForegroundColor Yellow
    Write-Host '  https://aka.ms/getwinget' -ForegroundColor Yellow
    exit 1
}

$version = (& $winget --version).Trim()
Write-Host "    winget OK ($version) at: $winget" -ForegroundColor Green

if (-not (Test-Path $ConfigFile)) {
    Write-Error "Configuration file not found: $ConfigFile"
    exit 1
}

# The Configuration feature is off by default and must be enabled once (requires
# admin). We validate the file to detect this.
Write-Host '==> Checking whether the Configuration feature is enabled...' -ForegroundColor Cyan
$validate = & $winget configure validate --file $ConfigFile 2>&1 | Out-String
if ($validate -match 'Extended features are not enabled') {
    Write-Host '    Feature is off. Enabling (winget configure --enable)...' -ForegroundColor Yellow
    if (Test-Admin) {
        & $winget configure --enable
    } else {
        Write-Warning 'This requires Administrator privileges.'
        Write-Host 'Open PowerShell AS ADMINISTRATOR and run once:' -ForegroundColor Yellow
        Write-Host '  winget configure --enable' -ForegroundColor Yellow
        Write-Host 'Then run .\bootstrap.ps1 normally.' -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host '    OK.' -ForegroundColor Green
}

Write-Host "==> Applying configuration: $ConfigFile" -ForegroundColor Cyan
Write-Host '    (this may take a while and prompt for UAC per package)' -ForegroundColor DarkGray

& $winget configure `
    --file $ConfigFile `
    --accept-configuration-agreements `
    --disable-interactivity

$exit = $LASTEXITCODE
if ($exit -eq 0) {
    Write-Host '==> Setup completed successfully.' -ForegroundColor Green
} else {
    Write-Warning "winget configure returned exit code $exit. Review the output above."
}
exit $exit
