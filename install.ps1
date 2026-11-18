<#
.SYNOPSIS
    Restores the exact Windows Terminal + PowerShell 7 setup from this backup
    on any Windows 10/11 machine, with a backup/restore safety net.

.USAGE
    powershell -ExecutionPolicy Bypass -File install.ps1
    powershell -ExecutionPolicy Bypass -File install.ps1 -Install       # skip the menu
    powershell -ExecutionPolicy Bypass -File install.ps1 -Backup        # backup only
    powershell -ExecutionPolicy Bypass -File install.ps1 -Restore       # restore only
    Flags -SkipPackages / -SkipFonts / -SkipBackup apply to the install path.

.DESCRIPTION
    On start the script asks what to do:
      [1] Install        set this PC up from the backup
      [2] Backup         save the machine's current terminal configs
      [3] Restore        put configs back from a saved backup

    Backups live under %LOCALAPPDATA%\terminal-setup\backups\<stamp>\
    and capture the machine's .gitconfig, both PowerShell profiles, the atuin
    config and the Windows Terminal settings hive, so anything this script
    touches is recoverable by name, not just by diffing .bak files.
    Install saves a backup automatically before changing anything.

    Install is idempotent: identical files are skipped, and every file it
    replaces is additionally saved as *.bak-<timestamp> in place.

    A .gitconfig that carries a [user] identity is MERGED, not replaced: the
    delta/lfs settings come from this backup and your identity keys are
    carried over. This is what keeps the README's "set your git identity,
    then re-run for Windows Terminal" order from wiping your name/email.

    What install does:
      0. Saves a backup of the machine's current configs (unless -SkipBackup)
      1. winget-installs the curated tool list (winget\terminal-packages.txt)
      2. Installs the bundled Meslo LG Nerd Fonts (per-user, no admin needed)
      3. Copies PowerShell 7 + Windows PowerShell 5.1 profiles to their
         default locations, and disables any leftover current-user
         all-hosts profile (…\profile.ps1) that would load on top of them
         and duplicate the fastfetch banner
      4. Copies atuin config to %USERPROFILE%\.config\atuin\config.toml
      5. Merges gitconfig into %USERPROFILE%\.gitconfig (delta pager etc.)
      6. Copies Windows Terminal settings.dat into the WT Settings folder
         (only after Windows Terminal has been launched at least once)

    Manual steps afterwards are listed in README.md (pick pwsh as the default
    Windows Terminal profile, set your git identity if this box has none yet).
#>

[CmdletBinding()]
param(
    [switch]$Install,      # go straight to the install action
    [switch]$Backup,       # go straight to the backup action
    [switch]$Restore,      # go straight to the restore-picker action
    [switch]$SkipPackages, # skip the winget install loop
    [switch]$SkipFonts,    # skip the bundled font install
    [switch]$SkipBackup    # install without the pre-install backup
)

$ErrorActionPreference = 'Stop'
$Root  = $PSScriptRoot
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Notes = [System.Collections.Generic.List[string]]::new()

# Machine-local snapshot library (deliberately outside the repo folder so
# re-cloning or pulling the repo never deletes your rollbacks).
$BackupRoot = Join-Path $env:LOCALAPPDATA 'terminal-setup\backups'

function Write-Step([string]$Message) {
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# Snapshot library: every target this script touches, by short name
# ---------------------------------------------------------------------------
function Get-SnapshotTargets {
    $targets = [ordered]@{
        'gitconfig'                = Join-Path $HOME '.gitconfig'
        'profile-pwsh7'            = Join-Path $HOME 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'
        'profile-ps51'             = Join-Path $HOME 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
        'atuin-config'             = Join-Path $HOME '.config\atuin\config.toml'
        'windows-terminal-settings' = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\Settings\settings.dat'
    }
    return $targets
}

function Copy-WithFallback {
    <# Copy-Item first; if the source is locked (Windows Terminal holds
       settings.dat open while running), fall back to robocopy, which
       retries through sharing violations. #>
    param([string]$Src, [string]$Dst)
    try {
        Copy-Item -LiteralPath $Src -Destination $Dst -Force -ErrorAction Stop
    } catch {
        $dir  = Split-Path $Dst -Parent
        $name = Split-Path $Dst -Leaf
        & robocopy.exe (Split-Path $Src -Parent) $dir (Split-Path $Src -Leaf) /R:3 /W:1 /NFL /NDL /NJH /NJS | Out-Null
        $rob = Join-Path $dir (Split-Path $Src -Leaf)
        if (Test-Path -LiteralPath $rob) {
            if (Test-Path -LiteralPath $Dst) { Remove-Item -LiteralPath $Dst -Force }
            Move-Item -LiteralPath $rob -Destination $Dst -Force
        } else { throw }
    }
}

