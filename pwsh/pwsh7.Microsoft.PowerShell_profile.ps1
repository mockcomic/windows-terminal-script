# -----------------------------
# Prompt / Theme
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
# Atuin - better shell history
# Ctrl+R = Atuin history search
# -----------------------------
if (Get-Command atuin -ErrorAction SilentlyContinue) {
    atuin init powershell | Out-String | Invoke-Expression
}


# -----------------------------
# PSReadLine - history + type-ahead suggestions
# Requires newer PSReadLine / PowerShell 7+
# -----------------------------
Import-Module PSReadLine -ErrorAction SilentlyContinue

$psrlOptions = Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue
$psrlKeys = Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue

if ($psrlOptions) {
    $optionParams = $psrlOptions.Parameters.Keys

    if ($optionParams -contains "PredictionSource") {
        try {
            Set-PSReadLineOption -PredictionSource HistoryAndPlugin
        } catch {
            Set-PSReadLineOption -PredictionSource History
        }
    }

    if ($optionParams -contains "PredictionViewStyle") {
        Set-PSReadLineOption -PredictionViewStyle ListView
    }

    if ($optionParams -contains "HistorySaveStyle") {
        Set-PSReadLineOption -HistorySaveStyle SaveIncrementally
    }

    if ($optionParams -contains "HistorySearchCursorMovesToEnd") {
        Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    }
}

if ($psrlKeys) {
    # Smart history search:
    # - Press UpArrow with an empty line to go through recent commands.
    # - Type part of a command, then press UpArrow to search matching history.
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

    # Ctrl+Up / Ctrl+Down can still move through raw history normally
    Set-PSReadLineKeyHandler -Key Ctrl+UpArrow -Function PreviousHistory
    Set-PSReadLineKeyHandler -Key Ctrl+DownArrow -Function NextHistory

    # Normal arrow behavior
    Set-PSReadLineKeyHandler -Key LeftArrow -Function BackwardChar
    Set-PSReadLineKeyHandler -Key RightArrow -Function ForwardChar

    # Accept suggestions with Ctrl+Right instead of stealing normal RightArrow
    try {
        Set-PSReadLineKeyHandler -Key Ctrl+RightArrow -Function AcceptSuggestion
    } catch {
        # Older PSReadLine versions may not support AcceptSuggestion
    }

    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
}


# -----------------------------
# Yazi MIME detection on Windows
# -----------------------------
$gitFileExe = "C:\Program Files\Git\usr\bin\file.exe"

if (Test-Path $gitFileExe) {
    $env:YAZI_FILE_ONE = $gitFileExe
}


# -----------------------------
# Remove default PowerShell aliases that block replacement
# -----------------------------
foreach ($alias in @("ls", "ll", "cat", "grep", "find", "cd", "z", "zi")) {
    if (Test-Path "Alias:$alias") {
        Remove-Item "Alias:$alias" -Force -ErrorAction SilentlyContinue
    }
}


# -----------------------------
# Auto-list helper
# -----------------------------
function Invoke-AutoList {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza -a --icons --git
    } else {
        Get-ChildItem -Force
    }
}


# -----------------------------
# Better terminal tool aliases / replacements
# -----------------------------

# ls now behaves like ls -a
function ls {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza -a --icons --git @args
    } else {
        Get-ChildItem -Force @args
    }
}

# ll shows a long all-files listing
function ll {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza -la --icons --git @args
    } else {
        Get-ChildItem -Force @args
    }
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
# cd / zoxide with auto ls
# -----------------------------

# cd into a directory, then automatically list files
function cd {
    Set-Location @args

    if ($?) {
        Invoke-AutoList
    }
}

# zoxide jump, then automatically list files
function z {
    if (-not (Get-Command zoxide -ErrorAction SilentlyContinue)) {
        Write-Host "zoxide is not installed or not in PATH."
        return
    }

    if ($args.Count -eq 0) {
        Set-Location ~

        if ($?) {
            Invoke-AutoList
        }

        return
    }

    $target = zoxide query -- @args

    if ($LASTEXITCODE -eq 0 -and $target) {
        Set-Location $target

        if ($?) {
            Invoke-AutoList
        }
    }
}

