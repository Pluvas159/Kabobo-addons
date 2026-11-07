<#
.SYNOPSIS
    Scaffolds a new addon: addons\<Name>\ with a TOC, Core.lua and the shared KaboboUI library
    (Libs\KaboboUI), plus tests\<Name>\tests.lua.

.EXAMPLE
    .\scripts\new-addon.ps1 -Name KaboboBags -Title "Kabobo's Bags" -Notes "Bag sorting for WoW: Forever."
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Z][A-Za-z0-9]+$')][string]$Name,
    [string]$Title = $Name,
    [string]$Notes = ''
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$addonDir = Join-Path $repo "addons\$Name"
$testDir = Join-Path $repo "tests\$Name"

if (Test-Path $addonDir) { throw "addons\$Name already exists." }

$utf8 = New-Object System.Text.UTF8Encoding($false)
function Write-File([string]$path, [string]$text) {
    [IO.File]::WriteAllText($path, ($text -replace "`r`n", "`n"), $utf8)
}

New-Item -ItemType Directory -Path $addonDir, $testDir -Force | Out-Null

Write-File (Join-Path $addonDir "$Name.toc") @"
## Interface: 16001
## Title: $Title
## Notes: $Notes
## Author: Kabobo
## Version: 0.1.0
## Category: Kabobo's addons
## IconTexture: Interface\Icons\INV_Misc_QuestionMark
## SavedVariables: ${Name}DB

Core.lua
"@

Write-File (Join-Path $addonDir 'Core.lua') @"
-- ${Title}: saved variables and slash commands.
--
-- The runtime (events, addon messages, modules, error guards, identity) comes from
-- Libs/KaboboCore, the look from Libs/KaboboUI. Put features in their own files, each a module:
--   local M = ns:NewModule("Thing")   function M:OnLogin() end
--
-- Addon messages: (list the ones this addon sends here)
local _, ns = ...

ns:Setup({
	title = "$Title",
	savedVariables = "${Name}DB",
	dbVersion = 1,
	defaults = {
		settings = {},
	},
})

ns:Slash({ "/$($Name.ToLower())" }, {
	{ cmd = "", help = "say hello", run = function() ns:Print("hello, " .. tostring(ns.charName)) end },
})
"@

Write-File (Join-Path $testDir 'tests.lua') @"
-- ${Title}: tests. See tests/lib/harness.lua for test/eq/near/truthy.
local ns = _NS

_FIRE("ADDON_LOADED", "$Name")
_FIRE("PLAYER_LOGIN")

test("saved variables are created", function()
	truthy(ns.db, "ns.db")
	truthy(${Name}DB, "${Name}DB")
	eq(${Name}DB.dbVersion, 1)
end)
"@

# Embed every shared library (KaboboCore, KaboboUI) and load them first from the TOC.
& node (Join-Path $repo 'scripts\sync-shared.js') --embed $Name
if ($LASTEXITCODE -ne 0) { throw "Could not embed the shared libraries (is Node installed?)." }

Write-Host "Created addons\$Name and tests\$Name."
Write-Host "Next: npm test -- $Name, then .\scripts\install.ps1 (symlinks it into WoW; restart the game)."
Write-Host "Add the addon to the tables in README.md and AGENTS.md."
Write-Host "Runtime: shared\KaboboCore\README.md. UI: shared\KaboboUI\README.md."