function Backup-CurrentConfigs {
    <# Copies every present target into a fresh timestamped folder (its OWN
       timestamp - snapshots taken minutes apart within one run must never
       collide, e.g. the safety snapshot a restore takes).
       Returns the snapshot folder path, or $null when the machine has
       nothing to snapshot (fresh PC - the honest no-op). #>
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $targets = Get-SnapshotTargets
    $present = [ordered]@{}
    foreach ($k in $targets.Keys) {
        if (Test-Path -LiteralPath $targets[$k]) { $present[$k] = $targets[$k] }
    }
    if ($present.Count -eq 0) {
        Write-Host '    nothing to back up yet (fresh machine) - skipped.' -ForegroundColor DarkGray
        return $null
    }
    $dir = Join-Path $BackupRoot $stamp
    $n = 1
    while (Test-Path $dir) {
        $n++
        $dir = Join-Path $BackupRoot "$stamp-$n"
    }
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    foreach ($k in $present.Keys) {
        try {
            Copy-WithFallback -Src $present[$k] -Dst (Join-Path $dir $k)
            Write-Host ("    saved: {0}" -f $k) -ForegroundColor DarkGray
        } catch {
            Write-Host ("    [!] could not back up {0}: {1}" -f $k, $_.Exception.Message) -ForegroundColor Yellow
            $Notes += "Backup of '$k' failed - that file was not saved into $dir."
        }
    }
    return $dir
}