# interactive zoxide jump, then automatically list files
function zi {
    if (-not (Get-Command zoxide -ErrorAction SilentlyContinue)) {
        Write-Host "zoxide is not installed or not in PATH."
        return
    }

    $target = zoxide query -i -- @args

    if ($LASTEXITCODE -eq 0 -and $target) {
        Set-Location $target

        if ($?) {
            Invoke-AutoList
        }
    }
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
        Get-ChildItem -Recurse @args
    }
}


# -----------------------------
# System info
# -----------------------------
function ff {
    if (Get-Command fastfetch -ErrorAction SilentlyContinue) {
        fastfetch
    } else {
        systeminfo
    }
}


# -----------------------------
# fzf file/folder helpers
# -----------------------------
function cdf {
    if (-not (Get-Command fd -ErrorAction SilentlyContinue)) {
        Write-Host "fd is not installed or not in PATH."
        return
    }

    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Write-Host "fzf is not installed or not in PATH."
        return
    }

    $file = fd --type f --hidden --exclude .git | fzf

    if ($file) {
        Set-Location (Split-Path $file -Parent)

        if ($?) {
            Invoke-AutoList
        }
    }
}

function openfdir {
    if (-not (Get-Command fd -ErrorAction SilentlyContinue)) {
        Write-Host "fd is not installed or not in PATH."
        return
    }

    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Write-Host "fzf is not installed or not in PATH."
        return
    }

    $file = fd --type f --hidden --exclude .git | fzf

    if ($file) {
        explorer (Split-Path $file -Parent)
    }
}

function codefdir {
    if (-not (Get-Command fd -ErrorAction SilentlyContinue)) {
        Write-Host "fd is not installed or not in PATH."
        return
    }

    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Write-Host "fzf is not installed or not in PATH."
        return
    }

    $file = fd --type f --hidden --exclude .git | fzf

    if ($file) {
        code (Split-Path $file -Parent)
    }
}


