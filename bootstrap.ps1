#Requires -Version 5.1
<#
.SYNOPSIS
    Replicates the dev setup by installing every package listed in
    configuration.dsc.yaml, plus the one prerequisite that file can't express.

.DESCRIPTION
    1. Checks that winget is available (ships with "App Installer" on Windows 11).
    2. Installs Visual Studio 2022 Build Tools with the C++ workload (prerequisite
       for the Rust MSVC toolchain and native Python extensions) - this needs
       installer override arguments that the declarative file cannot express.
    3. Reads the package ids out of configuration.dsc.yaml and installs each one
       with a plain `winget install` call.
    4. Prints the remaining one-time manual steps (JDK via jabba, Rust default
       toolchain, container engines first run).

    Run from the project folder:
        .\bootstrap.ps1

    Tip: some packages require elevation; winget triggers the UAC prompt when
    needed for that one package - you don't need to run this whole script
    elevated.

.NOTES
    You don't need to edit this file. The program list lives in configuration.dsc.yaml;
    this script extracts package ids from it with a regex, so there's no YAML parser
    dependency and no duplicated list to keep in sync.

    Why not `winget configure -f configuration.dsc.yaml`? That subcommand requires
    enabling an experimental "Configuration" feature once via `winget configure
    --enable`, which itself requires Administrator rights - and in practice the
    elevated PowerShell window winget needs that run in can end up resolving a
    different user context (no winget.exe on PATH there) depending on how it was
    opened. Plain `winget install` has never needed that flag, so this script uses
    it as the default, reliable path. Pass -UseConfiguration to use the DSC engine
    instead, if you've already enabled it and prefer that.
#>

[CmdletBinding()]
param(
    # Path to the configuration file (default: next to this script).
    [string]$ConfigFile = (Join-Path $PSScriptRoot 'configuration.dsc.yaml'),

    # Skip the Visual Studio Build Tools step (e.g. if you already have a C++
    # toolchain installed some other way).
    [switch]$SkipBuildTools,

    # Use `winget configure` (DSC) instead of the default plain-install loop.
    # Requires `winget configure --enable` to have been run once, as admin.
    [switch]$UseConfiguration
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

function Get-PackageIdsFromConfig {
    param([string]$Path)

    $text = Get-Content -Path $Path -Raw
    # Matches the "settings:\n  id: X\n  source: winget" blocks emitted by each
    # active (non-commented) resource. The commented-out SUGGESTIONS section uses
    # a different one-line "{ id: ..., source: winget }" style, so it's naturally
    # excluded.
    $pattern = '(?m)^\s*settings:\s*\r?\n\s*id:\s*(\S+)\s*\r?\n\s*source:\s*winget'
    [regex]::Matches($text, $pattern) | ForEach-Object { $_.Groups[1].Value }
}

# Exit codes that mean "nothing to do" / "already installed" - treat as success.
$script:BenignExitCodes = @(
    0,
    -1978335189,  # 0x8A150013 APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE (no newer version)
    -1978335212   # 0x8A1500F4 APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED
)

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

    if ($script:BenignExitCodes -contains $LASTEXITCODE) {
        Write-Host '    OK.' -ForegroundColor Green
    } else {
        Write-Warning "Build Tools install returned exit code $LASTEXITCODE. Continuing anyway - review the output above."
    }
}

$exit = 0

if ($UseConfiguration) {
    # --- DSC path (opt-in) ---------------------------------------------------
    Write-Host "==> Applying configuration via 'winget configure': $ConfigFile" -ForegroundColor Cyan
    Write-Host '    (requires the Configuration feature to already be enabled - see NOTES)' -ForegroundColor DarkGray

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
} else {
    # --- Default path: plain install loop, no feature flag required ---------
    $ids = Get-PackageIdsFromConfig -Path $ConfigFile

    if (-not $ids -or $ids.Count -eq 0) {
        Write-Warning "No package ids found in $ConfigFile - nothing to install."
    } else {
        Write-Host "==> Installing $($ids.Count) packages from $ConfigFile" -ForegroundColor Cyan
        Write-Host '    (winget will show its own UAC prompt per package if one needs elevation)' -ForegroundColor DarkGray

        $failed = @()
        foreach ($id in $ids) {
            Write-Host "---> $id" -ForegroundColor Cyan

            & $winget install `
                --id $id `
                --source winget `
                --accept-package-agreements `
                --accept-source-agreements `
                --disable-interactivity

            if ($script:BenignExitCodes -contains $LASTEXITCODE) {
                Write-Host "     OK." -ForegroundColor Green
            } else {
                Write-Warning "     $id returned exit code $LASTEXITCODE."
                $failed += $id
            }
        }

        if ($failed.Count -gt 0) {
            $exit = 1
            Write-Host ''
            Write-Warning "Setup finished with $($failed.Count) package(s) that need attention:"
            $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
        } else {
            Write-Host ''
            Write-Host '==> Setup completed successfully.' -ForegroundColor Green
        }
    }
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
Write-Host '    4) Provision the Podman container engine (one-time, CLI only):'
Write-Host '         podman machine init'
Write-Host '         podman machine start'
Write-Host '    5) Sign in: Claude, Claude Code, Antigravity IDE/CLI, Spotify, DBeaver connections.'

exit $exit