function Restore-FromSnapshot {
    <# Lists snapshots, lets the user pick one, and copies its files back to
       their real locations after taking a safety snapshot of the present
       state. Files in the snapshot that match no known target are skipped
       with a note rather than written somewhere blind. #>
    if (-not (Test-Path $BackupRoot)) {
        Write-Host '    no saved backups found - nothing to restore.' -ForegroundColor Yellow
        return
    }
    $snaps = @(Get-ChildItem $BackupRoot -Directory | Sort-Object Name -Descending)
    if ($snaps.Count -eq 0) {
        Write-Host '    no saved backups found - nothing to restore.' -ForegroundColor Yellow
        return
    }
    Write-Host ''
    Write-Host 'Saved backups (newest first):' -ForegroundColor Cyan
    $i = 0
    foreach ($s in $snaps) {
        $i++
        $files = (Get-ChildItem $s.FullName -File | ForEach-Object { $_.Name }) -join ', '
        Write-Host ("  [{0}] {1}  ({2})" -f $i, $s.Name, $files)
    }
    Write-Host '  [0] cancel'
    $pick = Read-Host "Restore which backup (0-$i)"
    if ($pick -notmatch '^\d+$' -or [int]$pick -lt 1 -or [int]$pick -gt $i) {
        Write-Host '    cancelled.' -ForegroundColor DarkGray
        return
    }
    $chosen = $snaps[[int]$pick - 1]

    # Safety first: the state we are leaving behind is itself snapshotted.
    $safety = Backup-CurrentConfigs

    $known = @{}
    foreach ($k in (Get-SnapshotTargets).Keys) { $known[$k] = (Get-SnapshotTargets)[$k] }

    foreach ($f in (Get-ChildItem $chosen.FullName -File)) {
        if (-not $known.Contains($f.Name)) {
            Write-Host ("    skipping unknown file in backup: {0}" -f $f.Name) -ForegroundColor Yellow
            $Notes += "Backup $($chosen.Name) contained unknown file '$($f.Name)' - left in the backup folder, not restored."
            continue
        }
        $dst = $known[$f.Name]
        $dstDir = Split-Path $dst -Parent
        if (-not (Test-Path $dstDir)) {
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
        Write-Host ("    restored: {0} -> {1}" -f $f.Name, $dst) -ForegroundColor Green
    }
    Write-Host ("    restored from backup {0}" -f $chosen.Name) -ForegroundColor Green
    if ($null -ne $safety) {
        Write-Host ("    previous state saved as a backup at {0}" -f $safety) -ForegroundColor DarkGray
    }
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

function Install-GitConfigWithIdentity {
    <# Installs git\gitconfig without destroying a [user] identity the
       machine already has: when the current .gitconfig carries user.* keys
       and git is on PATH, they are re-written onto the freshly installed
       file with `git config --file` (git's own writer, no ini parsing here).
       The old file is .bak'd by Copy-ConfigFile either way, and a full
       snapshot exists from the pre-install step. Falls back to a plain
       replace (plus a loud note) when git is not on PATH yet - e.g. during
       a -SkipPackages run on a machine that has no git.
       Returns 'identical' | 'installed' | 'replaced' | 'merged'. #>
    $src = Join-Path $Root 'git\gitconfig'
    $dst = Join-Path $HOME '.gitconfig'
    if (Test-Path $dst) {
        $same = (Get-FileHash $src).Hash -eq (Get-FileHash $dst).Hash
        if ($same) { return 'identical' }
    }

    $identity = @()
    if ((Test-Path $dst) -and (Get-Command git -ErrorAction SilentlyContinue)) {
        $identity = @(& git config --file $dst --get-regexp '^user\.' 2>$null)
    }

    $state = Copy-ConfigFile -Src $src -Dst $dst

    if ($identity.Count -gt 0) {
        foreach ($line in $identity) {
            $key, $value = $line -split ' ', 2
            & git config --file $dst $key $value
        }
        Write-Host "    existing git identity carried over ($($identity.Count) keys)" -ForegroundColor Green
        return 'merged'
    }

    if ((Test-Path "$dst.bak-$Stamp") -and -not (Get-Command git -ErrorAction SilentlyContinue)) {
        $Notes += 'An existing .gitconfig was replaced but git was not on PATH to detect a [user] identity. If your name/email disappeared, they are in the .bak copy next to it and in the pre-install backup.'
    }
    return $state
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

# ---------------------------------------------------------------------------
# Action menu
# ---------------------------------------------------------------------------
Write-Host 'Windows Terminal setup installer' -ForegroundColor Green
Write-Host "Backup source: $Root"
Write-Host "Backup library: $BackupRoot"

$actions = @('install')
if (-not $Install -and -not $Backup -and -not $Restore) {
    Write-Host ''
    Write-Host '[1] Install - set up this PC from the backup (saves your current configs first)'
    Write-Host '[2] Backup  - save this PC''s current terminal configs'
    Write-Host '[3] Restore - put configs back from a saved backup'
    Write-Host '[0] Quit'
    $choice = Read-Host 'Choose an action'
    switch ($choice) {
        '1' { $actions = @('install') }
        '2' { $actions = @('backup') }
        '3' { $actions = @('restore') }
        default {
            Write-Host 'Bye.' -ForegroundColor DarkGray
            exit 0
        }
    }
}
if ($Install) { $actions = @('install') }
if ($Backup)  { $actions = @($actions + 'backup'  | Select-Object -Unique) }
if ($Restore) { $actions = @($actions + 'restore' | Select-Object -Unique) }

foreach ($action in $actions) {

if ($action -eq 'backup') {
    Write-Step 'Saving a backup of the current terminal configs'
    $dir = Backup-CurrentConfigs
    if ($null -ne $dir) {
        Write-Host "    backup saved at $dir" -ForegroundColor Green
    }
    continue
}

if ($action -eq 'restore') {
    Write-Step 'Restoring terminal configs from a saved backup'
    Restore-FromSnapshot
    continue
}

# ------------------------------- install ----------------------------------
if (-not $SkipBackup) {
    Write-Step 'Saving a backup of the current configs before installing'
    $dir = Backup-CurrentConfigs
    if ($null -ne $dir) {
        Write-Host "    backup saved at $dir" -ForegroundColor Green
    }
}

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

    $regValues = @((Get-Item $regKey).Property)
    $copiedCount = 0
    $registeredCount = 0
    foreach ($f in $fonts) {
        $target = Join-Path $fontDir $f.Name
        $presentOnDisk = (Test-Path $target) -and
            ((Get-FileHash $f.FullName).Hash -eq (Get-FileHash $target).Hash)

        if (-not $presentOnDisk) {
            Copy-Item $f.FullName $target -Force
            $copiedCount++
        }

        # Register even when the bytes were already on disk: a font copied
        # there by another route has no HKCU entry and stays invisible to
        # apps until it does. Only notify for names not yet registered.
        $displayName = Get-FontDisplayName $target
        if ($regValues -notcontains $displayName) {
            New-ItemProperty -Path $regKey -Name $displayName -Value $target -PropertyType String -Force | Out-Null
            $regValues += $displayName
            try   { [Win32.FontNotify]::AddFontResourceEx($target, 0, [IntPtr]::Zero) | Out-Null } catch { }
            $registeredCount++
        }
    }

    if ($registeredCount) {
        try {
            $hwndBroadcast = [IntPtr]0xffff
            $result = [IntPtr]::Zero
            # WM_FONTCHANGE = 0x001D, HWND_BROADCAST, SMTO_NORMAL
            [Win32.FontNotify]::SendMessageTimeout($hwndBroadcast, 0x001D, [IntPtr]::Zero, [IntPtr]::Zero, 0x2, 1000, [ref]$result) | Out-Null
        } catch { }
    }

    Write-Host "    $copiedCount / $($fonts.Count) font files copied, $registeredCount newly registered for this user."
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
# 5. git config (delta pager, side-by-side diffs, zdiff3) - identity-safe
# ---------------------------------------------------------------------------
Write-Step 'Installing git config (identity-preserving)'

$state = Install-GitConfigWithIdentity
Write-Host "    gitconfig: $state -> $(Join-Path $HOME '.gitconfig')"
if ($state -in @('installed', 'replaced')) {
    $Notes += 'No git identity was found on this machine (the backup intentionally carries none). Set it once: git config --global user.name "Your Name"; git config --global user.email you@example.com'
}

# ---------------------------------------------------------------------------
# 6. Windows Terminal settings hive
# ---------------------------------------------------------------------------
Write-Step 'Installing Windows Terminal settings'

$wtSettings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\Settings'
if (-not (Test-Path $wtSettings)) {
    $Notes += 'Windows Terminal has never been launched on this PC yet - launch it once, then re-run install.ps1 to apply settings.dat. Re-running is safe: your git identity survives it now, and every re-run saves a fresh backup first.'
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
}