function download {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Url,

        [Parameter(Mandatory = $false, Position = 1)]
        [string]$FileName
    )

    try {
        $uri = [System.Uri]$Url

        # Use provided filename, otherwise extract it from the URL path
        if (-not $FileName) {
            $FileName = [System.IO.Path]::GetFileName($uri.LocalPath)
        }

        # Fallback if URL does not contain a filename
        if ([string]::IsNullOrWhiteSpace($FileName)) {
            $FileName = "downloaded-file"
        }

        # Decode URL-encoded filenames like file%20name.zip
        $FileName = [System.Uri]::UnescapeDataString($FileName)

        # Save into current directory
        $targetPath = Join-Path -Path (Get-Location) -ChildPath $FileName

        Write-Host "Downloading..." -ForegroundColor Cyan
        Write-Host "URL: $Url"
        Write-Host "To:  $targetPath"
        Write-Host ""

        Invoke-WebRequest -Uri $Url -OutFile $targetPath

        Write-Host "Downloaded to: $targetPath" -ForegroundColor Green
    }
    catch {
        Write-Host "Download failed: $($_.Exception.Message)" -ForegroundColor Red
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


# -----------------------------
# DeepSeek Harness
# -----------------------------
# Portable: resolves to the current user's profile folder on any machine
$DeepSeekHarnessPath = Join-Path $HOME "AI\deepseek-harness"

function Initialize-DeepSeekPnpm {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Repo
    )

    if (-not (Get-Command corepack -ErrorAction SilentlyContinue)) {
        Write-Host "[DeepSeek] Corepack was not found in PATH." -ForegroundColor Red
        return $false
    }

    $PackageJsonPath = Join-Path $Repo "package.json"

    if (-not (Test-Path $PackageJsonPath)) {
        Write-Host "[DeepSeek] package.json was not found at $PackageJsonPath" -ForegroundColor Red
        return $false
    }

    try {
        $PackageJson = Get-Content $PackageJsonPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Host "[DeepSeek] Could not read package.json: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }

    $PackageManagerSpec = [string]$PackageJson.packageManager

    if ($PackageManagerSpec -notmatch '^pnpm@(.+)$') {
        Write-Host "[DeepSeek] package.json does not declare a valid pnpm packageManager." -ForegroundColor Red
        Write-Host "[DeepSeek] Found: $PackageManagerSpec" -ForegroundColor Red
        return $false
    }

    $RequiredPnpmVersion = $Matches[1]

    # Create a DeepSeek-only pnpm shim. This avoids changing your global pnpm
    # installation while ensuring nested `pnpm` calls spawned by Harness also
    # use the exact packageManager version pinned by the repository.
    $ShimDir = Join-Path $env:LOCALAPPDATA "DeepSeekHarness\pnpm-shim"
    $PnpmShim = Join-Path $ShimDir "pnpm.cmd"

    if (-not (Test-Path $ShimDir)) {
        New-Item -ItemType Directory -Path $ShimDir -Force | Out-Null
    }

    $ShimContents = @"
@echo off
corepack pnpm@$RequiredPnpmVersion %*
exit /b %ERRORLEVEL%
"@

    Set-Content -Path $PnpmShim -Value $ShimContents -Encoding Ascii

    # Put the shim first in PATH for this PowerShell process and all child
    # processes spawned from it. This is what fixes scripts/build.ts calling
    # `pnpm` internally and accidentally finding a different global version.
    $PathParts = $env:PATH -split ';' | Where-Object { $_ -and ($_ -ne $ShimDir) }
    $env:PATH = (@($ShimDir) + $PathParts) -join ';'

    $script:DeepSeekPnpmCommand = $PnpmShim
    $script:DeepSeekRequiredPnpmVersion = $RequiredPnpmVersion

    # Verify the shim before doing any install/build work.
    $VersionOutput = & $PnpmShim --version 2>&1
    $VersionExitCode = $LASTEXITCODE
    $ResolvedVersion = (($VersionOutput | Out-String).Trim())

    if ($VersionExitCode -ne 0) {
        Write-Host "[DeepSeek] Could not start pnpm@$RequiredPnpmVersion through Corepack." -ForegroundColor Red
        if ($ResolvedVersion) {
            Write-Host $ResolvedVersion -ForegroundColor Red
        }
        return $false
    }

    if ($ResolvedVersion -ne $RequiredPnpmVersion) {
        Write-Host "[DeepSeek] pnpm version mismatch." -ForegroundColor Red
        Write-Host "[DeepSeek] Required: $RequiredPnpmVersion" -ForegroundColor Red
        Write-Host "[DeepSeek] Resolved: $ResolvedVersion" -ForegroundColor Red
        return $false
    }

    Write-Host "[DeepSeek] pnpm: $ResolvedVersion (repo-pinned)" -ForegroundColor DarkGray
    return $true
}


function Invoke-DeepSeekPnpm {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]] $Arguments
    )

    if (
        -not $script:DeepSeekPnpmCommand -or
        -not (Test-Path $script:DeepSeekPnpmCommand)
    ) {
        Write-Host "[DeepSeek] The repo-pinned pnpm shim has not been initialized." -ForegroundColor Red
        return 127
    }

    # Send command output directly to the terminal. The only pipeline output
    # returned by this helper is the numeric process exit code.
    & $script:DeepSeekPnpmCommand @Arguments 2>&1 | Out-Host
    $ExitCode = $LASTEXITCODE

    return [int]$ExitCode
}


