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
    3. Installs the Spring Boot CLI (`spring init`) by downloading its official
       bin.zip from Maven Central and adding it to PATH - no winget package
       exists for it.
    4. Reads the package ids out of configuration.dsc.yaml and installs each one
       with a plain `winget install` call.
    5. Prints the remaining one-time manual steps (JDK via jabba, Rust default
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
    # toolchain installed some other way). Auto-skipped for profiles that don't
    # need a C++ toolchain, unless explicitly overridden.
    [switch]$SkipBuildTools,

    # Skip installing the Spring Boot CLI (gives you `spring init` to scaffold
    # Java/Kotlin projects from the terminal). Auto-skipped for profiles that
    # don't need it, unless explicitly overridden.
    [switch]$SkipSpringCli,

    # Spring Boot CLI version to install. Keep in sync with the Spring Boot
    # version used elsewhere (see README's compatibility notes) - pin it
    # deliberately rather than always grabbing "latest".
    [string]$SpringCliVersion = '3.5.16',

    # Use `winget configure` (DSC) instead of the default plain-install loop.
    # Requires `winget configure --enable` to have been run once, as admin.
    # Not compatible with -Profile (other than 'all').
    [switch]$UseConfiguration,

    # Install only a named subset of configuration.dsc.yaml instead of
    # everything. 'all' (default) installs the full file.
    [ValidateSet('all', 'java-kotlin', 'utilities')]
    [string]$Profile = 'all'
)

$ErrorActionPreference = 'Stop'

# Named subsets of configuration.dsc.yaml for scoped runs. Keep ids in sync
# with configuration.dsc.yaml by hand - this is a small, deliberately curated
# list per profile, not a derived filter.
$script:Profiles = @{
    'java-kotlin' = @(
        'Git.Git',                       # version control
        'GitHub.cli',                    # create/manage PRs and issues from the terminal
        'Microsoft.VisualStudioCode',    # editor (see vscode/ for the dotfiles)
        'jabba-team.jabba',              # JDK/JVM version manager
        'Podman.CLI',                    # run PostgreSQL via container
        'DBeaver.DBeaver.Community',     # PostgreSQL client/GUI
        'Bruno.Bruno'                    # API client for testing Spring Boot endpoints
    )
    'utilities' = @(
        'Microsoft.VisualStudioCode',    # editor (see vscode/ for the dotfiles)
        'DBeaver.DBeaver.Community',     # universal DB client
        'Bruno.Bruno'                    # API client
    )
}

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

if ($UseConfiguration -and $Profile -ne 'all') {
    Write-Error "-Profile '$Profile' is not supported together with -UseConfiguration (which always applies the whole file). Drop -UseConfiguration, or use -Profile all."
    exit 1
}

# None of the non-'all' profiles need a C++ toolchain today.
# Auto-skip Build Tools unless the caller explicitly asked for a value.
if ($Profile -ne 'all' -and -not $PSBoundParameters.ContainsKey('SkipBuildTools')) {
    $SkipBuildTools = $true
}

