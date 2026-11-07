-- Pluvas' Professions: tests. See tests/lib/harness.lua for test/eq/near/truthy.
local ns = _NS
local D, T, R = ns.Data, ns.Trainer, ns.Recipes

-- Client stand-ins this addon needs. Kept here because only this addon uses them.
local professions = { { "Tailoring", 75, 150, 197 }, { "Cooking", 10, 75, 185 } }
function GetProfessions()
	local out = {}
	for i = 1, #professions do out[i] = i end
	return unpack(out)
end
function GetProfessionInfo(i)
	local p = professions[i]
	if not p then return nil end
	return p[1], 136249, p[2], p[3], 0, 0, p[4]
end
UnitLevel = function() return 20 end
GetZoneText = function() return "Orgrimmar" end
local realUnitName = UnitName
UnitName = function(unit) if unit == "npc" then return "Magar" end return realUnitName(unit) end

_FIRE("ADDON_LOADED", "PluvasProfessions")
_FIRE("PLAYER_LOGIN")

local function profs() return ns.db.chars[ns.charKey] end

test("saved variables and identity", function()
	truthy(ns.db, "ns.db")
	truthy(PluvasProfessionsDB, "PluvasProfessionsDB")
	eq(ns.charKey, "Forever-Pluvas")
	eq(ns.db.settings.panel, false)
	eq(ns.db.settings.trainerUnavailable, true)
end)

-- Text helpers

test("key is lowercase and trimmed", function()
	eq(D.Key("  Bolt of Linen Cloth "), "bolt of linen cloth")
	eq(D.Key(""), nil)
	eq(D.Key(nil), nil)
end)

test("strip codes removes colors and textures", function()
	eq(D.StripCodes("|cFFFFD200Vendor: |rBob|nZone: X|TInterface\\Icons\\a:0|t"), "Vendor: Bob\nZone: X")
end)

test("source label from Blizzard source text", function()
	local label, plain = D.ParseSource("|cFFFFD200Vendor: |rGeorgio Bolero|n|cFFFFD200Zone: |rStormwind City")
	eq(label, "Vendor")
	eq(plain, "Vendor: Georgio Bolero\nZone: Stormwind City")
end)

test("source label without a colon is the whole first line", function()
	eq((D.ParseSource("|cFFFFD200Trainer|r")), "Trainer")
	eq((D.ParseSource("Discovery")), "Discovery")
end)

test("empty or missing source text has no label", function()
	eq((D.ParseSource(nil)), nil)
	eq((D.ParseSource("  ")), nil)
end)

test("source groups", function()
	eq((D.SourceGroup("Trainer")), "trainer")
	eq((D.SourceGroup("Vendor")), "vendor")
	eq((D.SourceGroup("World Drop")), "drop")
	eq((D.SourceGroup("Quest")), "quest")
	local key, order, text = D.SourceGroup("Fishing")
	eq(key, "other:fishing"); eq(text, "Fishing")
	truthy(order > select(2, D.SourceGroup("Discovery")), "other sorts after known groups")
	local ukey, uorder = D.SourceGroup(nil)
	eq(ukey, "unknown")
	truthy(uorder > order, "unknown sorts last")
end)

test("money", function()
	eq(D.Money(0), "0|cffeda55fc|r")
	eq(D.Money(10203), "1|cffffd700g|r 2|cffc7c7cfs|r 3|cffeda55fc|r")
	eq(D.Money(5000), "50|cffc7c7cfs|r")
end)

-- Trainer service info

test("service info: Forever order (name, type, icon, level, subtext, category)", function()
	local name, kind, icon, level = T.ParseServiceInfo("Linen Bag", "unavailable", 133639, 10, "", "Bags")
	eq(name, "Linen Bag"); eq(kind, "unavailable"); eq(icon, 133639); eq(level, 10)
end)

test("service info: older order (name, rank, category, expanded)", function()
	local name, kind, icon = T.ParseServiceInfo("Linen Bag", "", "available", 1)
	eq(name, "Linen Bag"); eq(kind, "available"); eq(icon, nil)
end)

test("service info: unknown shape gives no type", function()
	local _, kind = T.ParseServiceInfo("X", 5, 6)
	eq(kind, nil)
end)

-- Building the list

