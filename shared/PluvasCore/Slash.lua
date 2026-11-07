-- PluvasCore: slash commands from a table, with the help text generated from it.
local ADDON, ns = ...

local function onOff(v) return v and "on" or "off" end

local function describe(c)
	local help = c.help
	if type(help) == "function" then help = help() end
	if c.toggle then help = (help or c.toggle) .. ": " .. onOff(ns.db.settings[c.toggle]) end
	return help
end

local function helpLine(alias, c)
	local usage = "  " .. alias
	if c.cmd ~= "" then usage = usage .. " " .. c.cmd end
	if c.args then usage = usage .. " " .. c.args end
	local help = describe(c)
	return help and (usage .. " - " .. help) or usage
end

-- Registers slash commands (globals SLASH_<ADDON>n and SlashCmdList.<ADDON>).
--   aliases   { "/pa", "/pluvas" }
--   commands  array of
--     { cmd = "scan", args = "<item link>", help = "what it does", run = function(rest) end }
--     { cmd = "tooltip", toggle = "settingKey", help = "what the setting does" }
--   A toggle flips ns.db.settings[key], prints the new state and sends the addon message
--   SettingChanged(key, value). hidden = true leaves a command out of the help. cmd = "" runs
--   for a bare /alias. "help" and a hidden "debug" toggle are added; unknown commands print
--   the help.
function ns:Slash(aliases, commands)
	local list, byName = {}, {}
	local function add(c)
		list[#list + 1] = c
		byName[c.cmd] = c
	end
	for _, c in ipairs(commands) do add(c) end

	local function printHelp()
		ns:Print("v" .. ns.version .. " commands:")
		for _, c in ipairs(list) do
			if not c.hidden then print(helpLine(aliases[1], c)) end
		end
	end
	if not byName.help then add({ cmd = "help", help = "list these commands", run = printHelp }) end
	if not byName.debug then add({ cmd = "debug", toggle = "debug", help = "debug output", hidden = true }) end

	local key = ADDON:upper()
	for i, alias in ipairs(aliases) do _G["SLASH_" .. key .. i] = alias end
	SlashCmdList[key] = function(msg)
		local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
		local c = byName[(cmd or ""):lower()]
		if not c then return printHelp() end
		if c.toggle then
			local s = ns.db.settings
			s[c.toggle] = not s[c.toggle]
			ns:Print(describe(c))
			ns:Send("SettingChanged", c.toggle, s[c.toggle])
		else
			c.run(rest or "")
		end
	end
end
