-- PluvasCore: the runtime every Pluvas addon shares. Error guards, game events and addon
-- messages, modules, saved variables and the character's identity.
--
-- Edit this library only in shared/PluvasCore, then run `npm run sync`: every addon embeds its
-- own copy under Libs/PluvasCore, and `npm test` fails when a copy drifts. A copy installs its
-- functions on its addon's namespace (`ns`) and creates no globals, so addons never clash. The
-- one exception is the PluvasAddons table through which addons share APIs (Peers.lua).
local ADDON, ns = ...

ns.name = ADDON
ns.modules = {}
ns.disabled = {}   -- [guard name] = true once a guarded function has been turned off

local function metadata(field)
	local get = C_AddOns and C_AddOns.GetAddOnMetadata
	if not get then return nil end
	local ok, value = pcall(get, ADDON, field)
	return ok and value or nil
end

ns.title = metadata("Title") or ADDON
ns.version = metadata("Version") or "dev"

-- Output --------------------------------------------------------------------------

-- "Addon Title: ..." in chat. Uses the PluvasUI accent color when the addon embeds it.
function ns:Print(...)
	local UI = ns.PluvasUI
	print(UI and UI.Prefix(ns.title) or (ns.title .. ":"), ...)
end

-- Only with the hidden `debug` slash toggle on.
function ns:Debug(...)
	if not (ns.db and ns.db.settings and ns.db.settings.debug) then return end
	local tag = "[" .. ns.title .. " debug]"
	local UI = ns.PluvasUI
	print(UI and UI.Color(tag, "muted") or tag, ...)
end

-- Error containment ---------------------------------------------------------------
--
-- Lua errors never crash the game, but an error in a tooltip or event handler repeats every
-- time it runs. A guarded function reports its first errors (to BugSack or the error frame) and
-- turns itself off for the session after MAX_ERRORS, so a bug degrades one feature instead of
-- spamming errors. A real client crash comes from calling a Blizzard C function outside the
-- context it was built for; pcall cannot catch that (see docs/forever-client.md).

ns.MAX_ERRORS = 3

function ns:Guard(name, fn)
	local errors = 0
	local function finish(ok, ...)
		if ok then return ... end
		local err = ...
		errors = errors + 1
		if errors >= ns.MAX_ERRORS then
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

-- Events and messages -------------------------------------------------------------
--
-- ns:On(name, fn) takes both game events (ALL_CAPS, registered with the client) and addon
-- messages (CamelCase, sent with ns:Send). Messages decouple modules: data modules announce
-- changes ("LedgerChanged") and the UI listens, so neither has to know about the other.
-- Every handler is guarded on its own.

local frame = CreateFrame("Frame")
local handlers = {}

local function isGameEvent(name)
	return name:find("^[A-Z][A-Z0-9_]*$") ~= nil
end

function ns:On(name, fn)
	local list = handlers[name]
	if not list then
		list = {}
		handlers[name] = list
		-- Unknown events raise an error on the modern client; never let one break loading.
		if isGameEvent(name) and not pcall(frame.RegisterEvent, frame, name) then
			ns:Debug("could not register event", name)
		end
	end
	list[#list + 1] = ns:Guard(name .. " handler #" .. (#list + 1), fn)
end

local function dispatch(name, ...)
	local list = handlers[name]
	if not list then return end
	for i = 1, #list do list[i](...) end
end

frame:SetScript("OnEvent", function(_, event, ...) dispatch(event, ...) end)

-- Runs the handlers of an addon message right away.
function ns:Send(message, ...)
	dispatch(message, ...)
end

-- Modules -------------------------------------------------------------------------
--
-- A module is a table on ns with optional OnInit (saved variables loaded), OnLogin (identity
-- known) and OnLogout methods, called in the order the modules were created.

function ns:NewModule(name)
	if ns[name] ~= nil then error(ADDON .. ": ns." .. name .. " is already taken", 2) end
	local m = { name = name }
	ns.modules[#ns.modules + 1] = m
	ns[name] = m
	return m
end

local function callModules(method)
	for _, m in ipairs(ns.modules) do
		if m[method] then ns:Guard(m.name .. ":" .. method, m[method])(m) end
	end
end

-- Saved variables -----------------------------------------------------------------

local config

-- Describes the addon's saved variables; call once, from the addon's first file.
--   savedVariables  global name from the TOC's ## SavedVariables
--   defaults        merged into the saved table on every load (missing keys only)
--   dbVersion       current layout version (default 1)
--   migrations      { [version] = function(db) }: brings a db up from version - 1. Runs before
--                   the defaults are merged.
--   title           fallback for ns.title when the TOC cannot be read (tests)
function ns:Setup(opts)
	config = opts
	if opts.title and ns.title == ADDON then ns.title = opts.title end
end

-- Fills missing keys of target from defaults, recursively. Existing values are kept.
function ns.ApplyDefaults(target, defaults)
	for k, v in pairs(defaults) do
		if type(v) == "table" then
			if type(target[k]) ~= "table" then target[k] = {} end
			ns.ApplyDefaults(target[k], v)
		elseif target[k] == nil then
			target[k] = v
		end
	end
	return target
end

local function loadDB()
	local name = config.savedVariables
	local db = _G[name]
	if type(db) ~= "table" then
		db = {}
		_G[name] = db
	end
	local current = config.dbVersion or 1
	-- A brand-new table starts at the current layout; data saved before versions existed is 1.
	if type(db.dbVersion) ~= "number" then db.dbVersion = next(db) and 1 or current end
	for v = db.dbVersion + 1, current do
		local migrate = config.migrations and config.migrations[v]
		if migrate then migrate(db) end
		db.dbVersion = v
	end
	ns.ApplyDefaults(db, config.defaults or {})
	db.settings = db.settings or {}
	ns.db = db
end

-- Identity ------------------------------------------------------------------------
--
-- realmKey (realm-faction) keys data tied to an auction house; charKey (realm-character) keys
-- data of one character.

local function identify()
	local realm = (GetNormalizedRealmName and GetNormalizedRealmName())
		or (GetRealmName and GetRealmName()) or "Unknown"
	ns.realm = realm
	ns.faction = (UnitFactionGroup and UnitFactionGroup("player")) or "Neutral"
	ns.charName = (UnitName and UnitName("player")) or "Unknown"
	ns.realmKey = realm .. "-" .. ns.faction
	ns.charKey = realm .. "-" .. ns.charName
end

-- Lifecycle -----------------------------------------------------------------------

ns:On("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	if config then loadDB() end
	callModules("OnInit")
end)

ns:On("PLAYER_LOGIN", function()
	identify()
	callModules("OnLogin")
end)

ns:On("PLAYER_LOGOUT", function()
	callModules("OnLogout")
end)

-- Runs fn once the named addon is loaded: right away when it already is, else on its
-- ADDON_LOADED. For hooking load-on-demand Blizzard UI such as Blizzard_Professions.
function ns:WhenLoaded(addon, fn)
	local done = false
	local run = ns:Guard("WhenLoaded " .. addon, function()
		if done then return end
		done = true
		fn()
	end)
	local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
	if isLoaded and isLoaded(addon) then
		run()
		return
	end
	ns:On("ADDON_LOADED", function(name)
		if name == addon then run() end
	end)
end
