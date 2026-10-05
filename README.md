# My Dev Setup (Windows)

A **declarative and reproducible** configuration of my Windows 11 development
environment. The idea is simple: one command and the machine ends up exactly the way
I want it — on a brand-new machine, after a reinstall, or just to keep everything
consistent.

It uses **[winget](https://learn.microsoft.com/windows/package-manager/)** (the official
Windows package manager) with **Configuration / DSC**: you describe *what* you want
installed, and winget figures out *how* to reach that state.

---

## 📦 What's in this folder

| File | Purpose |
|---|---|
| `configuration.dsc.yaml` | **The heart of the setup.** Declarative list of every program (the machine's desired state). This is the file you edit. |
| `bootstrap.ps1` | Script that checks winget and applies the configuration above. This is the file you run. |
| `README.md` | This file. |

---

## 🚀 Usage

### Replicate the setup (normal use)

In PowerShell, inside this folder:

```powershell
.\bootstrap.ps1
```

The script:
1. Checks that `winget` is available (it ships with *App Installer* on Windows 11).
2. Applies `configuration.dsc.yaml`, installing whatever is missing.

> **First time on a machine:** winget's *Configuration* feature is **off by default**.
> `bootstrap.ps1` detects this and enables it automatically **if** run as Administrator.
> Otherwise, enable it once in an **elevated** PowerShell:
>
> ```powershell
> winget configure --enable
> ```

> Some packages require elevation — Windows shows the UAC prompt when needed.
> Running PowerShell **as Administrator** avoids several prompts along the way.

If script execution is blocked, allow it just for the current session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\bootstrap.ps1
```

### Alternative (without the script)

```powershell
winget configure -f configuration.dsc.yaml --accept-configuration-agreements
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
