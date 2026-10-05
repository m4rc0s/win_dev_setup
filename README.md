# My Dev Setup (Windows)

A **declarative and reproducible** configuration of my Windows 11 development
environment. The idea is simple: one command and the machine ends up exactly the way
I want it — on a brand-new machine, after a reinstall, or just to keep everything
consistent.

It uses **[winget](https://learn.microsoft.com/windows/package-manager/)** (the official
Windows package manager) with **Configuration / DSC**: you describe *what* you want
installed, and winget figures out *how* to reach that state. Most of the toolchain runs
**natively on Windows** — no WSL needed to write or run code day-to-day. **WSL2 is a
required dependency of this setup**, though: containers run through Podman, not Docker
Desktop (see [Notes on a couple of choices](#-notes-on-a-couple-of-choices)), and
Podman's Linux VM needs a backend to run on Windows — that's WSL2. Optionally, WSL2 is
also used for SDKMAN-based JDK management on the Linux side — see
[WSL2](#-wsl2-required-for-podman) below.

---

## 📦 What's in this folder

| File | Purpose |
|---|---|
| `configuration.dsc.yaml` | **The heart of the setup.** Declarative list of every program (the machine's desired state). This is the file you edit. |
| `bootstrap.ps1` | Script that checks winget, installs the one prerequisite the declarative file can't express (Visual Studio Build Tools' C++ workload), and installs the packages (everything, or a `-Profile` subset). This is the file you run. |
| `vscode/` | VS Code "dotfiles" — tracked `settings.json` and `extensions.txt`, applied with `vscode\install.ps1`. See [VS Code profile](#-vs-code-profile-dotfiles) below. |
| `wsl/install-sdkman.sh` | Installs SDKMAN inside a WSL distro. See [WSL2](#-wsl2-required-for-podman) below. |
| `README.md` | This file. |

---

## 🧰 What gets installed

| Category | Tools |
|---|---|
| Core | Git, GitHub CLI, Windows Terminal, Neovim, .NET Desktop Runtime 9 |
| AI / agent tooling | Claude (desktop app), Claude Code (CLI), Antigravity IDE, Antigravity CLI (`agy`) |
| Editor | Visual Studio Code |
| Languages & runtimes | Node.js (LTS), Bun, Python 3.13, Rust (via Rustup) + rust-analyzer, jabba (JDK manager) |
| Containers | Podman (CLI only, no Docker Desktop / no GUI) — needs WSL2, see below |
| Databases | DBeaver Community |
| API tooling | Bruno (open-source, offline-first API client) |
| Media | Spotify |
| Build prerequisite | Visual Studio 2022 Build Tools (C++ workload) — installed by `bootstrap.ps1`, not in the DSC file |

---

## 🚀 Usage

### Replicate the setup (normal use)

In PowerShell, inside this folder:

```powershell
.\bootstrap.ps1
```

The script:
1. Checks that `winget` is available (it ships with *App Installer* on Windows 11).
2. Installs the Visual Studio Build Tools C++ workload (prerequisite for Rust/MSVC and
   native Python extensions).
3. Reads every package id out of `configuration.dsc.yaml` and installs each one with a
   plain `winget install` call.

**No admin pre-step and no elevated terminal needed.** A handful of packages (e.g.
Visual Studio Build Tools) may trigger their own UAC prompt mid-install — just click
through it when it appears.

If script execution is blocked, allow it just for the current session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\bootstrap.ps1
```

Already have a C++ toolchain and want to skip that step:

```powershell
.\bootstrap.ps1 -SkipBuildTools
```

### Scoped runs: `-Profile`

Install only a named subset instead of everything, for a specific stack:

```powershell
.\bootstrap.ps1 -Profile java-kotlin
```

| Profile | Installs |
|---|---|
| `all` (default) | Every package in `configuration.dsc.yaml` |
| `java-kotlin` | Git, GitHub CLI, VS Code, jabba, Podman (CLI), DBeaver Community, Bruno — everything needed for Java/Kotlin + Spring Boot + PostgreSQL + Git, nothing else |
| `utilities` | VS Code, DBeaver Community, Bruno — editor + DB client + API client, no language toolchain |

A non-`all` profile automatically skips the Visual Studio Build Tools step too (no C++
toolchain needed for JVM languages); pass `-SkipBuildTools:$false` to force it anyway.
Profiles are hand-curated lists inside `bootstrap.ps1` (not derived from the YAML), so
adding a new one means editing the `$script:Profiles` hashtable there.

### Alternative: `winget configure` (DSC engine)

`configuration.dsc.yaml` is also a valid file for winget's declarative `configure`
subcommand, if you prefer that engine's convergence semantics. It requires enabling an
experimental feature **once**, as Administrator:

```powershell
winget configure --enable
```

> This step has been unreliable in practice: the elevated PowerShell window it needs to
> run in can end up resolving a different user context, where `winget.exe` isn't
> registered at all ("winget not found"). If that happens, this is exactly why
> `bootstrap.ps1` defaults to the plain-install loop instead — no admin pre-step needed.

Once enabled, run either:

```powershell
.\bootstrap.ps1 -UseConfiguration
# or, without the script:
winget configure -f configuration.dsc.yaml --accept-configuration-agreements
```

---

## ✅ Post-install steps (one time)

A few tools can't be fully configured by a package install alone:

```powershell
# 1) Open a NEW terminal first, so updated PATH entries take effect.

# 2) Install a JDK and set it as default (jabba = SDKMAN-style JDK switching, native Windows)
jabba ls-remote
jabba install temurin@21       # example: Temurin 21 LTS
jabba use temurin@21
jabba alias default temurin@21

# 3) Set the default Rust toolchain
rustup default stable-msvc

# 4) Provision the Podman container engine (one-time, CLI only).
#    Requires WSL2 with at least one distro installed - see WSL2 below.
podman machine init
podman machine start
podman run hello-world   # sanity check

# 5) Sign in where needed: Claude, Claude Code, Antigravity IDE/CLI, Spotify, DBeaver.
```

---

## 🐧 WSL2 (required for Podman)

WSL2 isn't installed by this repo's scripts — it's a Windows feature you install and
manage yourself (`wsl --install`). It's a **required dependency** of this setup, not an
optional extra: this setup's container engine is Podman, not Docker Desktop (see
[Notes on a couple of choices](#-notes-on-a-couple-of-choices)), and Podman's Linux VM
needs WSL2 as its backend on Windows. Without WSL2 (and at least one distro installed),
`podman machine init`/`start` has nothing to run on.

- **Podman's machine backend (required).** `podman machine init` / `podman machine
  start` (see [Post-install steps](#-post-install-steps-one-time)) provisions its Linux
  VM on top of WSL2. Install WSL2 and at least one distro (`wsl --install`) first.
- **SDKMAN, for JVM work done from inside WSL (optional).** From inside a WSL shell (not
  PowerShell), with the repo reachable at `/mnt/c/...`:

  ```bash
  bash wsl/install-sdkman.sh
  ```

  This installs SDKMAN itself; it doesn't install a JDK for you. This is entirely
  separate from `jabba`, which keeps managing the JDK used on the native-Windows side
  (see [Notes on a couple of choices](#-notes-on-a-couple-of-choices)).

### Known issue: Podman + WSL 3.0.1 cgroup error

With WSL 3.0.1, `podman run` can fail with:

```
Error: preparing container ... crun: controller `pids` is not available ... OCI runtime error
```

This is a WSL 3.0.1 regression in how it exposes cgroup controllers into the distro, not
a Podman misconfiguration. Fix it by switching Podman's cgroup manager to `cgroupfs`,
in `%APPDATA%\containers\containers.conf`:

```toml
[engine]
cgroup_manager="cgroupfs"
```

Create the file (and the `containers` folder) if it doesn't exist yet, then re-run
`podman run hello-world`.

---

## 🧩 VS Code profile (dotfiles)

`vscode/` holds a tracked, version-controlled VS Code user profile — extensions +
settings — tuned for Java + Kotlin + Spring Boot + PostgreSQL + Git. Apply it once VS
Code itself is installed:

```powershell
cd vscode
.\install.ps1
```

| File | Role |
|---|---|
| `vscode/extensions.txt` | One extension id per line (`#` for comments/optional ones). Installed via `code --install-extension`. |
| `vscode/settings.json` | User settings. **Symlinked** into `%APPDATA%\Code\User\settings.json` when possible (falls back to a plain copy if symlinks aren't permitted — enable *Developer Mode* in Windows Settings to allow them without admin). |
| `vscode/install.ps1` | Applies both of the above. Safe to re-run any time after editing either file. |

### What's included

| Extension | Why |
|---|---|
| `vscjava.vscode-java-pack` | Java language support, debugger, test runner, Maven, dependency viewer, IntelliCode |
| `vmware.vscode-boot-dev-pack` | Spring Boot Tools, Spring Initializr, Spring Boot Dashboard |
| `jetbrains.kotlin-server` | Official Kotlin language support (JetBrains, powered by the Kotlin Language Server) |
| `ms-ossdata.vscode-pgsql` | PostgreSQL: connect, browse, query with IntelliSense, without leaving the editor |
| `eamodio.gitlens` | Richer Git tooling on top of VS Code's built-in support |

`extensions.txt` also has a commented-out "nice to have" section (REST Client, YAML
schema validation, EditorConfig) — uncomment what you want.

`settings.json` deliberately does **not** hardcode a JDK path: the active JDK is
resolved via `JAVA_HOME`, which `jabba` manages, so switching JDKs with `jabba use`
is picked up automatically (restart VS Code after switching).

---

## ✏️ Customizing the program list

Everything lives in `configuration.dsc.yaml`, under `resources:`. Each program is a block:

```yaml
- resource: Microsoft.WinGet.DSC/WinGetPackage
  id: vscode
  directives:
    description: Visual Studio Code
    allowPrerelease: true
  settings:
    id: Microsoft.VisualStudioCode   # <- the package id in winget
    source: winget
```

- **Add a program:** copy a block and change the `id` (the top-level `id:` is a unique
  alias; `settings.id` is the actual package).
- **Enable a suggestion:** the file has a commented-out `SUGGESTIONS` section — just
  remove the leading `# `.
- **Find a package id:**

  ```powershell
  winget search "program name"
  ```

---

## 🔄 Maintenance

Capture what's installed on the current machine (good starting point / backup):

```powershell
winget export -o winget-export.json
```

Upgrade everything winget manages:

```powershell
winget upgrade --all
```

---

## 🗒️ Notes on a couple of choices

- **JDK/JVM switching on Windows: `jabba`, not SDKMAN.** SDKMAN is a bash/Linux tool; on
  native Windows it only works through workarounds (Git Bash plus manually-installed
  `zip`/`unzip`, or WSL). For the native-Windows side, this setup uses
  **[jabba](https://github.com/shyiko/jabba)** instead — same idea (`jabba install`,
  `jabba use`), but works directly in PowerShell. See [Post-install steps](#-post-install-steps-one-time).
  SDKMAN is also supported, but **inside WSL only**, for Linux-side JVM work — see
  [WSL2](#-wsl2-required-for-podman). These are two separate JDKs for two separate
  environments, not a replacement for jabba.
- **"Antigravity" is two different Google products in the winget catalog**: `Google.Antigravity`
  (a standalone agent-orchestration hub) and `Google.AntigravityIDE` (the actual code
  editor) + `Google.AntigravityCLI` (the terminal client, `agy`). This setup installs the
  **IDE + CLI** pair. If you actually wanted the orchestration hub instead (or as well),
  edit `configuration.dsc.yaml` and uncomment/add the `Google.Antigravity` block.
- **Podman, CLI only — no Docker Desktop.** Linux containers can't run on the Windows
  kernel directly; some VM has to sit underneath no matter which tool you use. Docker
  Desktop and Podman Desktop just wrap that VM in a GUI app. Podman provisions the same
  kind of VM from the command line instead (`podman machine init` / `podman machine
  start`), so there's no desktop app, no GUI, and no Docker Desktop licensing to think
  about. Podman's CLI is drop-in Docker-compatible — `Set-Alias docker podman` in your
  PowerShell profile if you want the literal `docker` command to work too. Its machine
  backend runs on **WSL2**, which is why this setup depends on it — see
  [WSL2](#-wsl2-required-for-podman) below.

---

## 📝 Notes

- Requires **Windows 11** (build 22000+), **App Installer / winget**
  (`winget --version`), and **WSL2** with at least one distro installed, which Podman's
  container backend depends on — see [WSL2](#-wsl2-required-for-podman) below. If
  winget is missing: <https://aka.ms/getwinget>.
- System apps, games, and drivers (e.g. Steam, NVIDIA drivers, Store apps) are **left
  out on purpose** — this setup focuses on development tooling.
- The native-Windows toolchain is the main focus of this repo; WSL2 is only a dependency
  for Podman's container backend (and, optionally, for SDKMAN-based JVM work) — see
  [WSL2](#-wsl2-required-for-podman). Installing WSL2 itself, and any further Linux-side
  tooling beyond `wsl/install-sdkman.sh` (e.g. `apt`-based tooling), is left to you —
  it's a deliberately separate concern from the native-Windows winget flow.
