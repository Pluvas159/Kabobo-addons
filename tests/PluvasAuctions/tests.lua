-- Pluvas' Auctions: tests for the parts that do not need the game client.
-- test/eq/near come from tests/lib/harness.lua; WoW stand-ins from tests/lib/mocks.lua.
local ns = _NS
local P, L = ns.Pricing, ns.Ledger
local PUI = ns.PluvasUI

-- Boot the addon like the client does.
_FIRE("ADDON_LOADED", "PluvasAuctions")
_FIRE("PLAYER_LOGIN")

test("realm key combines realm and faction", function()
	eq(ns.realmKey, "Forever-Horde")
end)

-- Item keys

test("item key from a plain link", function()
	eq(P.ItemKeyFromLink("|cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r"), "2589")
end)

test("item key keeps random suffix", function()
	eq(P.ItemKeyFromLink("|cff1eff00|Hitem:15210::::::1180::60:::::|h[Raider's Shortsword of the Bear]|h|r"), "15210:1180")
end)

test("item key handles negative suffix", function()
	eq(P.ItemKeyFromLink("|Hitem:15210::::::-42::60|h[x]|h"), "15210:-42")
end)

test("item key rejects non-links", function()
	eq(P.ItemKeyFromLink("hello"), nil)
	eq(P.ItemKeyFromLink(nil), nil)
end)

-- Statistics

test("stats: single listing", function()
	local s = P.ComputeStats({ { 500, 1 } })
	eq(s.min, 500); eq(s.market, 500); eq(s.qty, 1); eq(s.auctions, 1)
end)

test("stats: empty is nil", function()
	eq(P.ComputeStats({}), nil)
end)

test("stats: market ignores expensive tail", function()
	-- 10 units at 100, 90 units at 1000: cheapest 30% = 10@100 + 20@1000
	local s = P.ComputeStats({ { 1000, 90 }, { 100, 10 } })
	eq(s.min, 100)
	eq(s.qty, 100)
	-- median of the 30 cheapest units is 1000, so the 100s are outliers and dropped
	eq(s.market, 1000)
end)

test("stats: a single 1c listing does not drag market down", function()
	local s = P.ComputeStats({ { 1, 1 }, { 5000, 5 }, { 5100, 5 }, { 5200, 5 } })
	eq(s.min, 1)
	eq(s.market, 5000)
end)

test("stats: averages units near the median", function()
	local s = P.ComputeStats({ { 100, 2 }, { 110, 2 }, { 120, 2 }, { 900, 14 } })
	-- cap = 6 units: 2@100, 2@110, 2@120 -> median 110, all within range, mean 110
	eq(s.market, 110)
end)

-- Price database

test("record and history average", function()
	local items = {}
	local day = 86400
	local t0 = 1000 * day
	P.Record(items, "1", { market = 100, min = 90, qty = 5 }, t0)
	P.Record(items, "1", { market = 200, min = 80, qty = 5 }, t0 + 60)       -- same day: averaged
	P.Record(items, "1", { market = 300, min = 300, qty = 5 }, t0 + day)     -- next day
	local m, lo, c = P.ParseDay(items["1"].h[1000])
	eq(m, 150); eq(lo, 80); eq(c, 2)
	local avg, days = P.HistoryAverage(items["1"], t0 + day, 14)
	eq(avg, 225); eq(days, 2)
	eq(items["1"].m, 300)
end)

test("browse minimum does not overwrite market but seeds it", function()
	local items = {}
	P.RecordMin(items, "2", 70, 3, 0)
	eq(items["2"].m, 70)
	P.Record(items, "2", { market = 100, min = 95, qty = 4 }, 10)
	P.RecordMin(items, "2", 60, 9, 20)
	eq(items["2"].m, 100); eq(items["2"].n, 60); eq(items["2"].q, 9)
	local m, lo, c = P.ParseDay(items["2"].h[0])
	eq(m, 100); eq(lo, 60); eq(c, 1)
end)

