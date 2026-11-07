<#
.SYNOPSIS
    Symlinks every addon in this repo into the WoW: Forever client.

.DESCRIPTION
    Every folder in addons\ that has a matching <Name>.toc is linked into
    <WoW>\_forever_\Interface\AddOns\<Name> as a directory symbolic link. The game then reads
    straight from this repo: after an edit, /reload is enough. Newly added addons need a restart.

    The script is safe to run any number of times:
      - links that already point at the right folder are left alone
      - links pointing somewhere else (or junctions from older installs) are replaced
      - a real folder with the same name (an old copied install) is moved to
        Interface\AddOns.backup\ instead of being deleted
      - links into this repo whose addon no longer exists (renamed/removed) are removed
      - addons that do not come from this repo are never touched

    Symbolic links need Windows Developer Mode or an elevated shell. Without either, the script
    falls back to directory junctions (same effect for the game) and says so.

.PARAMETER WowPath
    The Forever client folder (contains Interface\). Defaults to $env:WOW_FOREVER_PATH, then the
    usual install locations.

.PARAMETER Addon
    Only install these addons (folder names). Default: all. Stale links are only pruned when
    installing all addons.

.PARAMETER Junction
    Use directory junctions instead of symbolic links.

.PARAMETER Copy
    Copy the files instead of linking them (a snapshot that does not follow the repo).

.PARAMETER Status
    Only report what is installed; change nothing.

.PARAMETER Uninstall
    Remove this repo's addons from the game folder.

.EXAMPLE
    .\scripts\install.ps1
.EXAMPLE
    .\scripts\install.ps1 -Status
.EXAMPLE
    .\scripts\install.ps1 -Addon KaboboAuctions -WowPath "E:\Games\World of Warcraft\_forever_"
#>
[CmdletBinding()]
param(
    [string]$WowPath = $env:WOW_FOREVER_PATH,
    [string[]]$Addon,
    [switch]$Junction,
    [switch]$Copy,
    [switch]$Status,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$addonsDir = (Resolve-Path (Join-Path $repo 'addons')).Path

# --- Locate the game -----------------------------------------------------------------------

if (-not $WowPath) {
    $candidates = @(
        'D:\World of Warcraft\_forever_',
        'C:\Program Files (x86)\World of Warcraft\_forever_',
        'C:\Program Files\World of Warcraft\_forever_',
        'E:\World of Warcraft\_forever_'
    )
    $WowPath = $candidates | Where-Object { Test-Path (Join-Path $_ 'Interface') } | Select-Object -First 1
    if (-not $WowPath) {
        throw "Could not find the WoW: Forever folder. Pass -WowPath or set WOW_FOREVER_PATH."
    }
}
if (-not (Test-Path $WowPath)) { throw "WoW folder not found: $WowPath" }

$gameAddOns = Join-Path $WowPath 'Interface\AddOns'
if (-not (Test-Path $gameAddOns)) {
    if ($Status -or $Uninstall) { throw "No AddOns folder at $gameAddOns" }
    New-Item -ItemType Directory -Path $gameAddOns | Out-Null
}

# --- Helpers -------------------------------------------------------------------------------

function Normalize([string]$path) {
    if (-not $path) { return '' }
    return [IO.Path]::GetFullPath($path).TrimEnd('\').ToLowerInvariant()
}

# Returns $null when nothing is there, otherwise kind (SymbolicLink | Junction | Folder | File)
# and, for links, the folder they point at.
function Get-Entry([string]$path) {
    $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $null }
    $isLink = [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
    $kind = if ($isLink) { if ($item.LinkType) { [string]$item.LinkType } else { 'Link' } }
            elseif ($item.PSIsContainer) { 'Folder' } else { 'File' }
    $target = if ($isLink) { @($item.Target)[0] } else { $null }
    return [pscustomobject]@{ Kind = $kind; IsLink = $isLink; Target = $target }
}

function Remove-Link([string]$path) {
    # Deletes only the link itself, never the files it points to.
    [IO.Directory]::Delete($path, $false)
}

function Backup-Folder([string]$path, [string]$name) {
    $backupRoot = Join-Path $WowPath 'Interface\AddOns.backup'
    if (-not (Test-Path $backupRoot)) { New-Item -ItemType Directory -Path $backupRoot | Out-Null }
    $backup = Join-Path $backupRoot ("{0}-{1:yyyyMMdd-HHmmss}" -f $name, (Get-Date))
    Move-Item -LiteralPath $path -Destination $backup
    Write-Host ("  {0,-24} existing folder moved to {1}" -f $name, $backup) -ForegroundColor Yellow
}

$script:symlinkFailed = $false
function New-Link([string]$path, [string]$target) {
    if (-not $Junction -and -not $script:symlinkFailed) {
        # mklink can create unprivileged symlinks under Developer Mode; New-Item in
        # Windows PowerShell 5.1 cannot.
        $out = & cmd.exe /d /c "mklink /D `"$path`" `"$target`"" 2>&1
        if ($LASTEXITCODE -eq 0) { return 'SymbolicLink' }
        $script:symlinkFailed = $true
        Write-Host "  Symbolic links are not allowed here ($out)." -ForegroundColor Yellow
        Write-Host "  Turn on Windows Developer Mode or run elevated to get symlinks. Using junctions." -ForegroundColor Yellow
    }
    New-Item -ItemType Junction -Path $path -Target $target | Out-Null
    return 'Junction'
}

function Write-Line([string]$name, [string]$state, [string]$color = 'Gray') {
    Write-Host ("  {0,-24} {1}" -f $name, $state) -ForegroundColor $color
}

# --- Addons in this repo -------------------------------------------------------------------

$all = @(Get-ChildItem -Path $addonsDir -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName "$($_.Name).toc") } |
    Sort-Object Name)
