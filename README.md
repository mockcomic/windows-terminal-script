# Terminal Setup Backup — Windows

A complete, portable snapshot of this PC's terminal environment (taken 2026-10-26).
Copy this whole folder to any Windows 10/11 machine (zip it, push it to a GitHub repo, USB stick…)
and run one script to get the identical setup.

## What the setup is

| Component | Detail |
|---|---|
| Terminal | **Windows Terminal** (stable, winget) — currently at default UI settings; settings stored in registry-hive mode (`settings.dat`) |
| Shell | **PowerShell 7** (`pwsh`) as the interactive shell, plus the same profile for Windows PowerShell 5.1 |
| Prompt | **Oh My Posh** with the built-in `gruvbox` theme |
| History | **Atuin** (Ctrl+R search) + PSReadLine history/ListView predictions, Up/Down = history search, Ctrl+Right = accept suggestion, Tab = MenuComplete |
| Navigation | **zoxide** (`z` / `zi`), `cd` auto-lists with **eza**, `cdf`/`openfdir`/`codefdir` via **fzf + fd** |
| Replacements | `ls`/`ll`/`la`/`lt` → **eza** (icons+git), `cat` → **bat**, `grep` → **ripgrep**, `find` → **fd**, `ff` → **fastfetch** (runs on shell start) |
| Git diffs | **delta** as `core.pager` (side-by-side, navigate) + `zdiff3` conflict style, **lazygit** |
| TUIs / extras | **yazi** (file manager, with `file.exe` MIME helper from Git for Windows), **nano**, **glazewm** (window manager), **mise** (tool manager) |
| Handy profile functions | `download <url> [name]`, `emptytrash`, `deepseek` / `deepseek-update` (DeepSeek Harness launcher; repo path is now `$HOME\AI\deepseek-harness`) |
| Fonts | Full **Meslo LG Nerd Font** family (Mono/Propo, L/LDZ/MDZ/M/S) + `UbuntuMono[wght].ttf` — required for eza icons & prompt glyphs |

## Folder contents

```
terminal-backup/
├── install.ps1                  ← run this on the new PC
├── winget/
│   ├── terminal-packages.txt    ← curated tool list the installer uses
│   └── full-machine-export.json ← full `winget export` of this PC (reference only)
├── pwsh/
│   ├── pwsh7.Microsoft.PowerShell_profile.ps1
│   ├── ps5.1.Microsoft.PowerShell_profile.ps1
│   └── legacy.WindowsPowerShell.CurrentUserAllHosts.profile.ps1  ← older 5.1 all-hosts profile, archived for reference (never installed)
├── atuin/config.toml
├── git/gitconfig
├── fonts/                       ← 72 installed Nerd Font faces + UbuntuMono variable
└── windows-terminal/
    ├── settings.dat             ← raw WT settings hive backup (currently default settings)
    └── default-profile.txt
```

## Install on another machine

```powershell
cd terminal-backup
powershell -ExecutionPolicy Bypass -File install.ps1
```

Flags: `-SkipPackages` (configs only, no winget), `-SkipFonts`.

The installer is idempotent; any file it replaces is first saved as `<file>.bak-<timestamp>`.
It also moves any *current-user, all-hosts* profile (`Documents\PowerShell\profile.ps1`,
`Documents\WindowsPowerShell\profile.ps1`) out of the way, because those load **before** the
host-specific profiles from this repo and would otherwise run a second oh-my-posh + fastfetch startup.

### Troubleshooting

**The fastfetch banner prints twice.** PowerShell dot-sources up to four profiles, in this order:
`AllUsersAllHosts` → `CurrentUserAllHosts` → `AllUsersCurrentHost` → `CurrentUserCurrentHost`
(`$PROFILE` lists all four paths). Two of them printing a banner = two banners. Current-user files
live in `Documents\PowerShell\` (pwsh 7) and `Documents\WindowsPowerShell\` (5.1); machine-level
files live in the PowerShell install folder and need admin to change. Since `install.ps1` now
disables leftovers at the all-hosts paths, re-running it fixes this.

### Manual steps afterwards (2 minutes)

1. **Launch Windows Terminal once** (first run creates its Settings folder). If you launched WT *before*
   running the installer, settings.dat is applied automatically; otherwise re-run `install.ps1` once.
2. In Windows Terminal **Settings → Startup → Default profile**, pick **PowerShell** (the `pwsh` profile),
   and set its font face to **MesloLGS Nerd Font Mono** (or any bundled Meslo NF) if icons look broken.
3. Re-run `install.ps1` if you had to do step 1 — or sign out/in once if fonts don't appear immediately.
4. **Set your git identity** — the backup intentionally contains no `[user]` name/email (kept off GitHub):
   `git config --global user.name "Your Name"` and `git config --global user.email you@example.com`.
   The installed `.gitconfig` from this backup only carries delta / LFS / diff settings.

### Not restored automatically (by design)

- **Terminal history contents** — Atuin syncs from your Atuin account (`atuin account import` / login), or accept a fresh history.
- Non-terminal winget apps — see `winget/full-machine-export.json` if you ever want everything (`winget import -i winget\full-machine-export.json`).
- Dev-tool PATH entries unrelated to the terminal (pnpm, Python, CUDA, …). Everything in the tool list puts
  itself on PATH through its winget installer (WinGet\Links + package folders).

## Re-taking the backup

After changing anything (new alias, new tool, WT settings):

```powershell
# 1. refresh the pieces you changed, e.g.:
Copy-Item $PROFILE .\pwsh\pwsh7.Microsoft.PowerShell_profile.ps1 -Force
Copy-Item $HOME\.config\atuin\config.toml .\atuin\config.toml -Force
Copy-Item $HOME\.gitconfig .\git\gitconfig -Force
# 2. refresh the full export if you installed more tools:
winget export -o .\winget\full-machine-export.json --include-versions
# 3. add any new tool ID to winget\terminal-packages.txt
```

If you ever give Windows Terminal real custom settings (colorscheme, profiles…) and want them backed up,
either switch WT back to `settings.json` storage (Settings page bottom: "Edit settings in JSON" / storage-mode
toggle) and copy that file into `windows-terminal\`, or add the new `settings.dat` here again.
