<#
.SYNOPSIS
    Restores the exact Windows Terminal + PowerShell 7 setup from this backup
    on any Windows 10/11 machine.

.USAGE
    powershell -ExecutionPolicy Bypass -File install.ps1

.DESCRIPTION
    Idempotent: safe to run multiple times. Existing files are backed up as
    *.bak-<timestamp> before being replaced (identical files are skipped).

    What it does:
      1. winget-installs the curated tool list (winget\terminal-packages.txt)
      2. Installs the bundled Meslo LG Nerd Fonts (per-user, no admin needed)
      3. Copies PowerShell 7 + Windows PowerShell 5.1 profiles to their
         default locations, and disables any leftover current-user
         all-hosts profile (…\profile.ps1) that would load on top of them
         and duplicate the fastfetch banner
      4. Copies atuin config to %USERPROFILE%\.config\atuin\config.toml
      5. Copies gitconfig to %USERPROFILE%\.gitconfig (delta pager etc.)
      6. Copies Windows Terminal settings.dat into the WT Settings folder
         (only after Windows Terminal has been launched at least once)

    Manual steps afterwards are listed in README.md (set pwsh as the default
    Windows Terminal profile, fix git user/email, re-open your PC if the
    font did not appear immediately).
#>

[CmdletBinding()]
param(
    [switch]$SkipPackages,   # skip the winget install loop
    [switch]$SkipFonts       # skip the bundled font install
)

$ErrorActionPreference = 'Stop'
$Root   = $PSScriptRoot
$Stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$Notes  = [System.Collections.Generic.List[string]]::new()

