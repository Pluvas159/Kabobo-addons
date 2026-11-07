-- KaboboCore: tests. Loaded on its own as addon "KaboboCoreTest" (see tests/run.js).
local ns = _NS

local function catchErrors()
	local reported, old = {}, geterrorhandler
	geterrorhandler = function() return function(err) reported[#reported + 1] = err end end
	return reported, function() geterrorhandler = old end
end

-- Setup, saved variables and lifecycle -----------------------------------------------

local calls = {}
local M = ns:NewModule("Probe")
function M:OnInit() calls[#calls + 1] = "init:" .. tostring(ns.db ~= nil) end
function M:OnLogin() calls[#calls + 1] = "login:" .. tostring(ns.realmKey) end
function M:OnLogout() calls[#calls + 1] = "logout" end

KaboboCoreTestDB = { dbVersion = 1, settings = { keep = "me" }, old = { 1, 2 } }
ns:Setup({
	title = "Kabobo's Core Test",
	savedVariables = "KaboboCoreTestDB",
	dbVersion = 3,
	defaults = { settings = { flag = true, keep = "default", nested = { a = 1 } }, list = {} },
	migrations = {
		[2] = function(db) db.renamed = db.old; db.old = nil end,
		[3] = function(db) calls[#calls + 1] = "migrate3:" .. tostring(db.renamed ~= nil) end,
	},
})

_FIRE("ADDON_LOADED", "SomeOtherAddon")
_FIRE("ADDON_LOADED", "KaboboCoreTest")
_FIRE("PLAYER_LOGIN")

test("title comes from Setup when the TOC cannot be read", function()
	eq(ns.title, "Kabobo's Core Test")
	eq(ns.version, "dev")
end)

test("saved variables: migrations run in order, then defaults fill the gaps", function()
	local db = KaboboCoreTestDB
	eq(ns.db, db)
	eq(db.dbVersion, 3)
	eq(db.old, nil)
	eq(db.renamed[2], 2)
	eq(db.settings.keep, "me", "existing values are kept")
	eq(db.settings.flag, true)
	eq(db.settings.nested.a, 1)
	truthy(db.list, "default tables are created")
end)

test("modules run OnInit after the saved variables, OnLogin after identity", function()
	eq(table.concat(calls, ","), "migrate3:true,init:true,login:Forever-Horde")
	_FIRE("PLAYER_LOGOUT")
	eq(calls[#calls], "logout")
end)

test("identity keys", function()
	eq(ns.realm, "Forever")
	eq(ns.charName, "Kabobo")
	eq(ns.realmKey, "Forever-Horde")
	eq(ns.charKey, "Forever-Kabobo")
end)

test("a module name can only be taken once", function()
	eq(pcall(ns.NewModule, ns, "Probe"), false)
end)

-- Guard ------------------------------------------------------------------------

test("guard reports errors and turns the code off after three", function()
	local reported, restore = catchErrors()
	local count = 0
	local f = ns:Guard("Test feature", function(x)
		count = count + 1
		if x == "boom" then error("bad") end
		return x * 2
	end)
	eq(f(21), 42)
	f("boom"); f("boom"); f("boom")
	restore()
	eq(#reported, 3)
	truthy(reported[1]:find("Test feature: ", 1, true), "error names the feature")
	eq(ns.disabled["Test feature"], true)
	eq(f(1), nil, "turned off: not even called")
	eq(count, 4)
end)

-- Events and messages ------------------------------------------------------------

test("game events and addon messages reach their handlers", function()
	local got = {}
	ns:On("BAG_UPDATE", function(bag) got[#got + 1] = "bag" .. bag end)
	ns:On("ThingChanged", function(a, b) got[#got + 1] = a .. b end)
	ns:On("ThingChanged", function() got[#got + 1] = "second" end)
	_FIRE("BAG_UPDATE", 2)
	ns:Send("ThingChanged", "x", "y")
	eq(table.concat(got, ","), "bag2,xy,second")
end)

test("messages are not registered as game events", function()
	local registered = false
	for _, f in ipairs(_EVENT_FRAMES) do
		if f.events.ThingChanged then registered = true end
	end
	eq(registered, false)
end)

test("one failing handler does not stop the others", function()
	local reported, restore = catchErrors()
	local ran = false
	ns:On("Shaky", function() error("oops") end)
	ns:On("Shaky", function() ran = true end)
	ns:Send("Shaky")
	restore()
	eq(ran, true)
	eq(#reported, 1)
end)

test("WhenLoaded waits for the addon, and runs once", function()
	local runs = 0
	ns:WhenLoaded("Blizzard_Thing", function() runs = runs + 1 end)
	eq(runs, 0)
	_FIRE("ADDON_LOADED", "Blizzard_Thing")
	_FIRE("ADDON_LOADED", "Blizzard_Thing")
	eq(runs, 1)
	C_AddOns = { IsAddOnLoaded = function(name) return name == "Blizzard_Loaded" end }
	ns:WhenLoaded("Blizzard_Loaded", function() runs = runs + 1 end)
	eq(runs, 2, "already loaded: runs right away")
	C_AddOns = nil
end)

-- Tasks --------------------------------------------------------------------------

test("a session follows its window's events", function()
	local s = ns:Session("THING_SHOW", "THING_CLOSED")
	eq(s.open, false)
	_FIRE("THING_SHOW")
	eq(s.open, true)
	_FIRE("THING_CLOSED")
	eq(s.open, false)
end)

test("merchant items from either client API", function()
	local items = {
		{ link = "|Hitem:2320::::|h[Coarse Thread]|h", name = "Coarse Thread", price = 10, stack = 1, avail = -1 },
		{ link = "|Hitem:2678::::|h[Mild Spices]|h", name = "Mild Spices", price = 50, stack = 5, avail = 3 },
	}
	GetMerchantNumItems = function() return #items end
	GetMerchantItemLink = function(i) return items[i].link end
	C_MerchantFrame = { GetItemInfo = function(i)
		local it = items[i]
		return { name = it.name, price = it.price, stackCount = it.stack, numAvailable = it.avail, hasExtendedCost = false }
	end }
	local list = ns.MerchantItems()
	eq(#list, 2)
	eq(list[1].id, 2320); eq(list[1].name, "Coarse Thread"); eq(list[1].price, 10); eq(list[1].available, -1)
	eq(list[2].id, 2678); eq(list[2].quantity, 5); eq(list[2].extended, false)

	-- the older global function, when C_MerchantFrame is missing
	C_MerchantFrame = nil
	GetMerchantItemInfo = function(i)
		local it = items[i]
		return it.name, 0, it.price, it.stack, it.avail, true, true, i == 2
	end
	list = ns.MerchantItems()
	eq(list[2].quantity, 5); eq(list[2].available, 3); eq(list[2].extended, true)

	-- a failing client function costs only that field
	GetMerchantItemInfo = function() error("client bug") end
	list = ns.MerchantItems()
	eq(list[1].name, "Coarse Thread", "name from the link"); eq(list[1].price, nil)

	GetMerchantNumItems, GetMerchantItemLink, GetMerchantItemInfo = nil, nil, nil
	eq(#ns.MerchantItems(), 0)
end)

test("a caller turns errors into nil and counts them", function()
	local api = ns.NewCaller()
	eq(api:Call(function(a) return a + 1 end, 1), 2)
	eq(api:Call(function() error("x") end), nil)
	eq(api:Call(nil), nil, "a missing function is not a failure")
	eq(api.failures, 1)
end)

test("debounce runs once per burst", function()
	local runs = 0
	local trigger = ns:Debounce("Burst", 0.5, function() runs = runs + 1 end)
	trigger(); trigger(); trigger()
	_RUN_TIMERS()
	eq(runs, 1)
	trigger()
	_RUN_TIMERS()
	eq(runs, 2)
end)

test("spread runs every step over several frames", function()
	local seen, progress, result = {}, {}, nil
	ns:Spread({
		count = 7, size = 3,
		step = function(i) seen[#seen + 1] = i end,
		progress = function(done, count) progress[#progress + 1] = done .. "/" .. count end,
		done = function(ok) result = ok end,
	})
	eq(#seen, 3, "first batch runs right away")
	_RUN_TIMERS()
	eq(#seen, 7)
	eq(table.concat(progress, ","), "3/7,6/7")
	eq(result, true)
end)

test("spread stops when alive() turns false", function()
	local seen, alive, result = 0, true, nil
	ns:Spread({
		count = 10, size = 4,
		alive = function() return alive end,
		step = function() seen = seen + 1 end,
		done = function(ok, err) result = tostring(ok) .. ":" .. tostring(err) end,
	})
	alive = false
	_RUN_TIMERS()
	eq(seen, 4)
	eq(result, "false:nil")
end)

test("spread reports a failing step and stops", function()
	local reported, restore = catchErrors()
	local result
	ns:Spread({
		name = "Broken",
		count = 5, size = 2,
		step = function(i) if i == 2 then error("bad step") end end,
		done = function(ok, err) result = ok == false and err ~= nil end,
	})
	restore()
	eq(result, true)
	truthy(reported[1]:find("Broken: ", 1, true), "error names the task")
end)

-- Utilities -----------------------------------------------------------------------

test("ensure creates nested tables and stops at a nil key", function()
	local t = {}
	local leaf = ns.Ensure(t, "a", "b")
	eq(t.a.b, leaf)
	eq(ns.Ensure(t, "a", "b"), leaf, "existing tables are reused")
	eq(ns.Ensure(t, "a", nil, "c"), nil)
end)

test("split keeps empty fields", function()
	local parts = ns.Split("1::3", ":")
	eq(#parts, 3); eq(parts[2], ""); eq(parts[3], "3")
end)

test("try returns the first result or nil", function()
	eq(ns.Try(function() return 1, 2 end), 1)
	eq(ns.Try(function() error("x") end), nil)
	eq(ns.Try(nil), nil)
end)

test("known professions from the spellbook", function()
	eq(select(2, ns:KnownProfessions()), false, "no profession API: nothing known")
	GetProfessions = function() return 1, nil end
	GetProfessionInfo = function() return "Tailoring", nil, 75, 150, 0, 0, 197 end
	local known, any = ns:KnownProfessions()
	eq(any, true)
	eq(known.Tailoring.skill, 75); eq(known.Tailoring.max, 150); eq(known.Tailoring.line, 197)
	GetProfessions, GetProfessionInfo = nil, nil
end)

-- Slash commands ------------------------------------------------------------------

local ran
ns:Slash({ "/pct", "/pcoretest" }, {
	{ cmd = "", help = "open", run = function() ran = "open" end },
	{ cmd = "echo", args = "<text>", help = "repeat text", run = function(rest) ran = rest end },
	{ cmd = "flag", toggle = "flag", help = "the flag" },
	{ cmd = "secret", hidden = true, run = function() ran = "secret" end },
})

test("slash aliases are registered under the addon's name", function()
	eq(SLASH_KABOBOCORETEST1, "/pct")
	eq(SLASH_KABOBOCORETEST2, "/pcoretest")
end)

test("slash commands run with the rest of the line", function()
	SlashCmdList.KABOBOCORETEST("")
	eq(ran, "open")
	SlashCmdList.KABOBOCORETEST("  ECHO hello  there ")
	eq(ran, "hello  there")
end)

test("slash toggles flip a setting and send SettingChanged", function()
	local seen
	ns:On("SettingChanged", function(key, value) seen = key .. "=" .. tostring(value) end)
	SlashCmdList.KABOBOCORETEST("flag")
	eq(ns.db.settings.flag, false)
	eq(seen, "flag=false")
end)

test("unknown commands print the help, without hidden commands", function()
	local before = #_PRINTED
	SlashCmdList.KABOBOCORETEST("nonsense")
	local help = table.concat(_PRINTED, "\n", before + 1)
	truthy(help:find("/pct echo <text> - repeat text", 1, true), "usage line")
	truthy(help:find("/pct flag - the flag: off", 1, true), "toggle shows its state")
	eq(help:find("secret", 1, true), nil)
	eq(help:find("debug", 1, true), nil)
end)

test("a hidden debug toggle comes built in", function()
	SlashCmdList.KABOBOCORETEST("debug")
	eq(ns.db.settings.debug, true)
	SlashCmdList.KABOBOCORETEST("debug")
	eq(ns.db.settings.debug, false)
end)

-- Item tooltips -------------------------------------------------------------------

test("tooltip item: link from the tooltip, else from the data", function()
	local tooltip = { GetItem = function() return "Linen Cloth", "|Hitem:2589::::::::|h[Linen Cloth]|h" end }
	local link, id = ns.TooltipItem(tooltip, nil)
	eq(link, "|Hitem:2589::::::::|h[Linen Cloth]|h")
	eq(id, 2589)
	link, id = ns.TooltipItem({}, { id = 4306 })
	eq(link, nil)
	eq(id, 4306)
	eq(ns.TooltipItem({}, {}), nil)
end)

test("item tooltip callbacks get the item, and only for item tooltips", function()
	local got = {}
	truthy(ns:OnItemTooltip("Probe tooltip", function(_, link, id) got[#got + 1] = tostring(link) .. "/" .. id end))
	_HOVER({ AddDoubleLine = function() end }, { id = 2589 })
	_HOVER({}, { id = 2589 })                                -- not a tooltip that takes lines
	_HOVER({ AddDoubleLine = function() end }, {})           -- no item
	eq(#got, 1)
	eq(got[1], "nil/2589")
end)

-- Peers ---------------------------------------------------------------------------

test("an exposed API is found by name; a missing addon gives nil", function()
	local api = { Hello = function() return "hi" end }
	ns:Expose(api)
	eq(ns:Peer("KaboboCoreTest"), api)
	eq(KaboboAddons.KaboboCoreTest, api)
	eq(ns:Peer("KaboboNothing"), nil)
end)

-- Profession window ---------------------------------------------------------------

test("own profession window and its name, only while it is open", function()
	local linked = false
	C_TradeSkillUI = {
		IsTradeSkillLinked = function() return linked end,
		GetBaseProfessionInfo = function() return { professionID = 197, professionName = "Schneiderei" } end,
	}
	GetProfessions = function() return 1 end
	GetProfessionInfo = function() return "Tailoring", 0, 75, 150, 0, 0, 197 end
	ns:TradeSkillSession()
	eq(ns:ViewingOwnProfession(), false, "closed")
	eq(ns:OpenProfession(), nil, "closed")
	_FIRE("TRADE_SKILL_SHOW")
	eq(ns:ViewingOwnProfession(), true)
	local name, base = ns:OpenProfession()
	eq(name, "Tailoring", "named by skill line, as the spellbook spells it")
	eq(base.professionID, 197)
	linked = true
	eq(ns:ViewingOwnProfession(), false, "someone else's linked profession")
	_FIRE("TRADE_SKILL_CLOSE")
	eq(ns:TradeSkillSession(), ns:TradeSkillSession(), "one session per addon")
	C_TradeSkillUI, GetProfessions, GetProfessionInfo = nil, nil, nil
end)
