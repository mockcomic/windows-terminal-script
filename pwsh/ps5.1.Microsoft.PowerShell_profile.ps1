# -----------------------------
# Prompt / Theme
# -----------------------------
oh-my-posh init pwsh --config "gruvbox" | Invoke-Expression


# -----------------------------
# Smart cd / directory jumping
# -----------------------------
Invoke-Expression (& { (zoxide init powershell | Out-String) })


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
atuin init powershell | Out-String | Invoke-Expression

# Predictions need a real console. Skip them when output is redirected,
# such as powershell -File from a non-interactive host.
if (-not [Console]::IsOutputRedirected) {
    try {
        Set-PSReadLineOption -PredictionSource History -ErrorAction Stop
        Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction Stop
        Set-PSReadLineKeyHandler -Key RightArrow -Function AcceptSuggestion
    } catch {
        Write-Verbose "PSReadLine predictions are unavailable in this console."
    }
}

# Better tab completion menu
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete


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
# -----------------------------
Set-Alias ls eza
Set-Alias ll eza
Set-Alias cat bat
Set-Alias grep rg
Set-Alias find fd


# -----------------------------
# Directory listing helpers
# -----------------------------
function la {
    eza -la --icons --git @args
}

function lt {
    eza --tree --level=2 --icons --git @args
}


# -----------------------------
# System info
# -----------------------------
function ff {
    fastfetch
}


# -----------------------------
# fzf file/folder helpers
# -----------------------------

# Pick a file with fzf, then cd into its folder
function cdf {
    $file = fd --type f --hidden --exclude .git | fzf

    if ($file) {
        Set-Location (Split-Path $file -Parent)
    }
}

# Pick a file with fzf, then open its folder in Explorer
function openfdir {
    $file = fd --type f --hidden --exclude .git | fzf

    if ($file) {
        explorer (Split-Path $file -Parent)
    }
}

# Pick a file with fzf, then open its folder in VS Code
function codefdir {
    $file = fd --type f --hidden --exclude .git | fzf

    if ($file) {
        code (Split-Path $file -Parent)
    }
}


# -----------------------------
# Recycle Bin
# -----------------------------
function emptytrash {
    Clear-RecycleBin -Force
    Write-Host "Recycle Bin emptied."
}


# -----------------------------
# Launch fastfetch when opening an interactive terminal
# -----------------------------
if ($Host.Name -eq "ConsoleHost") {
    ff
}