function Write-Step([string]$Message) {
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Copy-ConfigFile {
    <# Copies $Src onto $Dst, backing up any different existing file first.
       Returns 'identical' | 'installed' | 'replaced'. #>
    param(
        [Parameter(Mandatory)][string]$Src,
        [Parameter(Mandatory)][string]$Dst
    )

    $srcDir = Split-Path $Dst -Parent
    if (-not (Test-Path $srcDir)) {
        New-Item -ItemType Directory -Path $srcDir -Force | Out-Null
    }

    if (Test-Path $Dst) {
        $same = (Get-FileHash $Src).Hash -eq (Get-FileHash $Dst).Hash
        if ($same) { return 'identical' }
        $bak = "$Dst.bak-$Stamp"
        Copy-Item $Dst $bak -Force
        Copy-Item $Src $Dst -Force
        return 'replaced'
    }

    Copy-Item $Src $Dst -Force
    return 'installed'
}

function Get-FontDisplayName([string]$Path) {
    <# Returns the registry value name (e.g. "MesloLGS Nerd Font Regular (TrueType)")
       by reading the real name table out of the font file. #>
    try {
        Add-Type -AssemblyName PresentationCore -ErrorAction Stop
        $gt      = New-Object System.Windows.Media.GlyphTypeface([Uri]$Path)
        $culture = [Globalization.CultureInfo]::InvariantCulture

        $family = $gt.FamilyNames[$culture]
        $face   = $gt.Typefaces[$culture]

        if ($family -and $face) {
            return "$($family[0]) $($face[0]) (TrueType)"
        }
    } catch { }

    # Fallback: derive a readable name from the file name
    $base = [IO.Path]::GetFileNameWithoutExtension($Path)
    return "$($base -replace '-', ' ') (TrueType)"
}

Write-Host 'Windows Terminal setup installer' -ForegroundColor Green
Write-Host "Backup source: $Root"

# ---------------------------------------------------------------------------
# 1. Packages (winget)
# ---------------------------------------------------------------------------
if (-not $SkipPackages) {
    Write-Step 'Installing terminal toolchain with winget'

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Host '[!] winget was not found. Install "App Installer" from the Microsoft Store, then re-run.' -ForegroundColor Red
        Write-Host '    (You can re-run with -SkipPackages to restore only the config files.)'
        exit 1
    }

    $pkgListPath = Join-Path $Root 'winget\terminal-packages.txt'
    $packages    = Get-Content $pkgListPath | Where-Object { $_.Trim() }

    foreach ($id in $packages) {
        $id = $id.Trim()
        # winget list exits non-zero when the exact --id is not installed
        winget list --id $id -e --accept-source-agreements *> $null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    already installed: $id" -ForegroundColor DarkGray
            continue
        }

        Write-Host "    installing: $id"
        winget install --id $id -e --silent --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) {
            $Notes += "winget failed for '$id' (exit $LASTEXITCODE) - install it manually."
            Write-Host "    [!] failed: $id" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host '(-SkipPackages: winget step skipped)' -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# 2. Fonts (per-user install: copy + register + notify)
# ---------------------------------------------------------------------------
if (-not $SkipFonts) {
    Write-Step 'Installing bundled fonts for the current user'

    $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    if (-not (Test-Path $fontDir)) {
        New-Item -ItemType Directory -Path $fontDir -Force | Out-Null
    }

    $regKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    if (-not (Test-Path $regKey)) {
        New-Item -Path $regKey -Force | Out-Null
    }

    if (-not ('Win32.FontNotify' -as [type])) {
        Add-Type -Name FontNotify -Namespace Win32 -MemberDefinition @'
[DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
public static extern int AddFontResourceEx(string lpszFilename, uint fl, IntPtr pdv);

[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam,
    uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
'@ -ErrorAction SilentlyContinue
    }

    $fonts = Get-ChildItem (Join-Path $Root 'fonts') -Filter '*.ttf' -File
    if (-not $fonts) { $fonts = Get-ChildItem (Join-Path $Root 'fonts') -Filter '*.otf' -File }

    $installedCount = 0
    foreach ($f in $fonts) {
        $target = Join-Path $fontDir $f.Name
        if ((Test-Path $target) -and
            ((Get-FileHash $f.FullName).Hash -eq (Get-FileHash $target).Hash)) {
            $installedCount++
            continue
        }
        Copy-Item $f.FullName $target -Force

        $displayName = Get-FontDisplayName $target
        New-ItemProperty -Path $regKey -Name $displayName -Value $target -PropertyType String -Force | Out-Null

        try   { [Win32.FontNotify]::AddFontResourceEx($target, 0, [IntPtr]::Zero) | Out-Null } catch { }
        $installedCount++
    }

    if ($installedCount) {
        try {
            $hwndBroadcast = [IntPtr]0xffff
            $result = [IntPtr]::Zero
            # WM_FONTCHANGE = 0x001D, HWND_BROADCAST, SMTO_NORMAL
            [Win32.FontNotify]::SendMessageTimeout($hwndBroadcast, 0x001D, [IntPtr]::Zero, [IntPtr]::Zero, 0x2, 1000, [ref]$result) | Out-Null
        } catch { }
    }

    Write-Host "    $installedCount / $($fonts.Count) fonts present for this user."
    $Notes += 'If a font does not appear in Windows Terminal right away, sign out and back in (or reboot) once.'
} else {
    Write-Host '(-SkipFonts: font step skipped)' -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# 3. PowerShell profiles
# ---------------------------------------------------------------------------
Write-Step 'Installing PowerShell profiles'

$profileTargets = @(
    @{ Src = (Join-Path $Root 'pwsh\pwsh7.Microsoft.PowerShell_profile.ps1');
       Dst = (Join-Path $HOME 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1');
       Label = 'PowerShell 7 (pwsh) current-user profile' }
    @{ Src = (Join-Path $Root 'pwsh\ps5.1.Microsoft.PowerShell_profile.ps1');
       Dst = (Join-Path $HOME 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1');
       Label = 'Windows PowerShell 5.1 current-user profile' }
)

foreach ($t in $profileTargets) {
    $state = Copy-ConfigFile -Src $t.Src -Dst $t.Dst
    $color = switch ($state) { 'identical' { 'DarkGray' } 'replaced' { 'Yellow' } default { 'Green' } }
    Write-Host ("    {0}: {1} -> {2}" -f $t.Label, $state, $t.Dst) -ForegroundColor $color
}

# PowerShell dot-sources the current-user ALL-HOSTS profiles (…\profile.ps1)
# *before* the host-specific files installed above. A leftover from an older
# setup usually carries its own oh-my-posh + fastfetch startup, which shows up
# as a duplicated banner. This backup owns only the host-specific files, so any
# all-hosts profile found here is moved aside (not deleted) to keep startups
# single-banner and predictable.
$allHostsProfiles = @(
    @{ Dst = (Join-Path $HOME 'Documents\PowerShell\profile.ps1');
       Label = 'PowerShell 7 (pwsh) current-user, all-hosts profile' }
    @{ Dst = (Join-Path $HOME 'Documents\WindowsPowerShell\profile.ps1');
       Label = 'Windows PowerShell 5.1 current-user, all-hosts profile' }
)

foreach ($t in $allHostsProfiles) {
    if (-not (Test-Path $t.Dst)) {
        Write-Host ("    {0}: none" -f $t.Label) -ForegroundColor DarkGray
        continue
    }

    $moved = "$($t.Dst).bak-$Stamp"
    Move-Item -LiteralPath $t.Dst -Destination $moved -Force
    Write-Host ("    {0}: leftover found, disabled -> {1}" -f $t.Label, $moved) -ForegroundColor Yellow
    $Notes += ("{0} was not created by this backup and was moved to '{1}'. Review it before re-enabling: anything there runs in addition to the profiles from this repo." -f $t.Label, $moved)
}

# ---------------------------------------------------------------------------
# 4. atuin config
# ---------------------------------------------------------------------------
Write-Step 'Installing atuin config'

$atuinDst = Join-Path $HOME '.config\atuin\config.toml'
$state = Copy-ConfigFile -Src (Join-Path $Root 'atuin\config.toml') -Dst $atuinDst
Write-Host "    atuin config: $state -> $atuinDst"

# ---------------------------------------------------------------------------
# 5. git config (delta pager, side-by-side diffs, zdiff3)
# ---------------------------------------------------------------------------
Write-Step 'Installing git config'

$gitDst = Join-Path $HOME '.gitconfig'
$state = Copy-ConfigFile -Src (Join-Path $Root 'git\gitconfig') -Dst $gitDst
Write-Host "    gitconfig: $state -> $gitDst"
$Notes += 'No git identity in the backup (kept out on purpose). Set it once: git config --global user.name "Your Name"; git config --global user.email you@example.com'

# ---------------------------------------------------------------------------
# 6. Windows Terminal settings hive
# ---------------------------------------------------------------------------
Write-Step 'Installing Windows Terminal settings'

$wtSettings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\Settings'
if (-not (Test-Path $wtSettings)) {
    $Notes += 'Windows Terminal has never been launched on this PC yet - launch it once, then re-run install.ps1 to apply settings.dat.'
    Write-Host '    Windows Terminal Settings folder not found (launch WT once, then re-run).' -ForegroundColor Yellow
} else {
    $state = Copy-ConfigFile -Src (Join-Path $Root 'windows-terminal\settings.dat') -Dst (Join-Path $wtSettings 'settings.dat')
    Write-Host "    settings.dat: $state"
    Write-Host '    (Your backup was captured while WT used the registry-hive storage mode and no custom UI settings.)' -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
Write-Step 'Verification checklist'
Write-Host @'
  [ ] Close all terminals, open Windows Terminal and start a "PowerShell" (pwsh) tab
  [ ] Prompt shows the gruvbox Oh-My-Posh theme; fastfetch banner appears exactly once
  [ ] Type a partial command + UpArrow  -> history search (atuin/PSReadLine)
  [ ] ls / ll / lt                       -> eza listing with icons
  [ ] cat somefile                       -> bat
  [ ] grep pattern .                     -> ripgrep
  [ ] z <dir> / zi                       -> zoxide jump (+ auto listing)
'@

if ($Notes.Count) {
    Write-Host ''
    Write-Host 'Follow-up notes:' -ForegroundColor Yellow
    foreach ($n in $Notes) { Write-Host "  - $n" -ForegroundColor Yellow }
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