# Only 'all' and 'java-kotlin' do Java/Kotlin work. Auto-skip the Spring Boot
# CLI for 'utilities' unless the caller explicitly asked for a value.
if ($Profile -eq 'utilities' -and -not $PSBoundParameters.ContainsKey('SkipSpringCli')) {
    $SkipSpringCli = $true
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

# --- Spring Boot CLI (`spring init` from the terminal) ----------------------
# No winget package exists for this, so it's installed the same way the
# official docs describe for Windows without SDKMAN/Scoop: download the
# official bin.zip from Maven Central, extract it, and add its bin/ to PATH.
# Gives you `spring init -l=kotlin -d=web --build=gradle my-app` (or -l=java)
# to scaffold a project without opening a browser to start.spring.io.
if (-not $SkipSpringCli) {
    Write-Host "==> Installing Spring Boot CLI $SpringCliVersion (spring init)..." -ForegroundColor Cyan
    Write-Host '    (skip with -SkipSpringCli)' -ForegroundColor DarkGray

    $springInstallRoot = Join-Path $HOME '.spring-boot-cli'
    $springVersionDir = Join-Path $springInstallRoot "spring-boot-cli-$SpringCliVersion"
    $springBat = Get-ChildItem -Path $springVersionDir -Filter 'spring.bat' -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($springBat) {
        Write-Host "    Already installed at $($springBat.DirectoryName)." -ForegroundColor Green
    } else {
        $zipUrl = "https://repo1.maven.org/maven2/org/springframework/boot/spring-boot-cli/$SpringCliVersion/spring-boot-cli-$SpringCliVersion-bin.zip"
        $zipPath = Join-Path $env:TEMP "spring-boot-cli-$SpringCliVersion-bin.zip"

        try {
            Write-Host "    Downloading $zipUrl" -ForegroundColor DarkGray
            Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing

            New-Item -ItemType Directory -Force -Path $springVersionDir | Out-Null
            Expand-Archive -Path $zipPath -DestinationPath $springVersionDir -Force
            Remove-Item $zipPath -Force

            $springBat = Get-ChildItem -Path $springVersionDir -Filter 'spring.bat' -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if (-not $springBat) {
                throw "spring.bat not found after extracting - archive layout may have changed."
            }
            Write-Host "    OK. Installed to $($springBat.DirectoryName)." -ForegroundColor Green
        } catch {
            Write-Warning "    Spring Boot CLI install failed: $_. Continuing anyway - review the output above."
            $springBat = $null
        }
    }

    if ($springBat) {
        $springBinPath = $springBat.DirectoryName
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $pathEntries = $userPath -split ';' | Where-Object { $_ }

        if ($pathEntries -notcontains $springBinPath) {
            # Drop any bin/ dir from an older spring-boot-cli version first, so
            # re-running this after a version bump doesn't leave two on PATH.
            $pathEntries = $pathEntries | Where-Object { $_ -notlike (Join-Path $springInstallRoot '*\bin') }
            $newPath = ($pathEntries + $springBinPath) -join ';'
            [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
            Write-Host "    Added $springBinPath to your User PATH (open a new terminal to pick it up)." -ForegroundColor Green
        }
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
    if ($Profile -eq 'all') {
        $ids = Get-PackageIdsFromConfig -Path $ConfigFile
    } else {
        $ids = $script:Profiles[$Profile]
    }

    if (-not $ids -or $ids.Count -eq 0) {
        Write-Warning "No package ids found for profile '$Profile' - nothing to install."
    } else {
        if ($Profile -eq 'all') {
            Write-Host "==> Installing $($ids.Count) packages from $ConfigFile" -ForegroundColor Cyan
        } else {
            Write-Host "==> Profile '$Profile': installing $($ids.Count) packages (subset of $ConfigFile)" -ForegroundColor Cyan
        }
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
Write-Host '         jabba install temurin@21          # recommended default - see README'
Write-Host '         jabba use temurin@21'
Write-Host '         jabba alias default temurin@21'
Write-Host '       Temurin 21 (LTS), not the newest LTS, is the recommended default: Kotlin,'
Write-Host '       the AWS SDK and most Gradle plugins validate against it first. See the'
Write-Host '       "Java/Kotlin + Spring Boot project checklist" section in README.md before'
Write-Host '       picking a newer JDK as default.'
Write-Host '       Verify it actually took in a NEW terminal: $env:JAVA_HOME. On this image,'
Write-Host '       jabba''s PowerShell integration can silently fail to persist the switch -'
Write-Host '       see "jabba use does not stick" in README.md if $env:JAVA_HOME is unchanged.'
Write-Host '    3) Scaffold a Java or Kotlin project from the terminal with the Spring Boot CLI:'
Write-Host '         spring init -l=kotlin -d=web --build=gradle my-app   # or -l=java'
Write-Host '    4) Set the default Rust toolchain:'
Write-Host '         rustup default stable-msvc'
Write-Host '    5) Provision the Podman container engine (one-time, CLI only):'
Write-Host '         podman machine init'
Write-Host '         podman machine start'
Write-Host '    6) Sign in: Claude, Claude Code, Antigravity IDE/CLI, Spotify, DBeaver connections.'

exit $exit
