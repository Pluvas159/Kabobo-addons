<#
.SYNOPSIS
    Installs the addons in this repo into the WoW: Forever client.

.DESCRIPTION
    By default every folder in addons\ is linked into <WoW>\_forever_\Interface\AddOns with a
    directory junction. The game then reads straight from this repo, so after an edit a /reload
    is enough. Junctions need no admin rights.

    An existing junction with the same name is replaced. A real folder with the same name (for
    example an older copied install) is moved to Interface\AddOns.backup\ first.

.PARAMETER WowPath
    The Forever client folder (the one containing Interface\ and Wow.exe).
    Defaults to $env:WOW_FOREVER_PATH, then the usual install locations.

.PARAMETER Addon
    Only install these addons (folder names). Default: all.

.PARAMETER Copy
    Copy the files instead of linking them (for a snapshot that does not follow the repo).

.PARAMETER Uninstall
    Remove the installed links/copies instead.

.EXAMPLE
    .\scripts\install.ps1
.EXAMPLE
    .\scripts\install.ps1 -Addon PluvasAuctions -WowPath "E:\Games\World of Warcraft\_forever_"
#>
[CmdletBinding()]
param(
    [string]$WowPath = $env:WOW_FOREVER_PATH,
    [string[]]$Addon,
    [switch]$Copy,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$addonsDir = Join-Path $repo 'addons'

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

$addOnsTarget = Join-Path $WowPath 'Interface\AddOns'
if (-not (Test-Path $addOnsTarget)) {
    New-Item -ItemType Directory -Path $addOnsTarget | Out-Null
}

$all = Get-ChildItem -Path $addonsDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName "$($_.Name).toc") }
if ($Addon) {
    $missing = $Addon | Where-Object { $all.Name -notcontains $_ }
    if ($missing) { throw "Unknown addon(s): $($missing -join ', ')" }
    $all = $all | Where-Object { $Addon -contains $_.Name }
}

function Test-Link([string]$path) {
    $item = Get-Item -LiteralPath $path -Force
    return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Remove-Existing([string]$path, [string]$name) {
    if (-not (Test-Path -LiteralPath $path)) { return }
    if (Test-Link $path) {
        # Removes only the link, never the files it points to.
        [IO.Directory]::Delete($path, $false)
        return
    }
    $backupRoot = Join-Path $WowPath 'Interface\AddOns.backup'
    if (-not (Test-Path $backupRoot)) { New-Item -ItemType Directory -Path $backupRoot | Out-Null }
    $backup = Join-Path $backupRoot ("{0}-{1:yyyyMMdd-HHmmss}" -f $name, (Get-Date))
    Move-Item -LiteralPath $path -Destination $backup
    Write-Host "  moved existing folder to $backup" -ForegroundColor Yellow
}

Write-Host "WoW: Forever AddOns folder: $addOnsTarget"
foreach ($a in $all) {
    $dest = Join-Path $addOnsTarget $a.Name
    if ($Uninstall) {
        if (Test-Path -LiteralPath $dest) {
            if (Test-Link $dest) { [IO.Directory]::Delete($dest, $false) }
            else { Remove-Existing $dest $a.Name }
            Write-Host "  removed $($a.Name)"
        }
        continue
    }
    Remove-Existing $dest $a.Name
    if ($Copy) {
        Copy-Item -Path $a.FullName -Destination $dest -Recurse
        Write-Host "  copied  $($a.Name)"
    } else {
        New-Item -ItemType Junction -Path $dest -Target $a.FullName | Out-Null
        Write-Host "  linked  $($a.Name) -> $($a.FullName)"
    }
}

if (-not $Uninstall) {
    Write-Host "Done. Restart WoW to pick up newly added addons; /reload is enough for changes to existing ones."
}
