#Requires -Version 5.1
<#
.SYNOPSIS
    Applies the VS Code "dotfiles" in this folder: installs the extension list
    and links settings.json into VS Code's user profile.

.DESCRIPTION
    1. Resolves the `code` CLI (PATH, then the usual per-user install location).
    2. Installs every extension listed in extensions.txt (one id per line,
       "#" lines and blank lines are skipped).
    3. Backs up any existing %APPDATA%\Code\User\settings.json, then links this
       folder's settings.json into place - as a symlink when possible, so
       further edits to the tracked file take effect immediately; falls back
       to a plain copy if symlink creation isn't permitted (no Developer Mode /
       not elevated).

    Run after VS Code itself is installed (see ..\bootstrap.ps1):
        .\install.ps1

.NOTES
    Re-run any time after editing extensions.txt or settings.json to pick up
    changes - it's idempotent (already-installed extensions are skipped by
    `code --install-extension`; the settings link is just replaced).
#>

[CmdletBinding()]
param(
    [string]$ExtensionsFile = (Join-Path $PSScriptRoot 'extensions.txt'),
    [string]$SettingsFile = (Join-Path $PSScriptRoot 'settings.json')
)

$ErrorActionPreference = 'Stop'

function Resolve-CodeCli {
    $cmd = Get-Command code.cmd -ErrorAction SilentlyContinue
    if (-not $cmd) { $cmd = Get-Command code -ErrorAction SilentlyContinue }
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'),
        (Join-Path ${env:ProgramFiles} 'Microsoft VS Code\bin\code.cmd')
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

function Get-ExtensionIds {
    param([string]$Path)

    Get-Content -Path $Path |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') }
}

Write-Host '==> Checking for the VS Code CLI (code)...' -ForegroundColor Cyan
$code = Resolve-CodeCli

if (-not $code) {
    Write-Warning "VS Code CLI not found. Install VS Code first (see ..\bootstrap.ps1), or in VS Code run 'Shell Command: Install code command in PATH' from the Command Palette, then re-run this script."
    exit 1
}
Write-Host "    Found: $code" -ForegroundColor Green

# --- Extensions --------------------------------------------------------------
if (-not (Test-Path $ExtensionsFile)) {
    Write-Error "Extensions file not found: $ExtensionsFile"
    exit 1
}

$ids = Get-ExtensionIds -Path $ExtensionsFile
Write-Host "==> Installing $($ids.Count) extensions..." -ForegroundColor Cyan

$failed = @()
foreach ($id in $ids) {
    Write-Host "---> $id" -ForegroundColor Cyan
    & $code --install-extension $id --force
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "     $id returned exit code $LASTEXITCODE."
        $failed += $id
    } else {
        Write-Host '     OK.' -ForegroundColor Green
    }
}

# --- settings.json ------------------------------------------------------------
if (-not (Test-Path $SettingsFile)) {
    Write-Error "Settings file not found: $SettingsFile"
    exit 1
}

$userDir = Join-Path $env:APPDATA 'Code\User'
$target = Join-Path $userDir 'settings.json'

Write-Host "==> Applying settings.json to $target" -ForegroundColor Cyan
New-Item -ItemType Directory -Path $userDir -Force | Out-Null

if (Test-Path $target) {
    $existingItem = Get-Item $target -Force
    $isOurSymlink = $existingItem.LinkType -and ($existingItem.Target -contains $SettingsFile -or $existingItem.Target -eq $SettingsFile)
    if (-not $isOurSymlink) {
        $backup = "$target.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Write-Host "    Existing settings.json found - backing up to $backup" -ForegroundColor Yellow
        Copy-Item -Path $target -Destination $backup -Force
    }
    Remove-Item -Path $target -Force
}

try {
    New-Item -ItemType SymbolicLink -Path $target -Target $SettingsFile -ErrorAction Stop | Out-Null
    Write-Host '    Linked (symlink) - edits to vscode\settings.json take effect immediately.' -ForegroundColor Green
} catch {
    Write-Host '    Symlink creation failed (needs Developer Mode or admin) - copying instead.' -ForegroundColor Yellow
    Write-Host '    Re-run this script after editing vscode\settings.json to re-apply.' -ForegroundColor DarkGray
    Copy-Item -Path $SettingsFile -Destination $target -Force
}

Write-Host ''
if ($failed.Count -gt 0) {
    Write-Warning "Done, but $($failed.Count) extension(s) need attention:"
    $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    exit 1
} else {
    Write-Host '==> VS Code profile applied successfully.' -ForegroundColor Green
    exit 0
}