local function rowNames(rows)
	local out = {}
	for _, r in ipairs(rows) do out[#out + 1] = r.header and ("[" .. r.text .. "]") or r.name end
	return table.concat(out, ",")
end

test("rows: grouped by source, trainer recipes by skill", function()
	local prof = { skill = 75, u = {
		[1] = { n = "Red Linen Robe", s = "Trainer" },
		[2] = { n = "Brown Linen Pants", s = "Trainer" },
		[3] = { n = "Blue Linen Vest", s = "|cFFFFD200Vendor: |rBob" },
		[4] = { n = "Mystery Shirt" },
		[5] = { n = "Azure Silk Hood", s = "World Drop" },
	}, tu = {} }
	local catalog = {
		["red linen robe"] = { n = "Red Linen Robe", s = 70, c = 200 },
		["brown linen pants"] = { n = "Brown Linen Pants", s = 30 },
	}
	local rows, summary = D.BuildRows(prof, catalog, { level = 20 })
	eq(rowNames(rows), "[Trainer],Brown Linen Pants,Red Linen Robe,[Vendor],Blue Linen Vest,[Drop],Azure Silk Hood,[No source info],Mystery Shirt")
	eq(summary.total, 5)
	eq(summary.learnable, 2)
	eq(rows[1].count, 2)
end)

test("rows: learnable needs skill and level", function()
	local prof = { skill = 50, u = {
		[1] = { n = "Low", s = "Trainer" },
		[2] = { n = "High Skill", s = "Trainer" },
		[3] = { n = "High Level", s = "Trainer" },
	}, tu = {} }
	local catalog = {
		low = { s = 25 }, ["high skill"] = { s = 100 }, ["high level"] = { s = 1, lv = 30 },
	}
	local rows = D.BuildRows(prof, catalog, { level = 20 })
	local by = {}
	for _, r in ipairs(rows) do if not r.header then by[r.name] = r.learnable end end
	eq(by["Low"], true)
	eq(by["High Skill"], false)
	eq(by["High Level"], false)
end)

test("rows: a recipe with no source text but trainer data counts as a trainer recipe", function()
	local prof = { skill = 10, u = { [1] = { n = "Linen Bag" } }, tu = {} }
	local rows = D.BuildRows(prof, { ["linen bag"] = { s = 45 } }, {})
	eq(rowNames(rows), "[Trainer],Linen Bag")
	eq(rows[2].learnable, false)
end)

test("rows: trainer-only recipes fill in, without duplicates", function()
	local prof = { skill = 75, u = { [1] = { n = "Linen Bag", s = "Trainer" } },
		tu = { ["linen bag"] = true, ["heavy linen gloves"] = true, ["no catalog"] = true } }
	local catalog = {
		["linen bag"] = { n = "Linen Bag", s = 45 },
		["heavy linen gloves"] = { n = "Heavy Linen Gloves", s = 35, ic = 132149 },
	}
	local rows = D.BuildRows(prof, catalog, { level = 20 })
	eq(rowNames(rows), "[Trainer],Heavy Linen Gloves,Linen Bag")
	eq(rows[2].icon, 132149)
end)

test("rows: hide unknown sources", function()
	local prof = { u = { [1] = { n = "A" }, [2] = { n = "B", s = "Quest" } }, tu = {} }
	eq(rowNames((D.BuildRows(prof, nil, { hideUnknown = true }))), "[Quest],B")
end)

test("rows: a collapsed group keeps its header and count but hides its recipes", function()
	local prof = { skill = 50, u = { [1] = { n = "A" }, [2] = { n = "B" }, [3] = { n = "C", s = "Trainer" } }, tu = {} }
	local catalog = { c = { s = 10 } }
	local rows, summary = D.BuildRows(prof, catalog, { collapsed = { unknown = true, trainer = false } })
	eq(rowNames(rows), "[Trainer],C,[No source info]")
	eq(rows[3].collapsed, true)
	eq(rows[3].count, 2)
	eq(rows[1].collapsed, false)
	eq(summary.total, 3)
	eq(summary.learnable, 1, "collapsed or not, learnable recipes are counted")
end)

test("the no-source group starts collapsed, and staying expanded survives a reload", function()
	eq(ns.db.settings.collapsed.unknown, true)
	ns.db.settings.collapsed.unknown = false
	_FIRE("ADDON_LOADED", "PluvasProfessions")   -- reapplies defaults like a reload
	eq(ns.db.settings.collapsed.unknown, false)
	ns.db.settings.collapsed.unknown = true
end)

test("rows: a vendor seen selling the recipe is its source", function()
	local prof = { u = { [1] = { n = "Blue Linen Vest" }, [2] = { n = "Mystery Shirt" } }, tu = {} }
	local vendors = { ["blue linen vest"] = { v = "Bob", c = 500 } }
	local rows = D.BuildRows(prof, nil, { vendors = vendors })
	eq(rowNames(rows), "[Vendor],Blue Linen Vest,[No source info],Mystery Shirt")
	eq(rows[2].vendor.v, "Bob")
end)

test("rows: same-named recipes (one per faction) are shown once", function()
	local prof = { u = { [20] = { n = "Faction Banner" }, [10] = { n = "Faction Banner" } }, tu = {} }
	local rows = D.BuildRows(prof, nil, {})
	eq(rowNames(rows), "[No source info],Faction Banner")
	eq(rows[2].id, 10)
end)

test("rows: recipes without a requirement sort by the skill where they turn grey", function()
	local prof = { u = {
		[1] = { n = "Loom", g = 300 }, [2] = { n = "Spinning Wheel", g = 145 },
		[3] = { n = "Odd One" }, [4] = { n = "Another", g = 145 },
	}, tu = {} }
	eq(rowNames((D.BuildRows(prof, nil, {}))), "[No source info],Another,Spinning Wheel,Loom,Odd One")
end)

-- Vendors

test("recipe name from a recipe item", function()
	local V = ns.Vendor
	eq(V.RecipeName("Pattern: Red Linen Robe"), "Red Linen Robe")
	eq(V.RecipeName("Recipe: Elixir of Minor Agility"), "Elixir of Minor Agility")
	eq(V.RecipeName("Linen Cloth"), nil)
	eq(V.RecipeName(nil), nil)
end)

test("vendor visit records the recipe items it sells", function()
	local items = {
		{ link = "|Hitem:6272::::|h[Pattern: Blue Linen Robe]|h", class = 9, sub = 2, name = "Pattern: Blue Linen Robe", price = 210, available = -1 },
		{ link = "|Hitem:6274::::|h[Pattern: Blue Overalls]|h", class = 9, sub = 2, name = "Pattern: Blue Overalls", price = 400, available = 1 },
		{ link = "|Hitem:2320::::|h[Coarse Thread]|h", class = 7, sub = 5, name = "Coarse Thread", price = 10, available = -1 },
		{ link = "|Hitem:1::::|h[Tailoring Tome]|h", class = 9, sub = 0, name = "Book: Tailoring Tome", price = 1, available = -1 },
		{ link = "|Hitem:2::::|h[Pattern: Token Robe]|h", class = 9, sub = 2, name = "Pattern: Token Robe", price = 0, extended = true, available = -1 },
	}
	function GetMerchantNumItems() return #items end
	function GetMerchantItemLink(i) return items[i].link end
	C_Item = { GetItemInfoInstant = function(link)
		for _, it in ipairs(items) do
			if it.link == link then return 1, "", "", "", 0, it.class, it.sub end
		end
	end }
	C_MerchantFrame = { GetItemInfo = function(i)
		local it = items[i]
		return { name = it.name, price = it.price, hasExtendedCost = it.extended or false, numAvailable = it.available }
	end }
	_FIRE("MERCHANT_SHOW")
	_RUN_TIMERS()
	_FIRE("MERCHANT_CLOSED")
	local v = ns.db.vendor
	eq(v["blue linen robe"].v, "Magar")
	eq(v["blue linen robe"].c, 210)
	eq(v["blue linen robe"].lim, nil)
	eq(v["blue overalls"].lim, true, "limited supply")
	eq(v["token robe"].c, nil, "no gold price for token items")
	eq(v["coarse thread"], nil, "not a recipe")
	eq(v["tailoring tome"], nil, "books are not single recipes")
end)

test("no merchant reads after the vendor window closes", function()
	local reads = 0
	local link = GetMerchantItemLink
	GetMerchantItemLink = function(i) reads = reads + 1; return link(i) end
	_FIRE("MERCHANT_SHOW")
	_FIRE("MERCHANT_CLOSED")
	_RUN_TIMERS()
	eq(reads, 0)
	GetMerchantItemLink = link
end)

test("rows: nothing to show", function()
	local rows, summary = D.BuildRows(nil, nil, nil)
	eq(#rows, 0); eq(summary.total, 0)
end)

-- Reading the profession window

local recipes = {
	[2963] = { name = "Bolt of Linen Cloth", learned = true },
	[2386] = { name = "Linen Robe", learned = true },
	[3755] = { name = "Linen Bag", learned = false, icon = 133639, source = "Trainer", sourceType = 3, grey = 70 },
	[7630] = { name = "Blue Linen Vest", learned = false, source = "|cFFFFD200Vendor: |rBob" },
	[9999] = { name = "Old Placeholder", learned = false, isDummyRecipe = true },
}
local linked, sourceCalls = false, 0

C_TradeSkillUI = {
	IsTradeSkillLinked = function() return linked end,
	IsTradeSkillGuild = function() return false end,
	IsNPCCrafting = function() return false end,
	GetBaseProfessionInfo = function()
		return { professionID = 197, professionName = "Tailoring", skillLevel = 80, maxSkillLevel = 150 }
	end,
	GetAllRecipeIDs = function()
		local ids = {}
		for id in pairs(recipes) do ids[#ids + 1] = id end
		table.sort(ids)
		return ids
	end,
	GetRecipeInfo = function(id)
		local r = recipes[id]
		if not r then return nil end
		return { recipeID = id, name = r.name, learned = r.learned, icon = r.icon, isDummyRecipe = r.isDummyRecipe, sourceType = r.sourceType, maxTrivialLevel = r.grey }
	end,
	GetRecipeSourceText = function(id)
		sourceCalls = sourceCalls + 1
		return recipes[id] and recipes[id].source
	end,
}

local function openWindow()
	_FIRE("TRADE_SKILL_SHOW")
	_RUN_TIMERS()
end

test("profession scan stores unlearned recipes with their source", function()
	sourceCalls = 0
	openWindow()
	local p = profs().Tailoring
	truthy(p, "Tailoring entry")
	eq(p.skill, 80); eq(p.max, 150); eq(p.id, 197)
	eq(p.u[3755].n, "Linen Bag")
	eq(p.u[3755].s, "Trainer")
	eq(p.u[3755].i, 133639)
	eq(p.u[3755].t, 3, "raw source type kept")
	eq(p.u[7630].t, nil)
	eq(p.u[3755].g, 70, "grey level kept")
	eq(p.u[7630].n, "Blue Linen Vest")
	eq(p.u[2963], nil, "learned recipe left out")
	eq(p.u[9999], nil, "dummy recipe left out")
	eq(sourceCalls, 2, "source text read only for unlearned recipes")
	eq(R.current, "Tailoring")
	_FIRE("TRADE_SKILL_CLOSE")
	eq(R.current, nil)
end)

test("a complete read replaces the saved list", function()
	profs().Tailoring.u[123] = { n = "Recipe Since Removed" }
	openWindow()
	eq(profs().Tailoring.u[123], nil)
	_FIRE("TRADE_SKILL_CLOSE")
end)

test("learned recipes are taken off the trainer list", function()
	profs().Tailoring.tu["linen robe"] = true
	profs().Tailoring.tu["linen bag"] = true
	openWindow()
	eq(profs().Tailoring.tu["linen robe"], nil)
	eq(profs().Tailoring.tu["linen bag"], true)
	_FIRE("TRADE_SKILL_CLOSE")
end)

test("without GetAllRecipeIDs the filtered list only adds", function()
	local all = C_TradeSkillUI.GetAllRecipeIDs
	C_TradeSkillUI.GetAllRecipeIDs = nil
	C_TradeSkillUI.GetFilteredRecipeIDs = function() return { 2963, 2386 } end
	profs().Tailoring.u[555] = { n = "Kept Recipe" }
	openWindow()
	eq(profs().Tailoring.u[555].n, "Kept Recipe")
	eq(profs().Tailoring.u[3755].n, "Linen Bag")
	C_TradeSkillUI.GetAllRecipeIDs = all
	C_TradeSkillUI.GetFilteredRecipeIDs = nil
	profs().Tailoring.u[555] = nil
	_FIRE("TRADE_SKILL_CLOSE")
end)

test("another player's linked profession is not read", function()
	linked = true
	local before = profs().Tailoring.scanned
	profs().Tailoring.scanned = 1
	openWindow()
	eq(profs().Tailoring.scanned, 1)
	linked = false
	profs().Tailoring.scanned = before
	_FIRE("TRADE_SKILL_CLOSE")
end)

test("no reads after the window closes", function()
	local reads = 0
	local info = C_TradeSkillUI.GetRecipeInfo
	C_TradeSkillUI.GetRecipeInfo = function(id) reads = reads + 1; return info(id) end
	_FIRE("TRADE_SKILL_SHOW")
	_FIRE("TRADE_SKILL_CLOSE")
	_RUN_TIMERS()
	eq(reads, 0)
	C_TradeSkillUI.GetRecipeInfo = info
end)

test("a scan spread over frames stops when the window closes", function()
	for id = 20001, 20040 do recipes[id] = { name = "Filler " .. id, learned = true } end
	local reads = 0
	local info = C_TradeSkillUI.GetRecipeInfo
	C_TradeSkillUI.GetRecipeInfo = function(id)
		reads = reads + 1
		if reads == 5 then _FIRE("TRADE_SKILL_CLOSE") end
		return info(id)
	end
	_FIRE("TRADE_SKILL_SHOW")
	_RUN_TIMERS()
	eq(reads, 30, "only the batch already running finishes")
	C_TradeSkillUI.GetRecipeInfo = info
	for id = 20001, 20040 do recipes[id] = nil end
end)

-- Trainer

local services, filters, filterSets = {}, { available = true, unavailable = false, used = false }, 0
function IsTradeskillTrainer() return true end
function GetNumTrainerServices() return #services end
function GetTrainerServiceInfo(i)
	local s = services[i]
	return s.name, s.kind, s.icon, s.level, "", ""
end
function GetTrainerServiceSkillReq(i)
	local s = services[i]
	return s.prof, s.skill, true
end
function GetTrainerServiceCost(i) return services[i].cost or 0, false end
function GetTrainerServiceTypeFilter(kind) return filters[kind] end
function SetTrainerServiceTypeFilter(kind, on)
	filters[kind] = on
	filterSets = filterSets + 1
end

local function visitTrainer()
	_FIRE("TRAINER_SHOW")
	_RUN_TIMERS()
	_FIRE("TRAINER_CLOSED")
end

test("trainer visit records the catalog and what this character still needs", function()
	services = {
		{ name = "Linen Bag", kind = "available", prof = "Tailoring", skill = 45, cost = 90, icon = 133639 },
		{ name = "Heavy Linen Gloves", kind = "unavailable", prof = "Tailoring", skill = 85, level = 12, cost = 250 },
		{ name = "Bolt of Linen Cloth", kind = "used", prof = "Tailoring", skill = 1 },
	}
	visitTrainer()
	local c = ns.db.trainer.Tailoring
	eq(c["linen bag"].s, 45)
	eq(c["linen bag"].c, 90)
	eq(c["linen bag"].w, "Magar")
	eq(c["linen bag"].z, "Orgrimmar")
	eq(c["heavy linen gloves"].lv, 12)
	eq(c["bolt of linen cloth"].c, nil, "zero cost is not stored")
	local p = profs().Tailoring
	eq(p.tu["heavy linen gloves"], true)
	eq(p.tu["linen bag"], true)
	eq(p.tu["bolt of linen cloth"], nil)
end)

test("trainer turns on the unavailable filter when the setting is on", function()
	eq(filters.unavailable, true)
	filters.unavailable = false
	ns.db.settings.trainerUnavailable = false
	filterSets = 0
	visitTrainer()
	eq(filters.unavailable, false)
	eq(filterSets, 0)
	ns.db.settings.trainerUnavailable = true
end)

test("a trainer for a profession this character lacks only fills the catalog", function()
	services = { { name = "Copper Chain Belt", kind = "available", prof = "Blacksmithing", skill = 35 } }
	visitTrainer()
	truthy(ns.db.trainer.Blacksmithing["copper chain belt"], "catalog entry")
	eq(profs().Blacksmithing, nil)
end)

test("a service seen as used takes it off the unlearned list", function()
	services = { { name = "Linen Bag", kind = "used", prof = "Tailoring", skill = 45 } }
	visitTrainer()
	local p = profs().Tailoring
	eq(p.tu["linen bag"], nil)
	eq(p.u[3755], nil)
end)

test("class trainers are ignored", function()
	IsTradeskillTrainer = function() return false end
	services = { { name = "Linen Bag", kind = "available", prof = "Tailoring", skill = 45 } }
	visitTrainer()
	eq(profs().Tailoring.tu["linen bag"], nil)
	IsTradeskillTrainer = function() return true end
end)

-- Learning, pruning, slash commands

test("learning a recipe removes it everywhere", function()
	local p = profs().Tailoring
	p.u[7630] = { n = "Blue Linen Vest" }
	p.tu["blue linen vest"] = true
	C_Spell = { GetSpellName = function() return "Blue Linen Vest" end }
	_FIRE("NEW_RECIPE_LEARNED", 7630)
	eq(p.u[7630], nil)
	eq(p.tu["blue linen vest"], nil)
end)

test("professions the character dropped are pruned at login", function()
	profs().Alchemy = { u = {}, tu = {} }
	R:SyncProfessions(true)
	eq(profs().Alchemy, nil)
	truthy(profs().Tailoring, "kept")
	eq(profs().Tailoring.skill, 75, "skill synced from GetProfessionInfo")
end)

test("nothing is pruned when the client lists no professions yet", function()
	local saved = professions
	professions = {}
	R:SyncProfessions(true)
	truthy(profs().Tailoring, "kept")
	professions = saved
end)

test("slash: unknown toggles, reset forgets this character", function()
	SlashCmdList.PLUVASPROFESSIONS("unknown")
	eq(ns.db.settings.hideUnknown, true)
	SlashCmdList.PLUVASPROFESSIONS("unknown")
	eq(ns.db.settings.hideUnknown, false)
	SlashCmdList.PLUVASPROFESSIONS("reset")
	eq(ns.db.chars[ns.charKey], nil)
	truthy(ns.db.trainer.Tailoring, "trainer catalog is shared and kept")
end)

-- Panel visibility follows the player's last choice ------------------------------------
-- Uses the shared frame stand-ins from tests/lib/mocks.lua.

ProfessionsFrame = CreateFrame("Frame", "ProfessionsFrame")
ProfessionsFrame:Hide()
ProfessionsFrame:SetHeight(600)

local function openProfession()
	ProfessionsFrame:Show()
	_FIRE("TRADE_SKILL_SHOW")
	_RUN_TIMERS()
end
local function closeProfession()
	ProfessionsFrame:Hide()
	_FIRE("TRADE_SKILL_CLOSE")
	_RUN_TIMERS()
end
local function panelShown() return PluvasProfessionsFrame ~= nil and PluvasProfessionsFrame:IsShown() end
local function onEscapeList()
	for _, n in ipairs(UISpecialFrames) do
		if n == "PluvasProfessionsFrame" then return true end
	end
	return false
end

test("panel stays closed on launch when it was never opened", function()
	ns.db.settings.panel = false
	openProfession()
	truthy(PluvasProfessionsToggleButton, "toggle button under the profession window")
	eq(panelShown(), false)
	closeProfession()
end)

test("opening it with the button is remembered for the next launch", function()
	openProfession()
	PluvasProfessionsToggleButton.scripts.OnClick()
	eq(panelShown(), true)
	eq(ns.db.settings.panel, true)
	closeProfession()
	eq(panelShown(), false, "closes with the profession window")
	eq(ns.db.settings.panel, true, "closing the window is not closing the panel")
	openProfession()
	eq(panelShown(), true, "back on the next launch")
end)

test("closing it with its close button is remembered too", function()
	PluvasProfessionsFrame:Hide()   -- the X button
	eq(ns.db.settings.panel, false)
	closeProfession()
	openProfession()
	eq(panelShown(), false)
	closeProfession()
end)

test("/pprof while the profession window is open counts as the choice", function()
	openProfession()
	SlashCmdList.PLUVASPROFESSIONS("")
	eq(panelShown(), true)
	eq(ns.db.settings.panel, true)
	SlashCmdList.PLUVASPROFESSIONS("")
	eq(ns.db.settings.panel, false)
	closeProfession()
end)

test("docked, Escape closes the profession window rather than the panel", function()
	openProfession()
	PluvasProfessionsToggleButton.scripts.OnClick()
	eq(onEscapeList(), false, "not closed by Escape while docked")
	closeProfession()
	eq(ns.db.settings.panel, true)
end)

test("on its own the panel closes with Escape and does not change the choice", function()
	SlashCmdList.PLUVASPROFESSIONS("")   -- profession window closed: opens floating
	eq(panelShown(), true)
	eq(onEscapeList(), true)
	PluvasProfessionsFrame:Hide()
	eq(ns.db.settings.panel, true, "floating panel does not touch the launch choice")
end)

test("a floating panel docked by the button records the choice", function()
	ns.db.settings.panel = false
	SlashCmdList.PLUVASPROFESSIONS("")   -- floating
	openProfession()
	eq(panelShown(), true)
	PluvasProfessionsToggleButton.scripts.OnClick()   -- docks it
	eq(ns.db.settings.panel, true)
	closeProfession()
end)