$selected = $all
if ($Addon) {
    $missing = @($Addon | Where-Object { $all.Name -notcontains $_ })
    if ($missing.Count) { throw "Unknown addon(s): $($missing -join ', '). Known: $($all.Name -join ', ')" }
    $selected = @($all | Where-Object { $Addon -contains $_.Name })
}
$wantType = if ($Copy) { 'Folder' } elseif ($Junction) { 'Junction' } else { 'SymbolicLink' }

Write-Host "Repo:   $addonsDir"
Write-Host "Game:   $gameAddOns"
Write-Host ""

# --- Status --------------------------------------------------------------------------------

if ($Status) {
    foreach ($a in $all) {
        $e = Get-Entry (Join-Path $gameAddOns $a.Name)
        if (-not $e) { Write-Line $a.Name 'not installed' 'Yellow'; continue }
        if ($e.IsLink) {
            if ((Normalize $e.Target) -eq (Normalize $a.FullName)) { Write-Line $a.Name "$($e.Kind) -> repo" 'Green' }
            else { Write-Line $a.Name "$($e.Kind) -> $($e.Target) (not this repo)" 'Yellow' }
        } else {
            Write-Line $a.Name "$($e.Kind) (copied, does not follow the repo)" 'Yellow'
        }
    }
    return
}

# --- Uninstall -----------------------------------------------------------------------------

if ($Uninstall) {
    foreach ($a in $selected) {
        $dest = Join-Path $gameAddOns $a.Name
        $e = Get-Entry $dest
        if (-not $e) { Write-Line $a.Name 'not installed'; continue }
        if ($e.IsLink) { Remove-Link $dest; Write-Line $a.Name 'link removed' 'Green' }
        else { Backup-Folder $dest $a.Name }
    }
    return
}

# --- Install -------------------------------------------------------------------------------

foreach ($a in $selected) {
    $dest = Join-Path $gameAddOns $a.Name
    $e = Get-Entry $dest

    if ($e -and $e.IsLink -and -not $Copy -and (Normalize $e.Target) -eq (Normalize $a.FullName) `
            -and ($e.Kind -eq $wantType -or ($script:symlinkFailed -and $e.Kind -eq 'Junction'))) {
        Write-Line $a.Name "up to date ($($e.Kind))" 'Green'
        continue
    }

    if ($e) {
        if ($e.IsLink) { Remove-Link $dest } else { Backup-Folder $dest $a.Name }
    }

    if ($Copy) {
        Copy-Item -Path $a.FullName -Destination $dest -Recurse
        Write-Line $a.Name 'copied' 'Green'
    } else {
        $made = New-Link $dest $a.FullName
        $verb = if ($e) { 'relinked' } else { 'linked' }
        Write-Line $a.Name "$verb ($made)" 'Green'
    }
}

# Remove links into this repo whose addon no longer exists here (only on a full install).
if (-not $Addon) {
    $prefix = (Normalize $addonsDir) + '\'
    $names = @($all.Name)
    foreach ($item in Get-ChildItem -LiteralPath $gameAddOns -Force -Directory) {
        $e = Get-Entry $item.FullName
        if (-not $e -or -not $e.IsLink) { continue }
        $target = Normalize $e.Target
        if ($target.StartsWith($prefix) -and ($names -notcontains $item.Name -or -not (Test-Path -LiteralPath $e.Target))) {
            Remove-Link $item.FullName
            Write-Line $item.Name 'stale link removed (addon no longer in repo)' 'Yellow'
        }
    }
}

Write-Host ""
Write-Host "Done. Restart WoW to load newly added addons; /reload picks up changes to existing ones."
