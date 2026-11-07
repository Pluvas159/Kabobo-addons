-- Pluvas' Professions: bootstrap, saved variables, events and slash commands.
local ADDON, ns = ...

ns.name = ADDON
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"

local DB_VERSION = 1

local DEFAULTS = {
	settings = {
		panel = false,             -- open the unlearned list next to the profession window
		trainerUnavailable = true, -- make profession trainers list recipes you cannot learn yet
		hideUnknown = false,       -- leave out recipes the client gives no source for
		-- Collapsed groups in the list: [groupKey] = true. Expanding stores false, so the default
		-- below does not come back on the next load. Forever gives no source text for most
		-- recipes, so that pile starts collapsed.
		collapsed = { unknown = true },
	},
	-- Trainer catalog, shared by every character: what each profession's trainers teach.
	-- [professionName] = { [lowercase recipe name] = { n = name, s = skill, lv = level,
	--   c = copper, ic = icon, w = trainer name, z = zone } }
	trainer = {},
	-- Vendor catalog, shared by every character: who sells the item that teaches a recipe.
	-- [lowercase recipe name] = { v = vendor, z = zone, c = copper, it = item name, lim = limited }
	vendor = {},
	-- Per character: [realm-name] = { [professionName] = profession entry, see Data.lua }
	chars = {},
}

-- Error containment ---------------------------------------------------------
--
-- Lua errors never crash the game, but an error in an event handler repeats every time it runs.
-- ns:Guard reports the first errors and turns the guarded code off for the rest of the session
-- after MAX_ERRORS, so a bug degrades one feature instead of spamming errors.

local MAX_ERRORS = 3
ns.disabled = {}

function ns:Guard(name, fn)
	local errors = 0
	local function finish(ok, ...)
		if ok then return ... end
		local err = ...
		errors = errors + 1
		if errors >= MAX_ERRORS then
			ns.disabled[name] = true
			ns:Print(name .. " hit repeated errors and is turned off until /reload.")
		end
		geterrorhandler()(name .. ": " .. tostring(err))
	end
	return function(...)
		if ns.disabled[name] then return end
		return finish(pcall(fn, ...))
	end
end

-- Event dispatch ----------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}

function ns:On(event, fn)
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
		-- Unknown events raise an error on the modern client; never let one break loading.
		if not pcall(frame.RegisterEvent, frame, event) then
			ns:Debug("could not register event", event)
		end
	end
	list[#list + 1] = ns:Guard(event .. " handler #" .. (#list + 1), fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do
		list[i](...)
	end
end)

-- Output ------------------------------------------------------------------

local PREFIX = "|cff22b8cfPluvas' Professions|r:"

function ns:Print(...)
	print(PREFIX, ...)
end

function ns:Debug(...)
	if ns.db and ns.db.settings.debug then
		print("|cff888888[PP debug]|r", ...)
	end
end

-- Saved variables ---------------------------------------------------------

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

local function initDB()
	PluvasProfessionsDB = PluvasProfessionsDB or {}
	local db = PluvasProfessionsDB
	applyDefaults(db, DEFAULTS)
	db.dbVersion = db.dbVersion or DB_VERSION
	ns.db = db
end

local function computeIdentity()
	local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or "Unknown"
	ns.charName = UnitName("player") or "Unknown"
	ns.charKey = realm .. "-" .. ns.charName
end

-- Module lifecycle --------------------------------------------------------

ns.modules = {}

function ns:NewModule(name)
	local m = { name = name }
	ns.modules[#ns.modules + 1] = m
	ns[name] = m
	return m
end

local function callModules(method)
	for _, m in ipairs(ns.modules) do
		if m[method] then
			ns:Guard(m.name .. ":" .. method, m[method])(m)
		end
	end
end

ns:On("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	initDB()
	callModules("OnInit")
end)

ns:On("PLAYER_LOGIN", function()
	computeIdentity()
	callModules("OnLogin")
end)

-- Slash commands ----------------------------------------------------------

local function onOff(v) return v and "on" or "off" end

local function printHelp()
	ns:Print("v" .. ns.version .. " commands:")
	print("  /pprof - open or close the list of recipes you have not learned")
	print("  /pprof auto - open that list with the profession window: " .. onOff(ns.db.settings.panel))
	print("  /pprof trainer - make trainers list recipes you cannot learn yet: " .. onOff(ns.db.settings.trainerUnavailable))
	print("  /pprof unknown - hide recipes with no known source: " .. onOff(ns.db.settings.hideUnknown))
	print("  /pprof reset - forget this character's recipe data")
	print("  /pprof dump - with a profession window open, print what the game returns for unlearned recipes")
end

SLASH_PLUVASPROFESSIONS1 = "/pprof"
SLASH_PLUVASPROFESSIONS2 = "/pluvasprof"
SlashCmdList.PLUVASPROFESSIONS = function(msg)
	local cmd = ((msg or ""):match("^%s*(%S*)") or ""):lower()
	local s = ns.db.settings
	if cmd == "" then
		ns.UI:Toggle()
	elseif cmd == "auto" then
		s.panel = not s.panel
		ns:Print("open with the profession window: " .. onOff(s.panel))
		ns.UI:Refresh()
	elseif cmd == "trainer" then
		s.trainerUnavailable = not s.trainerUnavailable
		ns:Print("trainers list recipes you cannot learn yet: " .. onOff(s.trainerUnavailable))
	elseif cmd == "unknown" then
		s.hideUnknown = not s.hideUnknown
		ns:Print("hide recipes with no known source: " .. onOff(s.hideUnknown))
		ns.UI:Refresh()
	elseif cmd == "reset" then
		ns.db.chars[ns.charKey] = nil
		ns:Print("recipe data for " .. ns.charKey .. " deleted. Open your profession windows to read it again.")
		ns.UI:Refresh()
	elseif cmd == "dump" then
		ns.Recipes:Dump(tonumber((msg or ""):match("dump%s+(%d+)")) or 3)
	elseif cmd == "debug" then
		s.debug = not s.debug
		ns:Print("debug " .. onOff(s.debug))
	else
		printHelp()
	end
end
