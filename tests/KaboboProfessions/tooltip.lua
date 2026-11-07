-- Kabobo's Professions: disenchanting in item tooltips. Runs after tests.lua (logged in).
local ns = _NS
local DE, DT = ns.Disenchant, ns.DisenchantTooltip
local PUI = ns.KaboboUI

-- Items the fake client knows: [id] = GetItemInfo results from quality on.
local ITEMS = {
	[5001] = { 2, 18, "INVTYPE_CHEST", 200, DE.ARMOR },   -- green chest, item level 18
	[5002] = { 2, 18, "INVTYPE_2HWEAPON", 200, DE.WEAPON },
	[5003] = { 2, 30, "INVTYPE_HAND", 200, DE.ARMOR },
	[5004] = { 1, 18, "INVTYPE_CHEST", 50, DE.ARMOR },    -- white: cannot be disenchanted
}
C_Item = C_Item or {}
C_Item.GetItemInfo = function(item)
	local i = ITEMS[item]
	if not i then return nil end
	return "Item " .. item, "item:" .. item, i[1], i[2], 1, "", "", 1, i[3], 0, i[4], i[5]
end

-- A stand-in for Kabobo's Auctions' API, with its 5% cut, 1s deposit and prices old after 3 days.
local prices, seenAt = {}, {}
local DAY = 86400
local fakeAuctions = {
	Price = function(item) return prices[item], seenAt[item] end,
	Proceeds = function(gross, auctions)
		return gross - math.floor(gross * 0.05 + 0.5) - 100 * (auctions or 1)
	end,
	StaleAge = function(seen, now)
		local age = (now or time()) - seen
		if age > 3 * DAY then return age end
	end,
}
local DUST, GME, SGS = 10940, 10939, 10978

