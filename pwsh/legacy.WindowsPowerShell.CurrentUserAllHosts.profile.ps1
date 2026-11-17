# -----------------------------
# Omarchy-like PowerShell Profile
# -----------------------------

# Icons
Import-Module Terminal-Icons -ErrorAction SilentlyContinue

# -----------------------------
# Prompt / Theme
# -----------------------------
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    $theme = "$env:POSH_THEMES_PATH\gruvbox.omp.json"
    if (Test-Path $theme) {
        oh-my-posh init pwsh --config $theme | Invoke-Expression
    } else {
        oh-my-posh init pwsh | Invoke-Expression
    }
}

# -----------------------------
# Editor
# -----------------------------
$env:EDITOR = "nano"
$env:VISUAL = "nano"

function edit {
    nano @args
}

# -----------------------------
# PSReadLine
# -----------------------------
Import-Module PSReadLine -ErrorAction SilentlyContinue

if ($PSVersionTable.PSVersion -ge [version]"7.2") {
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
}
Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction SilentlyContinue
Set-PSReadLineOption -EditMode Windows -ErrorAction SilentlyContinue
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete -ErrorAction SilentlyContinue
Set-PSReadLineKeyHandler -Key Ctrl+d -Function DeleteCharOrExit -ErrorAction SilentlyContinue

# Ctrl+R = Atuin history search
if (Get-Command atuin -ErrorAction SilentlyContinue) {
    atuin init powershell | Out-String | Invoke-Expression
}

# zoxide smart cd
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    zoxide init powershell | Out-String | Invoke-Expression
}

# -----------------------------
# Linux-style commands
# -----------------------------

function ls {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza --icons=auto --group-directories-first @args
    } else {
        Get-ChildItem @args
    }
}

function la {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza -la --icons=auto --group-directories-first @args
    } else {
        Get-ChildItem -Force @args
    }
}

function lt {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza --tree --level=2 --icons=auto --group-directories-first @args
    } else {
        tree @args
    }
}

function cat {
    if (Get-Command bat -ErrorAction SilentlyContinue) {
        bat @args
    } else {
        Get-Content @args
    }
}

function grep {
    if (Get-Command rg -ErrorAction SilentlyContinue) {
        rg @args
    } else {
        Select-String @args
    }
}

function find {
    if (Get-Command fd -ErrorAction SilentlyContinue) {
        fd @args
    } else {
        Get-ChildItem -Recurse @args
    }
}

function ff {
    if (Get-Command fzf -ErrorAction SilentlyContinue) {
        fzf @args
    } else {
        Write-Host "fzf is not installed"
    }
}

function cdf {
    if ((Get-Command fd -ErrorAction SilentlyContinue) -and (Get-Command fzf -ErrorAction SilentlyContinue)) {
        $dir = fd --type d --hidden --exclude .git | fzf
        if ($dir) { Set-Location $dir }
    }
}

function openfdir {
    explorer.exe .
}

function reload-profile {
    . $PROFILE.CurrentUserAllHosts
}

function edit-profile {
    nano $PROFILE.CurrentUserAllHosts
}

# -----------------------------
# Git shortcuts
# -----------------------------
function gs { git status @args }
function ga { git add @args }
function gcmsg { git commit -m @args }
function gp { git push @args }
function gl { git pull @args }
function lg { lazygit @args }

# -----------------------------
# Useful aliases
# -----------------------------
Set-Alias which Get-Command
Set-Alias touch New-Item

# -----------------------------
# Startup look
# -----------------------------
Clear-Host
if (Get-Command fastfetch -ErrorAction SilentlyContinue) {
    fastfetch
}

# -----------------------------
# Compact eza listing overrides
# -----------------------------

function ls {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza --grid --icons=auto --group-directories-first @args
    } else {
        Get-ChildItem @args
    }
}

function la {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza --grid --all --icons=auto --group-directories-first @args
    } else {
        Get-ChildItem -Force @args
    }
}

function ll {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza --long --icons=auto --group-directories-first @args
    } else {
        Get-ChildItem @args
    }
}

function lla {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza --long --all --icons=auto --group-directories-first @args
    } else {
        Get-ChildItem -Force @args
    }
}

# -----------------------------
# Compact ls override
# -----------------------------
function ls {
    eza --grid --icons=auto --group-directories-first --no-quotes @args
}

# -----------------------------
# Compact ls override
# -----------------------------
function ls {
    eza --grid --icons=auto --group-directories-first --no-quotes @args
}

# -----------------------------
# Force compact eza ls / la
# -----------------------------
Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
Remove-Item Alias:dir -Force -ErrorAction SilentlyContinue

function global:ls {
    eza --grid --icons=auto --group-directories-first --no-quotes @args
}

function global:la {
    eza --grid --all --icons=auto --group-directories-first --no-quotes @args
}

function global:ll {
    eza --long --icons=auto --group-directories-first --no-quotes @args
}

function global:lla {
    eza --long --all --icons=auto --group-directories-first --no-quotes @args
}
