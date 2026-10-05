#Requires -Version 5.1
<#
.SYNOPSIS
    Replicates the dev setup by applying the declarative configuration (winget DSC).

.DESCRIPTION
    1. Checks that winget is available (ships with "App Installer" on Windows 11).
    2. Ensures winget's Configuration feature is enabled (requires admin the first time).
    3. Installs Visual Studio 2022 Build Tools with the C++ workload (prerequisite
       for the Rust MSVC toolchain and native Python extensions) - this needs
       installer override arguments that the declarative file cannot express.
    4. Applies configuration.dsc.yaml via `winget configure` (everything else).
    5. Prints the remaining one-time manual steps (JDK via jabba, Rust default
       toolchain, container engines first run).

    Run from the project folder:
        .\bootstrap.ps1

    Tip: some packages require elevation; winget triggers the UAC prompt when needed.

.NOTES
    You don't need to edit this file. The program list lives in configuration.dsc.yaml.
#>

[CmdletBinding()]
param(
    # Path to the configuration file (default: next to this script).
    [string]$ConfigFile = (Join-Path $PSScriptRoot 'configuration.dsc.yaml'),

    # Skip the Visual Studio Build Tools step (e.g. if you already have a C++
    # toolchain installed some other way).
    [switch]$SkipBuildTools
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

# --- Visual Studio 2022 Build Tools (C++ workload) --------------------------
# Needed for: the Rust MSVC toolchain (link.exe) and compiling native Python
# extensions. Installed as a direct `winget install` call (not via the DSC
# file) because selecting the workload requires installer override arguments.
if (-not $SkipBuildTools) {
    Write-Host '==> Installing Visual Studio 2022 Build Tools (C++ workload)...' -ForegroundColor Cyan
    Write-Host '    (skip with -SkipBuildTools if you already have a C++ toolchain)' -ForegroundColor DarkGray

    & $winget install `
        --id Microsoft.VisualStudio.2022.BuildTools `
        --source winget `
        --accept-package-agreements `
        --accept-source-agreements `
        --disable-interactivity `
        --override '--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'

    $btExit = $LASTEXITCODE
    # -1978335189 (0x8A150013) = "no applicable update found" - already installed.
    if ($btExit -eq 0 -or $btExit -eq -1978335189) {
        Write-Host '    OK.' -ForegroundColor Green
    } else {
        Write-Warning "Build Tools install returned exit code $btExit. Continuing anyway - review the output above."
    }
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

Write-Host ''
Write-Host '==> One-time manual steps still needed:' -ForegroundColor Cyan
Write-Host '    1) Open a NEW terminal (so updated PATH entries take effect).'
Write-Host '    2) Install a JDK and set it as default with jabba:'
Write-Host '         jabba ls-remote                  # list available JDKs'
Write-Host '         jabba install temurin@21          # example: Temurin 21 LTS'
Write-Host '         jabba use temurin@21'
Write-Host '         jabba alias default temurin@21'
Write-Host '    3) Set the default Rust toolchain:'
Write-Host '         rustup default stable-msvc'
Write-Host '    4) Launch Docker Desktop and/or Podman Desktop once to finish their'
Write-Host '       first-run setup (they provision their own Windows container backend).'
Write-Host '    5) Sign in: Claude, Claude Code, Antigravity IDE/CLI, Spotify, DBeaver connections.'

exit $exit
