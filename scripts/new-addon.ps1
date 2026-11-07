<#
.SYNOPSIS
    Scaffolds a new addon: addons\<Name>\ with a TOC, Core.lua and the shared PluvasUI library
    (Libs\PluvasUI), plus tests\<Name>\tests.lua.

.EXAMPLE
    .\scripts\new-addon.ps1 -Name PluvasBags -Title "Pluvas' Bags" -Notes "Bag sorting for WoW: Forever."
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
## Author: Pluvas
## Version: 0.1.0
## Category: Pluvas' addons
## IconTexture: Interface\Icons\INV_Misc_QuestionMark
## SavedVariables: ${Name}DB

Core.lua
"@

Write-File (Join-Path $addonDir 'Core.lua') @"
-- ${Title}: bootstrap, saved variables and events.
local ADDON, ns = ...

local DEFAULTS = {
	settings = {},
}

local frame = CreateFrame("Frame")
local handlers = {}

function ns:On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		pcall(frame.RegisterEvent, frame, event)
	end
	table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event] or {}) do
		local ok, err = pcall(fn, ...)
		if not ok then geterrorhandler()(err) end
	end
end)

function ns:Print(...)
	print(ns.PluvasUI.Prefix("$Title"), ...)
end

local function applyDefaults(target, defaults)
	for k, v in pairs(defaults) do
		if type(v) == "table" then
			if type(target[k]) ~= "table" then target[k] = {} end
			applyDefaults(target[k], v)
		elseif target[k] == nil then
			target[k] = v
		end
	end
end

ns:On("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	${Name}DB = ${Name}DB or {}
	applyDefaults(${Name}DB, DEFAULTS)
	ns.db = ${Name}DB
end)
"@

Write-File (Join-Path $testDir 'tests.lua') @"
-- ${Title}: tests. See tests/lib/harness.lua for test/eq/near/truthy.
local ns = _NS

_FIRE("ADDON_LOADED", "$Name")
_FIRE("PLAYER_LOGIN")

test("saved variables are created", function()
	truthy(ns.db, "ns.db")
	truthy(${Name}DB, "${Name}DB")
end)
"@

# Embed the shared UI library and load it first from the TOC.
& node (Join-Path $repo 'scripts\sync-shared.js') --embed $Name
if ($LASTEXITCODE -ne 0) { throw "Could not embed PluvasUI (is Node installed?)." }

Write-Host "Created addons\$Name and tests\$Name."
Write-Host "Next: npm test -- $Name, then .\scripts\install.ps1 (symlinks it into WoW; restart the game)."
Write-Host "Add the addon to the tables in README.md and AGENTS.md."
Write-Host "Build its UI with ns.PluvasUI: see shared\PluvasUI\README.md."