function Invoke-DeepSeekBuild {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Repo,

        [Parameter(Mandatory = $true)]
        [string] $CurrentCommit,

        [Parameter(Mandatory = $true)]
        [string] $BuildMarker,

        [Parameter(Mandatory = $true)]
        [string] $ProfilesNodeModules
    )

    $RepoNodeModules = Join-Path $Repo "node_modules"

    Write-Host ""
    Write-Host "==> Synchronizing dependencies..." -ForegroundColor Cyan

    $result = Invoke-DeepSeekPnpm install

    if ($result -ne 0) {
        Write-Host ""
        Write-Host "[DeepSeek] Normal dependency install failed." -ForegroundColor Yellow
        Write-Host "[DeepSeek] Attempting automatic dependency repair..." -ForegroundColor Yellow

        if (Test-Path $RepoNodeModules) {
            Write-Host "[DeepSeek] Removing repository node_modules..." -ForegroundColor DarkGray
            Remove-Item $RepoNodeModules -Recurse -Force -ErrorAction SilentlyContinue
        }

        $result = Invoke-DeepSeekPnpm install --force

        if ($result -ne 0) {
            Write-Host ""
            Write-Host "[DeepSeek] Dependency installation failed with exit code $result." -ForegroundColor Red
            Write-Host "[DeepSeek] See the pnpm error above for the actual cause." -ForegroundColor Red
            return $false
        }
    }

    Write-Host ""
    Write-Host "==> Building DeepSeek Harness..." -ForegroundColor Cyan

    # Use the full build. This regenerates the artifacts required by
    # the current Harness checkout, including client/Typert outputs.
    $result = Invoke-DeepSeekPnpm run build

    if ($result -ne 0) {
        Write-Host ""
        Write-Host "[DeepSeek] Initial build failed." -ForegroundColor Yellow
        Write-Host "[DeepSeek] Performing full generated-dependency repair..." -ForegroundColor Yellow

        if (Test-Path $RepoNodeModules) {
            Write-Host "[DeepSeek] Removing repository node_modules..." -ForegroundColor DarkGray
            Remove-Item $RepoNodeModules -Recurse -Force -ErrorAction SilentlyContinue
        }

        # This is generated/shared package state only.
        # Your actual .dsh profile/config files are preserved.
        if (Test-Path $ProfilesNodeModules) {
            Write-Host "[DeepSeek] Removing stale profile node_modules..." -ForegroundColor DarkGray
            Remove-Item $ProfilesNodeModules -Recurse -Force -ErrorAction SilentlyContinue
        }

        Write-Host ""
        Write-Host "==> Reinstalling dependencies..." -ForegroundColor Cyan

        $result = Invoke-DeepSeekPnpm install --force

        if ($result -ne 0) {
            Write-Host ""
            Write-Host "[DeepSeek] Dependency repair failed with exit code $result." -ForegroundColor Red
            return $false
        }

        Write-Host ""
        Write-Host "==> Retrying full build..." -ForegroundColor Cyan

        $result = Invoke-DeepSeekPnpm run build

        if ($result -ne 0) {
            Write-Host ""
            Write-Host "[DeepSeek] DeepSeek Harness still fails to build. Exit code: $result" -ForegroundColor Red
            Write-Host "[DeepSeek] See the build error above." -ForegroundColor Red
            return $false
        }
    }

    # Refresh the generated shared profile package fallback after a
    # successful build so the next launch cannot reuse stale packages.
    if (Test-Path $ProfilesNodeModules) {
        Write-Host ""
        Write-Host "==> Refreshing DeepSeek profile dependencies..." -ForegroundColor Cyan
        Remove-Item $ProfilesNodeModules -Recurse -Force -ErrorAction SilentlyContinue
    }

    $stateDir = Split-Path $BuildMarker -Parent

    if (-not (Test-Path $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    }

    Set-Content -Path $BuildMarker -Value $CurrentCommit -NoNewline

    Write-Host ""
    Write-Host "[DeepSeek] Build completed successfully." -ForegroundColor Green

    return $true
}