test("prune drops old days", function()
	local items = { a = { h = { [1] = "1:1:1", [100] = "2:2:1" } } }
	P.Prune(items, 100 * 86400, 60)
	eq(items.a.h[1], nil)
	eq(items.a.h[100], "2:2:1")
end)

-- Ledger

local function sale(t, gross, who) return { k = "s", item = "Linen Cloth", qty = 20, gross = gross or 1000, cut = 50, who = who or "Bob", t = t } end

test("merge skips the same mail seen again", function()
	local list = {}
	eq(L.Merge(list, { sale(1000) }), 1)
	eq(L.Merge(list, { sale(1030) }), 0)  -- same mail, slightly different estimate
	eq(#list, 1)
end)

test("merge keeps identical sales that are separate mails", function()
	local list = {}
	eq(L.Merge(list, { sale(1000), sale(1000) }), 2)
	eq(L.Merge(list, { sale(1000), sale(1000) }), 0)
	eq(L.Merge(list, { sale(1000), sale(1000), sale(1000) }), 1)
	eq(#list, 3)
end)

test("merge treats far-apart times as different sales", function()
	local list = {}
	L.Merge(list, { sale(0) })
	eq(L.Merge(list, { sale(4000) }), 1)
end)

test("summarize totals", function()
	local list = {
		sale(100, 1000), sale(200, 2000),
		{ k = "b", item = "Silk Cloth", qty = 1, gross = 700, t = 300 },
	}
	local s = L.Summarize(list)
	eq(s.sales, 3000); eq(s.cut, 100); eq(s.netSales, 2900); eq(s.bought, 700); eq(s.profit, 2200)
	eq(L.Summarize(list, 150).sales, 2000)
end)

test("top items sorted by net", function()
	local list = {
		sale(1, 1000),
		{ k = "s", item = "Silk Cloth", qty = 1, gross = 5000, cut = 250, t = 2 },
		{ k = "b", item = "Silk Cloth", qty = 1, gross = 1000, t = 3 },
	}
	local top = L.TopItems(list)
	eq(top[1].item, "Silk Cloth"); eq(top[1].net, 4750); eq(top[1].profit, 3750)
	eq(top[2].item, "Linen Cloth")
end)

test("sales per item", function()
	local by = L.SalesByItem({ sale(1, 1000), sale(2, 3000), { k = "b", item = "Linen Cloth", qty = 5, gross = 99, t = 3 } })
	eq(by["Linen Cloth"].total, 4000); eq(by["Linen Cloth"].qty, 40)
end)

test("merge keeps the list sorted by time", function()
	local list = {}
	L.Merge(list, { sale(5000), sale(1000, 7), sale(3000, 9) })
	eq(list[1].t, 1000); eq(list[2].t, 3000); eq(list[3].t, 5000)
end)

test("merge only compares entries near the incoming mail", function()
	-- An identical sale far in the past is never compared, so it cannot swallow a new one.
	local list = { sale(0) }
	eq(L.Merge(list, { sale(100000) }), 1)
	eq(#list, 2)
end)

test("inbox scan records invoices once", function()
	local mails = {
		{ "seller", "Linen Cloth", "Bob", 1000, 0, 60, 50, 0, 0, 0, 20, days = 29.5 },
		{ "buyer", "Silk Cloth", "Ann", 700, 700, 0, 0, 0, 0, 0, 1, days = 29.9 },
		{ nil, days = 3 }, -- ordinary mail
	}
	GetInboxNumItems = function() return #mails end
	GetInboxHeaderInfo = function(i) return nil, nil, "x", "subj", 0, 0, mails[i].days end
	GetInboxInvoiceInfo = function(i) return unpack(mails[i], 1, 11) end
	_FIRE("MAIL_INBOX_UPDATE")
	_FIRE("MAIL_INBOX_UPDATE")
	local tx = L:Transactions()
	eq(#tx, 2)
	local sold = tx[1].k == "s" and tx[1] or tx[2]
	eq(sold.gross, 1000); eq(sold.cut, 50); eq(sold.qty, 20); eq(sold.who, "Bob"); eq(sold.char, "Pluvas")
end)

-- Gold

test("gold summary across characters", function()
	_MONEY = 12345
	_FIRE("PLAYER_MONEY")
	local chars = L:GoldTable()
	chars["Alt"] = { money = 5000, days = { [ns.DayStart() - 86400] = 4000 } }
	local total, change = L:GoldSummary()
	eq(total, 17345); eq(change, 1000)
end)

-- Full scan through mocked replicate API

test("full scan groups auctions per item and records market", function()
	local auctions = {
		{ id = 2589, qty = 20, buyout = 2000 },   -- 100 per unit
		{ id = 2589, qty = 10, buyout = 1200 },   -- 120 per unit
		{ id = 4306, qty = 1, buyout = 0 },       -- bid only: ignored
		{ id = 15210, qty = 1, buyout = 50000, suffix = 1180 },
	}
	C_AuctionHouse = {
		ReplicateItems = function() end,
		GetNumReplicateItems = function() return #auctions end,
		GetReplicateItemInfo = function(i)
			local a = auctions[i + 1]
			return "n", 0, a.qty, 1, true, 1, nil, 0, 0, a.buyout, 0, false, nil, "o", nil, 0, a.id, true
		end,
		GetReplicateItemLink = function(i)
			local a = auctions[i + 1]
			return "|Hitem:" .. a.id .. "::::::" .. (a.suffix or "") .. "::60|h[x]|h"
		end,
	}
	ns.db.account.lastReplicate = 0
	_FIRE("AUCTION_HOUSE_SHOW")
	ns.Scanner:FullScan()
	eq(ns.Scanner.state, "waiting")
	_FIRE("REPLICATE_ITEM_LIST_UPDATE")
	_RUN_TIMERS()
	eq(ns.Scanner.state, "idle")
	local items = ns.Pricing:Realm().items
	eq(items["2589"].n, 100)
	eq(items["2589"].q, 30)
	eq(items["15210:1180"].m, 50000)
	eq(items["4306"], nil)
	-- cooldown now blocks another scan
	ns.Scanner:FullScan()
	eq(ns.Scanner.state, "idle")
	assert(ns.Scanner:CooldownRemaining() > 0)
end)

test("a full scan is discarded when the auction house closes mid-scan", function()
	local auctions = {}
	for i = 1, 2500 do auctions[i] = { id = 50000 + i, qty = 1, buyout = 100 } end
	C_AuctionHouse.GetNumReplicateItems = function() return #auctions end
	C_AuctionHouse.GetReplicateItemInfo = function(i)
		local a = auctions[i + 1]
		return "n", 0, a.qty, 1, true, 1, nil, 0, 0, a.buyout, 0, false, nil, "o", nil, 0, a.id, true
	end
	C_AuctionHouse.GetReplicateItemLink = function(i) return "|Hitem:" .. auctions[i + 1].id .. "::::::::60|h[x]|h" end
	ns.db.account.lastReplicate = 0
	local reads = 0
	local info = C_AuctionHouse.GetReplicateItemInfo
	C_AuctionHouse.GetReplicateItemInfo = function(i)
		reads = reads + 1
		if reads == 10 then _FIRE("AUCTION_HOUSE_CLOSED") end
		return info(i)
	end
	ns.Scanner:FullScan()
	_FIRE("REPLICATE_ITEM_LIST_UPDATE")
	_RUN_TIMERS()
	eq(ns.Scanner.state, "idle")
	eq(reads, ns.Scanner.CHUNK, "stops after the batch that was running")
	eq(P:Get("50001"), nil, "nothing saved")
end)

test("scan button text follows the scanner", function()
	local SB = ns.ScanButton
	eq((SB.Label("waiting", 0, 0)), "Waiting for AH...")
	eq((SB.Label("processing", 0.5, 0)), "Scanning 50%")
	local text, enabled = SB.Label("idle", 0, 65)
	eq(text, "Full scan in 1:05"); eq(enabled, false)
	text, enabled = SB.Label("idle", 0, 0)
	eq(text, "Full scan"); eq(enabled, true)
end)

-- Selling costs

test("deposit is a flat 1 silver per auction", function()
	eq(P.DEPOSIT, 100)
end)

test("net proceeds take off the 5% cut and the deposit", function()
	local gross, cut, net = P.NetProceeds(10000, 20, 300)
	eq(gross, 200000)
	eq(cut, 10000)
	eq(net, 189700)
	gross, cut, net = P.NetProceeds(50, 1, 0)
	eq(gross, 50)
	eq(cut, 3)
	eq(net, 47)
end)

test("tooltip shows stack total and net after cut and deposit", function()
	local items = ns.db.realms[ns.realmKey].items
	items["9999"] = { m = 10000, n = 9000, q = 5, t = time() }
	local lines = {}
	local tooltip = { AddDoubleLine = function(_, l, r) lines[#lines + 1] = { l, r } end }
	ns.Tooltip:AddLines(tooltip, { key = "9999", id = 9999, count = 20 })
	local byLabel = {}
	for _, line in ipairs(lines) do byLabel[line[1]] = line[2] end
	eq(byLabel["AH market x20"], PUI.MoneyIcons(200000))
	eq(byLabel["After cut & deposit|cff808080 (x20)|r"], PUI.MoneyIcons(200000 - 10000 - 100))

	-- A single item gets the net line but no stack total.
	lines = {}
	ns.Tooltip:AddLines(tooltip, { key = "9999", id = 9999, count = 1 })
	byLabel = {}
	for _, line in ipairs(lines) do byLabel[line[1]] = line[2] end
	eq(byLabel["AH market x1"], nil)
	eq(byLabel["After cut & deposit"], PUI.MoneyIcons(10000 - 500 - 100))

	items["9999"] = nil
end)

test("tooltip shows your average sale, and learns of new sales", function()
	local tx = L:Transactions()
	local before = #tx
	L.Merge(tx, { { k = "s", item = "Silk Cloth", qty = 10, gross = 2000, cut = 100, who = "Zed", t = time() } })
	local function soldLine()
		local lines = {}
		local tooltip = { AddDoubleLine = function(_, l, r) lines[l] = r end }
		ns.Tooltip:AddLines(tooltip, { key = "4306", id = 4306, name = "Silk Cloth", count = 1 })
		return lines["You sold at"]
	end
	eq(soldLine(), PUI.MoneyIcons(200) .. "|cff808080 (10 sold)|r")
	-- A new sale arrives by mail: the cached average must not go stale.
	GetInboxNumItems = function() return 1 end
	GetInboxHeaderInfo = function() return nil, nil, "x", "subj", 0, 0, 30 end
	GetInboxInvoiceInfo = function() return "seller", "Silk Cloth", "Amy", 6000, 0, 0, 300, 0, 0, 0, 10 end
	_FIRE("MAIL_INBOX_UPDATE")
	eq(soldLine(), PUI.MoneyIcons(400) .. "|cff808080 (20 sold)|r")
	for i = #tx, before + 1, -1 do table.remove(tx, i) end
	GetInboxNumItems = function() return 0 end
end)

test("slash toggles flip tooltip settings and announce it", function()
	local seen
	ns:On("SettingChanged", function(key, value) seen = key .. "=" .. tostring(value) end)
	SlashCmdList.PLUVASAUCTIONS("history")
	eq(ns.db.settings.tooltipHistory, false)
	eq(seen, "tooltipHistory=false")
	SlashCmdList.PLUVASAUCTIONS("history")
	eq(ns.db.settings.tooltipHistory, true)
end)

-- Crafting

local CR = ns.Crafting

test("recipe strings round-trip", function()
	local s = CR.Encode(1, 2, { { 2589, 2 }, { 2320, 1 } })
	eq(s, "1:2|2589*2,2320*1")
	local lo, hi, mats = CR.Decode(s)
	eq(lo, 1); eq(hi, 2)
	eq(#mats, 2)
	eq(mats[1][1], 2589); eq(mats[1][2], 2)
	eq(CR.Decode("junk"), nil)
end)

test("mats cost per crafted item", function()
	local prices = { [2589] = 100, [2320] = 50 }
	local priceOf = function(id) return prices[id] end
	local cost, missing = CR.CostPerItem("1:1|2589*2,2320*1", priceOf)
	eq(cost, 250); eq(missing, 0)
	-- 2 items per craft halves the cost per item
	eq((CR.CostPerItem("2:2|2589*2,2320*1", priceOf)), 125)
	-- unpriced mats are counted, priced ones still summed
	cost, missing = CR.CostPerItem("1:1|2589*2,9999*1", priceOf)
	eq(cost, 200); eq(missing, 1)
	-- nothing priced at all
	cost, missing = CR.CostPerItem("1:1|9998*1,9999*1", priceOf)
	eq(cost, nil); eq(missing, 2)
end)

test("profession scan stores learned recipes and the tooltip shows mats cost", function()
	Enum = Enum or {}
	Enum.CraftingReagentType = { Modifying = 0, Basic = 1, Finishing = 2 }
	C_TradeSkillUI = {
		GetBaseProfessionInfo = function() return { professionID = 197, professionName = "Tailoring" } end,
		GetAllRecipeIDs = function() return { 1, 2, 3 } end,
		GetRecipeInfo = function(id) return { learned = id ~= 3 } end,
		GetRecipeSchematic = function(id)
			if id == 1 then
				return { outputItemID = 2996, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = {
					{ reagentType = 1, quantityRequired = 2, reagents = { { itemID = 2589 } } },
					{ reagentType = 1, quantityRequired = 1, reagents = { { itemID = 2320 } } },
					{ reagentType = 0, quantityRequired = 1, reagents = { { itemID = 7777 } } },   -- optional
				} }
			elseif id == 2 then
				return { reagentSlotSchematics = {} }   -- an enchant: no item made
			end
			return { outputItemID = 3000, reagentSlotSchematics = {
				{ reagentType = 1, quantityRequired = 1, reagents = { { itemID = 2589 } } } } }
		end,
	}
	CR:OnLogin()
	_FIRE("TRADE_SKILL_SHOW")
	_RUN_TIMERS()

	eq(CR:RecipeFor(2996), "1:1|2589*2,2320*1")
	eq(CR:RecipeFor(3000), nil)   -- recipe 3 is not learned

	local items = ns.db.realms[ns.realmKey].items
	items["2589"] = { m = 100, t = time() }
	items["2320"] = { n = 50, t = time() }
	local lines = {}
	local tooltip = { AddDoubleLine = function(_, l, r) lines[#lines + 1] = { l, r } end }
	ns.Tooltip:AddLines(tooltip, { key = "2996", id = 2996, count = 3 })
	local byLabel = {}
	for _, line in ipairs(lines) do byLabel[line[1]] = line[2] end
	eq(byLabel["Mats cost (AH)|cff808080 (x3)|r"], PUI.MoneyIcons(750))
	eq(byLabel["   6x item:2589"], PUI.MoneyIcons(600))
	eq(byLabel["   3x item:2320"], PUI.MoneyIcons(150))

	-- a broken client function must not stop the addon: the scan reports and keeps old data
	local oldHandler = geterrorhandler
	local reported = 0
	geterrorhandler = function() return function() reported = reported + 1 end end
	C_TradeSkillUI.GetRecipeSchematic = function() error("client bug") end
	ns.Crafting:Scan()
	_RUN_TIMERS()
	geterrorhandler = oldHandler
	eq(CR:RecipeFor(2996), "1:1|2589*2,2320*1")

	items["2589"], items["2320"] = nil, nil
	C_TradeSkillUI = nil
	CR:OnLogin()
end)

test("dropped professions are pruned at login", function()
	local me = CR:CharTable()
	me[197] = { name = "Tailoring", r = { [2996] = "1:1|2589*1" } }
	me[164] = { name = "Blacksmithing", r = { [2862] = "1:1|2835*1" } }
	GetProfessions = function() return 1, nil end
	GetProfessionInfo = function() return "Tailoring", nil, 1, 300, 0, 0, 197 end
	CR:PruneProfessions()
	truthy(me[197], "kept Tailoring")
	eq(me[164], nil)
	-- no professions listed yet (early login): keep everything
	GetProfessions = function() return nil end
	CR:PruneProfessions()
	truthy(me[197], "still kept")
	GetProfessions, GetProfessionInfo = nil, nil
end)

test("mats cost recurses into mats the character can craft", function()
	-- Bolt of Linen (2996) = 2 Linen Cloth (2589); Linen Bag (4238) = 3 bolts + 1 thread (2320)
	local prices = { [2589] = 100, [2320] = 50, [2996] = 999 }
	local recipes = { [2996] = "1:1|2589*2" }
	local priceOf = function(id) return prices[id] end
	local recipeOf = function(id) return recipes[id] end
	-- bolts priced from cloth (200 each), not their 999 AH price
	eq((CR.CostPerCraft("1:1|2996*3,2320*1", priceOf, recipeOf)), 650)
	-- without recipes the AH price of the bolt is used
	eq((CR.CostPerCraft("1:1|2996*3,2320*1", priceOf)), 3047)

	-- three levels deep, with a recipe that makes 2 per craft
	recipes[1001] = "2:2|2996*1"          -- 2 of item 1001 per bolt -> 100 each
	eq((CR.CostPerCraft("1:1|1001*4", priceOf, recipeOf)), 400)

	-- a crafted mat whose own mats are unpriced falls back to its AH price
	recipes[2996] = "1:1|5555*2"
	local cost, missing = CR.CostPerCraft("1:1|2996*1", priceOf, recipeOf)
	eq(cost, 999); eq(missing, 0)
	-- ...and counts as unpriced when it has no AH price either
	prices[2996] = nil
	cost, missing = CR.CostPerCraft("1:1|2996*1,2320*1", priceOf, recipeOf)
	eq(cost, 50); eq(missing, 1)

	-- cycles stop instead of looping forever
	recipes = { [1] = "1:1|2*1", [2] = "1:1|1*1" }
	prices = { [1] = 30, [2] = 70 }
	eq((CR.CostPerCraft("1:1|1*1", priceOf, recipeOf)), 30)
end)

test("profession panel lines", function()
	local Lines = ns.Lines
	local lines = Lines.Craft({ cost = 650, missing = 0, yield = 1, value = 1000, net = 935, profit = 285 })
	eq(#lines, 4)
	eq(lines[1][1], "Mats cost (AH)")
	eq(lines[1][2], PUI.MoneyIcons(650))
	eq(lines[2][2], PUI.MoneyIcons(1000))
	eq(lines[3][2], PUI.MoneyIcons(935))
	eq(lines[4][2], "|cff40d040+|r" .. PUI.MoneyIcons(285))

	lines = Lines.Craft({ cost = 2000, missing = 1, yield = 2, value = 1000, net = 935, profit = -1065 })
	eq(lines[1][1], "Mats cost (AH)|cff808080 (per craft, makes 2)|r")
	eq(lines[1][2], PUI.MoneyIcons(2000) .. "|cff808080 (1 mats unpriced)|r")
	eq(lines[4][2], "|cffff5050-|r" .. PUI.MoneyIcons(1065))

	lines = Lines.Craft({ missing = 2, yield = 1 })
	eq(#lines, 2)
	eq(lines[1][2], "|cff808080no AH prices for mats|r")
	eq(lines[2][2], "|cff808080no AH price yet|r")
end)

test("craft summary: sale value, cut, deposit and profit", function()
	local prices = { [2589] = 100 }
	local s = CR.CraftSummary("1:1|2589*2", function(id) return prices[id] end, nil, 1000)
	eq(s.cost, 200)
	eq(s.value, 1000)
	eq(s.net, 1000 - 50 - 100)
	eq(s.profit, 1000 - 50 - 100 - 200)
	s = CR.CraftSummary("1:1|2589*2", function(id) return prices[id] end, nil, nil)
	eq(s.value, nil); eq(s.profit, nil); eq(s.cost, 200)
end)

test("mats list shows the base mats behind the cost", function()
	-- Linen Bag (4238) = 3 Bolt of Linen (2996) + 1 Coarse Thread (2320); bolt = 2 Linen (2589)
	local prices = { [2589] = 100, [2320] = 50 }
	local recipes = { [2996] = "1:1|2589*2" }
	local priceOf = function(id) return prices[id] end
	local recipeOf = function(id) return recipes[id] end

	local cost, missing, yield, mats = CR.CostPerCraft("1:1|2996*3,2320*1,7777*2", priceOf, recipeOf)
	eq(cost, 650); eq(missing, 1); eq(yield, 1)
	eq(#mats, 3)
	eq(mats[1].id, 2589); eq(CR.FormatQty(mats[1].qty), "6"); eq(mats[1].cost, 600)
	eq(mats[2].id, 2320); eq(CR.FormatQty(mats[2].qty), "1"); eq(mats[2].cost, 50)
	eq(mats[3].id, 7777); eq(mats[3].cost, nil)   -- unpriced mats go last

	-- for a stack of 4 bags everything is multiplied
	local total, _, list = CR.CostForItems("1:1|2996*3,2320*1", 4, priceOf, recipeOf)
	eq(total, 2600)
	eq(CR.FormatQty(list[1].qty), "24"); eq(list[1].cost, 2400)

	-- a recipe making 2 per craft gives fractional mats per item
	recipes[1001] = "2:2|2589*3"
	_, _, list = CR.CostForItems("1:1|1001*1", 1, priceOf, recipeOf)
	eq(CR.FormatQty(list[1].qty), "1.5"); eq(list[1].cost, 150)
	eq(CR.FormatQty(1 / 3), "0.33")
end)

test("profession panel lists mats", function()
	local Lines = ns.Lines
	local summary = { cost = 650, missing = 0, yield = 1, mats = {
		{ id = 2589, qty = 6, unit = 100, cost = 600 },
		{ id = 2320, qty = 1, unit = 50, cost = 50 },
	} }
	local lines = Lines.Craft(summary, true)
	eq(lines[2][1], "   6x item:2589")      -- item not in the (mock) cache: falls back to item:<id>
	eq(lines[2][2], PUI.MoneyIcons(600))
	eq(lines[2].color, "soft")
	eq(lines[3][2], PUI.MoneyIcons(50))
	eq(#Lines.Craft(summary, false), #lines - 2)
end)

test("long mat lists end in a '+N more' line", function()
	local mats = {}
	for i = 1, 13 do mats[i] = { id = i, qty = 1 } end
	local out = ns.Lines.AddMats({}, mats, 10)
	eq(#out, 11)
	eq(out[11][1], "   +3 more")
	eq(out[11].color, "muted")
end)

test("a crafting scan spread over frames stops when the window closes", function()
	local ids, reads = {}, 0
	for i = 1, 100 do ids[i] = i end
	C_TradeSkillUI = {
		GetBaseProfessionInfo = function() return { professionID = 197, professionName = "Tailoring" } end,
		GetAllRecipeIDs = function() return ids end,
		GetRecipeInfo = function()
			reads = reads + 1
			if reads == 5 then _FIRE("TRADE_SKILL_CLOSE") end
			return { learned = false }
		end,
	}
	_FIRE("TRADE_SKILL_SHOW")
	_RUN_TIMERS()
	eq(reads, 40, "only the batch already running finishes")
	C_TradeSkillUI = nil
end)
