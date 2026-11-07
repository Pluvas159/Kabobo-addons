-- Pluvas' Auctions: core bootstrap, saved variables, events and slash commands.
local ADDON, ns = ...

ns.name = ADDON
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"

local DB_VERSION = 1

local DEFAULTS = {
	settings = {
		tooltip = true,        -- show price lines in item tooltips
		tooltipHistory = true, -- show the 14-day average line
		tooltipLedger = true,  -- show your own average sale price
		tooltipCraft = true,   -- show the AH cost of mats for items this character can craft
		professionPanel = true, -- show mats cost and profit in the profession window
		matsList = true,       -- list the base mats under the mats cost
		historyDays = 60,      -- how many days of daily price history to keep
	},
	account = {
		lastReplicate = 0,     -- time() of the last full scan (the server allows one per account per 15 min)
	},
	realms = {},              -- [realmKey] = { items = { [itemKey] = entry }, lastScan = time }
	ledger = {},              -- [realmKey] = { tx = { transaction, ... } }
	gold = {},                -- [realmKey] = { [charName] = { money = copper, days = { [dayStart] = copper } } }
	crafts = {},              -- [realmKey] = { [charName] = { [professionID] = { name, r = recipes } } }
}

-- Error containment ---------------------------------------------------------
--
-- Lua errors never crash the game, but an error in a tooltip or event handler repeats every
-- time it runs. ns:Guard reports the first errors (to BugSack or the error frame) and turns the
-- guarded code off for the rest of the session after MAX_ERRORS, so a bug degrades one feature
-- instead of spamming errors. A real client crash comes from calling a Blizzard C function in a
-- context it does not support; pcall cannot catch that, so such calls must stay out of
-- tooltips (see docs/forever-client.md).

local MAX_ERRORS = 3
ns.disabled = {}   -- [name] = true once a guarded function has been turned off

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
ns.frame = frame
local handlers = {}

-- Register a handler for an event. Several handlers per event are allowed.
function ns:On(event, fn)
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
		-- Unknown events raise an error on the modern client; never let one break loading.
		local ok = pcall(frame.RegisterEvent, frame, event)
		if not ok then
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

local PREFIX = "|cff22b8cfPluvas' Auctions|r:"

function ns:Print(...)
	print(PREFIX, ...)
end

function ns:Debug(...)
	if ns.db and ns.db.settings.debug then
		print("|cff888888[PA debug]|r", ...)
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
	PluvasAuctionsDB = PluvasAuctionsDB or {}
	local db = PluvasAuctionsDB
	applyDefaults(db, DEFAULTS)
	db.dbVersion = db.dbVersion or DB_VERSION
	ns.db = db
end

-- Identity ----------------------------------------------------------------

-- Auction data is kept per realm (ruleset) and faction, since auction houses
-- are not guaranteed to be shared between factions.
local function computeIdentity()
	local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or "Unknown"
	local faction = UnitFactionGroup("player") or "Neutral"
	ns.realmName = realm
	ns.faction = faction
	ns.realmKey = realm .. "-" .. faction
	ns.charName = UnitName("player") or "Unknown"
end

function ns:RealmData()
	local realms = ns.db.realms
	local data = realms[ns.realmKey]
	if not data then
		data = { items = {}, lastScan = 0 }
		realms[ns.realmKey] = data
	end
	return data
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

ns:On("PLAYER_LOGOUT", function()
	callModules("OnLogout")
end)

-- Slash commands ----------------------------------------------------------

local function printHelp()
	ns:Print("v" .. ns.version .. " commands:")
	print("  /pa - open or close the ledger window")
	print("  /pa scan - full auction house scan (AH must be open, once per 15 min)")
	print("  /pa price <item link> - show stored prices for an item")
	print("  /pa tooltip - turn the tooltip price lines on or off")
	print("  /pa resetprices - delete price data for this realm/faction")
	print("  /pa resetledger - delete sales history for this realm/faction")
end

SLASH_PLUVASAUCTIONS1 = "/pa"
SLASH_PLUVASAUCTIONS2 = "/pluvas"
SlashCmdList.PLUVASAUCTIONS = function(msg)
	msg = msg or ""
	local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()

	if cmd == "" then
		ns.UI:Toggle()
	elseif cmd == "scan" then
		ns.Scanner:FullScan()
	elseif cmd == "price" then
		ns.Tooltip:PrintPrice(rest)
	elseif cmd == "tooltip" then
		ns.db.settings.tooltip = not ns.db.settings.tooltip
		ns:Print("tooltip prices " .. (ns.db.settings.tooltip and "on" or "off"))
	elseif cmd == "resetprices" then
		ns.db.realms[ns.realmKey] = nil
		ns:Print("price data for " .. ns.realmKey .. " deleted.")
	elseif cmd == "resetledger" then
		ns.db.ledger[ns.realmKey] = nil
		ns:Print("ledger for " .. ns.realmKey .. " deleted.")
	elseif cmd == "debug" then
		ns.db.settings.debug = not ns.db.settings.debug
		ns:Print("debug " .. (ns.db.settings.debug and "on" or "off"))
	else
		printHelp()
	end
end