local function hover(id)
	local lines, order = {}, {}
	local tooltip = { AddDoubleLine = function(_, l, r) lines[l] = r; order[#order + 1] = l end }
	_HOVER(tooltip, { id = id })
	return lines, order
end

local function enchanting(skill)
	GetProfessions = function() return 1 end
	GetProfessionInfo = function() return "Enchanting", 0, skill, 300, 0, 0, 333 end
	_FIRE("SKILL_LINES_CHANGED")
end

-- Rules

test("only uncommon to epic weapons and armor that can be worn disenchant", function()
	truthy(DE.Disenchantable(DE.ARMOR, 2, "INVTYPE_CHEST"))
	truthy(DE.Disenchantable(DE.WEAPON, 4, "INVTYPE_WEAPON"))
	truthy(DE.Disenchantable(DE.ARMOR, 3, "INVTYPE_FINGER"), "rings are armor")
	eq(DE.Disenchantable(DE.ARMOR, 1, "INVTYPE_CHEST"), false, "white")
	eq(DE.Disenchantable(DE.ARMOR, 5, "INVTYPE_CHEST"), false, "legendary")
	eq(DE.Disenchantable(DE.ARMOR, 2, "INVTYPE_BODY"), false, "shirt")
	eq(DE.Disenchantable(DE.ARMOR, 2, "INVTYPE_TABARD"), false, "tabard")
	eq(DE.Disenchantable(9, 2, ""), false, "recipe")
	eq(DE.Disenchantable(DE.ARMOR, nil, "INVTYPE_CHEST"), false, "not cached yet")
end)

test("uncommon armor gives mostly dust, weapons mostly essence", function()
	local armor = DE.Outcomes(2, 18, false)
	eq(#armor, 3)
	eq(armor[1].id, DUST); near(armor[1].chance, 0.75); eq(armor[1].min, 2); eq(armor[1].max, 3)
	eq(armor[2].id, GME); near(armor[2].chance, 0.20)
	eq(armor[3].id, SGS); near(armor[3].chance, 0.05)
	local weapon = DE.Outcomes(2, 18, true)
	eq(weapon[1].id, GME); near(weapon[1].chance, 0.75)
	eq(weapon[2].id, DUST); near(weapon[2].chance, 0.20)
	eq(DE.Outcomes(2, 18, false), armor, "cached")
end)

test("rare and epic outcomes", function()
	local rare = DE.Outcomes(3, 58, false)
	eq(rare[1].id, 14344); near(rare[1].chance, 0.995)
	eq(rare[2].id, 20725); near(rare[2].chance, 0.005)
	eq(#DE.Outcomes(3, 20, true), 1)
	local epic = DE.Outcomes(4, 62, false)
	eq(epic[1].id, 20725); eq(epic[1].min, 1); eq(epic[1].max, 2)
	eq(DE.Outcomes(1, 20, false), nil)
end)

test("expected value and verdict", function()
	local outcomes = DE.Outcomes(2, 18, false)
	local p = { [DUST] = 100, [GME] = 400, [SGS] = 1000 }
	local value, missing = DE.Value(outcomes, function(id) return p[id] end)
	eq(value, 358)   -- .75 * 2.5 * 100 + .2 * 1.5 * 400 + .05 * 1000 = 357.5
	eq(missing, 0)
	eq(DE.Verdict(358, 0, 200), "yes")
	eq(DE.Verdict(358, 0, 400), "no")
	eq(DE.Verdict(358, 0, nil), "yes", "an item that sells for nothing")
	eq(DE.Verdict(120, 1, 200), "unknown")
	eq(DE.Verdict(300, 1, 200), "yes", "already worth more without the unpriced mats")
end)

-- Tooltip

test("no lines without Kabobo's Auctions", function()
	KaboboAddons.KaboboAuctions = nil
	eq(DT.Available(), false)
	local _, order = hover(5001)
	eq(#order, 0)
end)

test("worth disenchanting: mats beat the vendor price", function()
	KaboboAddons.KaboboAuctions = fakeAuctions
	prices = { [DUST] = 100, [GME] = 400, [SGS] = 1000 }
	enchanting(10)
	local lines, order = hover(5001)
	eq(order[1], "Disenchant")
	eq(lines.Disenchant, PUI.Color("worth it", "good"))
	eq(lines["   expected mats"], PUI.MoneyIcons(358 - 18))
	eq(lines["   selling instead"], PUI.MoneyIcons(200) .. PUI.Color(" vendor", "muted"))
	eq(lines["   75% 2-3x Item 10940"], nil, "mats not cached: English fallback names")
	eq(lines["   75% 2-3x Strange Dust"], PUI.MoneyIcons(250))
	eq(lines["   20% 1-2x Greater Magic Essence"], PUI.MoneyIcons(600))
	eq(lines["   5% Small Glimmering Shard"], PUI.MoneyIcons(1000))
	eq(lines["   needs Enchanting"], nil, "any Enchanting skill will do")
end)

test("not worth it when the item sells for more on the AH", function()
	prices[5001] = 2000
	local lines = hover(5001)
	eq(lines.Disenchant, PUI.Color("not worth it", "bad"))
	eq(lines["   selling instead"], PUI.MoneyIcons(2000 - 100 - 100) .. PUI.Color(" AH", "muted"))
	prices[5001] = nil
end)

test("unpriced mats leave it open", function()
	prices = { [GME] = 400 }
	local lines = hover(5001)
	eq(lines.Disenchant, PUI.Color("no AH prices for its mats yet", "muted"))
	eq(lines["   expected mats"], PUI.MoneyIcons(114) .. PUI.Color(" (2 unpriced)", "muted"))
	eq(lines["   75% 2-3x Strange Dust"], PUI.Color("no price", "muted"))
end)

test("weapons, no Enchanting, white items and settings", function()
	prices = { [DUST] = 100, [GME] = 400, [SGS] = 1000 }
	local _, order = hover(5002)
	eq(order[4], "   75% 1-2x Greater Magic Essence", "weapon: essence first")

	local lines = hover(5003)
	eq(lines["   needs Enchanting"], nil, "item level 30 with Enchanting 10")
	GetProfessions = function() return end
	_FIRE("SKILL_LINES_CHANGED")
	lines = hover(5001)
	truthy(lines["   needs Enchanting"], "no Enchanting at all")

	_, order = hover(5004)
	eq(#order, 0, "white item")

	ns.db.settings.disenchantMats = false
	_, order = hover(5001)
	eq(order[4], "   needs Enchanting", "no mats list")
	ns.db.settings.disenchantMats = true

	SlashCmdList.KABOBOPROFESSIONS("de")
	eq(ns.db.settings.disenchant, false)
	_, order = hover(5001)
	eq(#order, 0)
	SlashCmdList.KABOBOPROFESSIONS("de")
	eq(ns.db.settings.disenchant, true)
end)

test("help says the disenchant lines need Kabobo's Auctions when it is missing", function()
	KaboboAddons.KaboboAuctions = nil
	local before = #_PRINTED
	SlashCmdList.KABOBOPROFESSIONS("help")
	local help = table.concat(_PRINTED, "\n", before + 1)
	truthy(help:find("needs Kabobo's Auctions", 1, true), "help mentions the peer")
	KaboboAddons.KaboboAuctions = fakeAuctions
	before = #_PRINTED
	SlashCmdList.KABOBOPROFESSIONS("help")
	help = table.concat(_PRINTED, "\n", before + 1)
	eq(help:find("needs Kabobo's Auctions", 1, true), nil)
end)

test("old AH prices are flagged", function()
	KaboboAddons.KaboboAuctions = fakeAuctions
	enchanting(10)
	local now = time()
	prices = { [DUST] = 100, [GME] = 400, [SGS] = 1000 }
	seenAt = { [DUST] = now - 5 * DAY, [GME] = now, [SGS] = now - DAY }
	local lines = hover(5001)
	local old = PUI.Color(" (5d old)", "warn")
	eq(lines.Disenchant, PUI.Color("worth it", "good") .. PUI.Color(" (old prices)", "warn"))
	eq(lines["   expected mats"], PUI.MoneyIcons(358 - 18) .. old, "the oldest mat price")
	eq(lines["   75% 2-3x Strange Dust"], PUI.MoneyIcons(250) .. old)
	eq(lines["   20% 1-2x Greater Magic Essence"], PUI.MoneyIcons(600), "fresh")
	eq(lines["   selling instead"], PUI.MoneyIcons(200) .. PUI.Color(" vendor", "muted"), "vendor prices never get old")

	-- the item's own AH price is old too
	seenAt = { [DUST] = now, [GME] = now, [SGS] = now, [5001] = now - 8 * DAY }
	prices[5001] = 2000
	lines = hover(5001)
	eq(lines.Disenchant, PUI.Color("not worth it", "bad") .. PUI.Color(" (old prices)", "warn"))
	eq(lines["   selling instead"], PUI.MoneyIcons(1800) .. PUI.Color(" AH", "muted") .. PUI.Color(" (8d old)", "warn"))
	eq(lines["   expected mats"], PUI.MoneyIcons(358 - 18))

	-- an older Kabobo's Auctions without StaleAge: nothing is flagged
	seenAt[DUST] = now - 9 * DAY
	KaboboAddons.KaboboAuctions = { Price = fakeAuctions.Price, Proceeds = fakeAuctions.Proceeds }
	lines = hover(5001)
	eq(lines.Disenchant, PUI.Color("not worth it", "bad"))
	KaboboAddons.KaboboAuctions = fakeAuctions
	prices[5001], seenAt = nil, {}
end)

-- API for other Kabobo addons

test("API: disenchant value of an item", function()
	local api = ns:Peer("KaboboProfessions")
	truthy(api, "Kabobo's Professions exposes an API")
	local p = { [DUST] = 100, [GME] = 400 }
	local value, missing = api.DisenchantValue(5001, function(id) return p[id] end)
	eq(value, 308)   -- .75 * 2.5 * 100 + .2 * 1.5 * 400, shard unpriced
	eq(missing, 1)
	local _, _, oldest = api.DisenchantValue(5001, function(id) return p[id], id == DUST and 50 or 90 end)
	eq(oldest, 50, "when the oldest price used was seen")
	eq(api.DisenchantValue(5004, function() return 1 end), nil, "white item")
	eq(api.DisenchantValue(424242, function() return 1 end), nil, "not cached")
end)