function deepseek-update {
    $Repo = $DeepSeekHarnessPath
    $ProfilesNodeModules = Join-Path $HOME ".dsh\profiles\node_modules"
    $StateDir = Join-Path $env:LOCALAPPDATA "DeepSeekHarness"
    $BuildMarker = Join-Path $StateDir "last-built-commit.txt"

    if (-not (Test-Path (Join-Path $Repo ".git"))) {
        Write-Host "DeepSeek Harness repo not found:" -ForegroundColor Red
        Write-Host $Repo
        return $false
    }

    Push-Location $Repo

    try {
        Write-Host ""
        Write-Host "Checking for DeepSeek Harness updates..." -ForegroundColor Cyan

        $before = (git rev-parse HEAD 2>$null).Trim()

        if (-not $before) {
            Write-Host "[DeepSeek] Could not determine the current Git revision." -ForegroundColor Red
            return $false
        }

        git fetch --prune origin

        if ($LASTEXITCODE -ne 0) {
            Write-Host "[DeepSeek] Git fetch failed." -ForegroundColor Red
            return $false
        }

        git pull --ff-only

        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "[DeepSeek] Git update could not fast-forward." -ForegroundColor Red
            Write-Host "[DeepSeek] Local files were not overwritten." -ForegroundColor Yellow
            return $false
        }

        $after = (git rev-parse HEAD 2>$null).Trim()

        if (-not $after) {
            Write-Host "[DeepSeek] Could not determine the Git revision after updating." -ForegroundColor Red
            return $false
        }

        if ($before -eq $after) {
            Write-Host "Already up to date." -ForegroundColor Green
        }
        else {
            Write-Host ""
            Write-Host "DeepSeek Harness updated:" -ForegroundColor Green
            Write-Host "  $($before.Substring(0, 8)) -> $($after.Substring(0, 8))"
        }

        if (-not (Initialize-DeepSeekPnpm -Repo $Repo)) {
            Write-Host "[DeepSeek] Could not initialize the repo-pinned pnpm version." -ForegroundColor Red
            return $false
        }

        # Explicit deepseek-update always verifies/install/builds the current checkout.
        return Invoke-DeepSeekBuild `
            -Repo $Repo `
            -CurrentCommit $after `
            -BuildMarker $BuildMarker `
            -ProfilesNodeModules $ProfilesNodeModules
    }
    finally {
        Pop-Location
    }
}


