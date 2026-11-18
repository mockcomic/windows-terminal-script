# -----------------------------
# Prompt / Theme
# Each tool is checked before init so a -SkipPackages install (or a
# machine where a tool is missing) starts clean instead of error-walling
# on every shell launch.
# -----------------------------
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config "gruvbox" | Invoke-Expression
}


# -----------------------------
# Smart cd / directory jumping
# -----------------------------
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}


# -----------------------------
# PSReadLine - type-ahead suggestions
# Load before Atuin. Atuin only sees a module that is already imported,
# and these prediction options need PSReadLine 2.2 or newer.
# Windows PowerShell 5.1 ships 2.0.0; 2.3.6 is installed for the user.
# -----------------------------
$loadedPsrl = Get-Module PSReadLine
if ($loadedPsrl -and $loadedPsrl.Version -lt [version]'2.2.0') {
    Remove-Module PSReadLine -Force
}
Import-Module PSReadLine -MinimumVersion 2.2.0

# -----------------------------
# Atuin - better shell history
# Ctrl+R = Atuin history search
# -----------------------------
if (Get-Command atuin -ErrorAction SilentlyContinue) {
    atuin init powershell | Out-String | Invoke-Expression
}

# Predictions need a real console. Skip them when output is redirected,
# such as powershell -File from a non-interactive host.
if (-not [Console]::IsOutputRedirected) {
    try {
        # 5.1 ships PSReadLine 2.0.0; predictions need 2.2+. Reload the
        # newer user-installed module if the shell preloaded an old one.
        $loadedPsrl = Get-Module PSReadLine
        if ($loadedPsrl -and $loadedPsrl.Version -lt [version]'2.2.0') {
            Remove-Module PSReadLine -Force
        }
        Import-Module PSReadLine -MinimumVersion 2.2.0 -ErrorAction Stop
        Set-PSReadLineOption -PredictionSource History -ErrorAction Stop
        Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction Stop
        Set-PSReadLineKeyHandler -Key RightArrow -Function AcceptSuggestion
    } catch {
        Write-Verbose "PSReadLine predictions are unavailable in this console."
    }
}

# Better tab completion menu
if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
}


# -----------------------------
# Remove default PowerShell aliases that block replacement
# -----------------------------
foreach ($alias in @("ls", "cat", "grep", "find")) {
    if (Test-Path "Alias:$alias") {
        Remove-Item "Alias:$alias" -Force
    }
}


# -----------------------------
# Better terminal tool aliases
# Only where the replacement tool actually exists, so a partial install
# keeps the stock PowerShell verbs instead of broken aliases.
# -----------------------------
if (Get-Command eza -ErrorAction SilentlyContinue) {
    Set-Alias ls eza
    Set-Alias ll eza
}
if (Get-Command bat -ErrorAction SilentlyContinue) {
    Set-Alias cat bat
}
if (Get-Command rg -ErrorAction SilentlyContinue) {
    Set-Alias grep rg
}
if (Get-Command fd -ErrorAction SilentlyContinue) {
    Set-Alias find fd
}


# -----------------------------
# Directory listing helpers
# -----------------------------
function la {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza -la --icons --git @args
    } else {
        Get-ChildItem -Force @args
    }
}

function lt {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza --tree --level=2 --icons --git @args
    } else {
        Get-ChildItem -Recurse -Depth 1 @args
    }
}


# -----------------------------
# System info
# -----------------------------
function ff {
    if (Get-Command fastfetch -ErrorAction SilentlyContinue) {
        fastfetch
    }
}


# -----------------------------
# fzf file/folder helpers
# -----------------------------

# Pick a file with fzf, then cd into its folder
function cdf {
    if (-not (Get-Command fd -ErrorAction SilentlyContinue)) {
        Write-Host "cdf needs 'fd'." -ForegroundColor Yellow
        return
    }
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Write-Host "cdf needs 'fzf'." -ForegroundColor Yellow
        return
    }
    $file = fd --type f --hidden --exclude .git | fzf

    if ($file) {
        Set-Location (Split-Path $file -Parent)
    }
}

# Pick a file with fzf, then open its folder in Explorer
function openfdir {
    if (-not (Get-Command fd -ErrorAction SilentlyContinue)) {
        Write-Host "openfdir needs 'fd'." -ForegroundColor Yellow
        return
    }
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Write-Host "openfdir needs 'fzf'." -ForegroundColor Yellow
        return
    }
    $file = fd --type f --hidden --exclude .git | fzf

    if ($file) {
        explorer (Split-Path $file -Parent)
    }
}

# Pick a file with fzf, then open its folder in VS Code
function codefdir {
    if (-not (Get-Command fd -ErrorAction SilentlyContinue)) {
        Write-Host "codefdir needs 'fd'." -ForegroundColor Yellow
        return
    }
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Write-Host "codefdir needs 'fzf'." -ForegroundColor Yellow
        return
    }
    $file = fd --type f --hidden --exclude .git | fzf

    if ($file) {
        code (Split-Path $file -Parent)
    }
}


# -----------------------------
# Recycle Bin
# -----------------------------
function emptytrash {
    # Clear-RecycleBin throws when the bin is already empty; that is a
    # success case, not an error.
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
    } catch {
        Write-Verbose "Recycle Bin was already empty."
    }
    Write-Host "Recycle Bin emptied."
}


# -----------------------------
# Launch fastfetch when opening an interactive terminal
# -----------------------------
if ($Host.Name -eq "ConsoleHost" -and -not [Console]::IsOutputRedirected) {
    ff
}