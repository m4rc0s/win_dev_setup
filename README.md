# My Dev Setup (Windows)

A **declarative and reproducible** configuration of my Windows 11 development
environment. The idea is simple: one command and the machine ends up exactly the way
I want it — on a brand-new machine, after a reinstall, or just to keep everything
consistent.

It uses **[winget](https://learn.microsoft.com/windows/package-manager/)** (the official
Windows package manager) with **Configuration / DSC**: you describe *what* you want
installed, and winget figures out *how* to reach that state. Everything runs **natively
on Windows** — no WSL, no Linux layer required.

---

## 📦 What's in this folder

| File | Purpose |
|---|---|
| `configuration.dsc.yaml` | **The heart of the setup.** Declarative list of every program (the machine's desired state). This is the file you edit. |
| `bootstrap.ps1` | Script that checks winget, installs the one prerequisite the declarative file can't express (Visual Studio Build Tools' C++ workload), and applies the configuration. This is the file you run. |
| `README.md` | This file. |

---

## 🧰 What gets installed

| Category | Tools |
|---|---|
| Core | Git, Windows Terminal, Neovim, .NET Desktop Runtime 9 |
| AI / agent tooling | Claude (desktop app), Claude Code (CLI), Antigravity IDE, Antigravity CLI (`agy`) |
| Editor | Visual Studio Code |
| Languages & runtimes | Node.js (LTS), Bun, Python 3.13, Rust (via Rustup) + rust-analyzer, jabba (JDK manager) |
| Containers | Podman (CLI only, no Docker Desktop / no GUI) |
| Databases | DBeaver Community |
| Media | Spotify |
| Build prerequisite | Visual Studio 2022 Build Tools (C++ workload) — installed by `bootstrap.ps1`, not in the DSC file |

### Notes on a couple of choices

- **JDK/JVM switching: `jabba`, not SDKMAN.** SDKMAN is a bash/Linux tool; on native
  Windows it only works through workarounds (Git Bash plus manually-installed `zip`/
  `unzip`, or WSL). Since this setup stays 100% native, it uses
  **[jabba](https://github.com/shyiko/jabba)** instead — same idea (`jabba install`,
  `jabba use`), but works directly in PowerShell. See [Post-install steps](#-post-install-steps-one-time).
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
  PowerShell profile if you want the literal `docker` command to work too.

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
Docker Desktop) may trigger their own UAC prompt mid-install — just click through it
when it appears.

If script execution is blocked, allow it just for the current session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\bootstrap.ps1
```

Already have a C++ toolchain and want to skip that step:

```powershell
.\bootstrap.ps1 -SkipBuildTools
```

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

# 4) Provision the Podman container engine (one-time, CLI only):
podman machine init
podman machine start
podman run hello-world   # sanity check

# 5) Sign in where needed: Claude, Claude Code, Antigravity IDE/CLI, Spotify, DBeaver.
```

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

## 📝 Notes

- Requires **Windows 11** (build 22000+) and **App Installer / winget** (`winget --version`).
  If missing: <https://aka.ms/getwinget>.
- System apps, games, and drivers (e.g. Steam, NVIDIA drivers, Store apps) are **left
  out on purpose** — this setup focuses on development tooling.
- This setup is intentionally **native-Windows-only** (no WSL). If you later want a
  Linux-flavored toolchain (e.g. the real SDKMAN, `apt`-based tooling) alongside this,
  that would live in a separate script run inside WSL — it's a deliberately separate
  concern from this repo.