function deepseek {
    $Repo = $DeepSeekHarnessPath

    # Generated/shared package cache only. Actual DeepSeek profile,
    # credentials, models, MCP config, and cordis.patch.yml are preserved.
    $ProfilesNodeModules = Join-Path $HOME ".dsh\profiles\node_modules"

    # Track the last git commit that completed install + full build.
    $StateDir = Join-Path $env:LOCALAPPDATA "DeepSeekHarness"
    $BuildMarker = Join-Path $StateDir "last-built-commit.txt"

    function Write-DeepSeekStep($Message) {
        Write-Host ""
        Write-Host "==> $Message" -ForegroundColor Cyan
    }

    function Stop-DeepSeek($Message) {
        Write-Host ""
        Write-Host "[DeepSeek] $Message" -ForegroundColor Red
    }

    # ------------------------------------------------------------
    # 1. Prerequisites
    # ------------------------------------------------------------

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Stop-DeepSeek "Git was not found in PATH."
        return
    }

    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Stop-DeepSeek "Node.js was not found in PATH."
        return
    }

    if (-not (Get-Command corepack -ErrorAction SilentlyContinue)) {
        Stop-DeepSeek "Corepack was not found in PATH."
        return
    }

    # ------------------------------------------------------------
    # 2. Clone automatically if the repo disappears
    # ------------------------------------------------------------

    if (-not (Test-Path (Join-Path $Repo ".git"))) {
        Write-DeepSeekStep "DeepSeek Harness repo not found. Cloning it..."

        $Parent = Split-Path $Repo -Parent

        if (-not (Test-Path $Parent)) {
            New-Item -ItemType Directory -Path $Parent -Force | Out-Null
        }

        git clone https://github.com/deepseek-ai/deepseek-harness.git $Repo

        if ($LASTEXITCODE -ne 0) {
            Stop-DeepSeek "Git clone failed."
            return
        }
    }

    Push-Location $Repo

    try {
        # --------------------------------------------------------
        # 3. Current checkout
        # --------------------------------------------------------

        $BeforeUpdate = (git rev-parse HEAD 2>$null).Trim()

        if (-not $BeforeUpdate) {
            Stop-DeepSeek "Could not determine the current Git revision."
            return
        }

        Write-Host ""
        Write-Host "DeepSeek Harness" -ForegroundColor Green
        Write-Host "Repository: $Repo"
        Write-Host "Current:    $($BeforeUpdate.Substring(0, 8))"

        # --------------------------------------------------------
        # 4. Update safely
        # --------------------------------------------------------

        Write-DeepSeekStep "Checking for DeepSeek Harness updates..."

        $UpdateSucceeded = $true

        git fetch --prune origin

        if ($LASTEXITCODE -ne 0) {
            Write-Host "[DeepSeek] Git fetch failed. Using the existing checkout." -ForegroundColor Yellow
            $UpdateSucceeded = $false
        }
        else {
            git pull --ff-only

            if ($LASTEXITCODE -ne 0) {
                Write-Host ""
                Write-Host "[DeepSeek] Automatic update could not fast-forward." -ForegroundColor Yellow
                Write-Host "[DeepSeek] Local files were NOT overwritten." -ForegroundColor Yellow
                Write-Host "[DeepSeek] Continuing with the existing checkout." -ForegroundColor Yellow
                $UpdateSucceeded = $false
            }
        }

        $CurrentCommit = (git rev-parse HEAD 2>$null).Trim()

        if (-not $CurrentCommit) {
            Stop-DeepSeek "Could not determine the Git revision after update check."
            return
        }

        $Updated = $BeforeUpdate -ne $CurrentCommit

        if ($Updated) {
            Write-Host ""
            Write-Host "[DeepSeek] Updated:" -ForegroundColor Green
            Write-Host "  $($BeforeUpdate.Substring(0, 8)) -> $($CurrentCommit.Substring(0, 8))"
        }
        elseif ($UpdateSucceeded) {
            Write-Host "[DeepSeek] Repository is already up to date." -ForegroundColor DarkGray
        }

        # --------------------------------------------------------
        # 5. Pin pnpm to the version declared by this checkout
        # --------------------------------------------------------

        if (-not (Initialize-DeepSeekPnpm -Repo $Repo)) {
            Stop-DeepSeek "Could not initialize the pnpm version required by DeepSeek Harness."
            return
        }

        # --------------------------------------------------------
        # 6. Decide whether install/build is required
        # --------------------------------------------------------

        if (-not (Test-Path $StateDir)) {
            New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
        }

        $LastBuiltCommit = $null

        if (Test-Path $BuildMarker) {
            $LastBuiltCommit = (Get-Content $BuildMarker -Raw).Trim()
        }

        $RepoNodeModules = Join-Path $Repo "node_modules"

        $NeedsBuild = (
            $Updated -or
            -not (Test-Path $RepoNodeModules) -or
            -not $LastBuiltCommit -or
            ($LastBuiltCommit -ne $CurrentCommit)
        )

        if ($NeedsBuild) {
            $buildOk = Invoke-DeepSeekBuild `
                -Repo $Repo `
                -CurrentCommit $CurrentCommit `
                -BuildMarker $BuildMarker `
                -ProfilesNodeModules $ProfilesNodeModules

            if (-not $buildOk) {
                Stop-DeepSeek "Automatic setup could not complete."
                return
            }
        }
        else {
            Write-Host "[DeepSeek] Existing build matches current source." -ForegroundColor DarkGray
        }

        # --------------------------------------------------------
        # 7. Launch
        # --------------------------------------------------------

        Write-DeepSeekStep "Launching DeepSeek Harness..."

        $launchResult = Invoke-DeepSeekPnpm dsh web

        if ($launchResult -ne 0) {
            Write-Host ""
            Write-Host "[DeepSeek] Harness exited with code $launchResult." -ForegroundColor Red
        }
    }
    finally {
        Pop-Location
    }
}
