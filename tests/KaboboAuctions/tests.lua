-- Kabobo's Auctions: tests for the parts that do not need the game client.
-- test/eq/near come from tests/lib/harness.lua; WoW stand-ins from tests/lib/mocks.lua.
local ns = _NS
local P, L = ns.Pricing, ns.Ledger
local PUI = ns.KaboboUI

-- Boot the addon like the client does.
_FIRE("ADDON_LOADED", "KaboboAuctions")
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
	eq(sold.gross, 1000); eq(sold.cut, 50); eq(sold.qty, 20); eq(sold.who, "Bob"); eq(sold.char, "Kabobo")
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
	SlashCmdList.KABOBOAUCTIONS("history")
	eq(ns.db.settings.tooltipHistory, false)
	eq(seen, "tooltipHistory=false")
	SlashCmdList.KABOBOAUCTIONS("history")
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
	eq(byLabel["Mats cost|cff808080 (x3)|r"], PUI.MoneyIcons(750))
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
	eq(lines[1][1], "Mats cost")
	eq(lines[1][2], PUI.MoneyIcons(650))
	eq(lines[2][2], PUI.MoneyIcons(1000))
	eq(lines[3][2], PUI.MoneyIcons(935))
	eq(lines[4][2], "|cff40d040+|r" .. PUI.MoneyIcons(285))

	lines = Lines.Craft({ cost = 2000, missing = 1, yield = 2, value = 1000, net = 935, profit = -1065 })
	eq(lines[1][1], "Mats cost|cff808080 (per craft, makes 2)|r")
	eq(lines[1][2], PUI.MoneyIcons(2000) .. "|cff808080 (1 mats unpriced)|r")
	eq(lines[4][2], "|cffff5050-|r" .. PUI.MoneyIcons(1065))

	lines = Lines.Craft({ missing = 2, yield = 1 })
	eq(#lines, 2)
	eq(lines[1][2], "|cff808080no prices for mats|r")
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

test("profession panel mats are cut short to fit under the reagents", function()
	local Lines = ns.Lines
	local mats = {}
	for i = 1, 8 do mats[i] = { id = 2000 + i, qty = 1, unit = 10, cost = 10 } end
	local summary = { cost = 80, missing = 0, yield = 1, value = 1000, net = 935, profit = 855, mats = mats }
	eq(#Lines.Craft(summary, true), 12, "everything without a limit")
	local lines = Lines.Craft(summary, true, nil, 8)
	eq(#lines, 8)
	eq(lines[5][1], "   +5 more")
	eq(lines[6][1], "Sells for (AH)")
	eq(#Lines.Craft(summary, true, nil, 4), 4, "no room for mats")
	eq(#Lines.Craft(summary, true, nil, 12), 12, "all fit")

	-- room measured between the lowest reagent and the Track Recipe checkbox
	local function frame(bottom, top) return { IsShown = function() return true end,
		GetBottom = function() return bottom end, GetTop = function() return top end } end
	local form = { Reagents = frame(300), TrackRecipeCheckbox = frame(100, 120), GetBottom = function() return 100 end }
	eq(ns.CraftPanel.LinesThatFit(form, 14), 11)   -- 300 - 8 - (100 + 26) = 166 px
	eq(ns.CraftPanel.LinesThatFit({}, 14), nil)
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

test("vendor visit records what it charges per unit", function()
	local items = {
		{ link = "|Hitem:2320::::|h[Coarse Thread]|h", name = "Coarse Thread", price = 10, stack = 1, avail = -1 },
		{ link = "|Hitem:2678::::|h[Mild Spices]|h", name = "Mild Spices", price = 100, stack = 5, avail = -1 },
		{ link = "|Hitem:4340::::|h[Gray Dye]|h", name = "Gray Dye", price = 350, stack = 1, avail = 2 },
		{ link = "|Hitem:9999::::|h[Token Thing]|h", name = "Token Thing", price = 0, stack = 1, avail = -1, ext = true },
	}
	GetMerchantNumItems = function() return #items end
	GetMerchantItemLink = function(i) return items[i].link end
	C_MerchantFrame = { GetItemInfo = function(i)
		local it = items[i]
		return { name = it.name, price = it.price, stackCount = it.stack, numAvailable = it.avail, hasExtendedCost = it.ext or false }
	end }
	local changed = 0
	ns:On("VendorPricesChanged", function() changed = changed + 1 end)
	_FIRE("MERCHANT_SHOW")
	_RUN_TIMERS()
	_FIRE("MERCHANT_CLOSED")
	eq(ns.Vendor:Get(2320), 10)
	eq(ns.Vendor:Get(2678), 20, "price per unit, not per purchase")
	eq(ns.Vendor:Get(4340), nil, "limited supply")
	eq(ns.Vendor:Get(9999), nil, "no plain gold price")
	eq(changed, 1)

	-- nothing new on the next visit: no message
	_FIRE("MERCHANT_SHOW")
	_RUN_TIMERS()
	_FIRE("MERCHANT_CLOSED")
	eq(changed, 1)

	-- and never a merchant read once the window has closed
	local reads = 0
	GetMerchantItemLink = function(i) reads = reads + 1; return items[i].link end
	_FIRE("MERCHANT_SHOW")
	_FIRE("MERCHANT_CLOSED")
	_RUN_TIMERS()
	eq(reads, 0)
	GetMerchantNumItems, GetMerchantItemLink, C_MerchantFrame = nil, nil, nil
	ns.db.vendor = {}
end)

test("mats use the cheaper of AH and vendor prices", function()
	local items = ns.db.realms[ns.realmKey].items
	items["2320"] = { m = 50, t = time() }   -- thread on the AH at 50c
	items["2589"] = { m = 100, t = time() }
	ns.db.vendor[2320] = 10                    -- ...and 10c at the vendor
	ns.db.vendor[2589] = 400                   -- a vendor price above the AH is not used
	ns.db.vendor[4340] = 350                   -- only a vendor sells this one
	local price, source = CR.MatPrice(2320)
	eq(price, 10); eq(source, "vendor")
	price, source = CR.MatPrice(2589)
	eq(price, 100); eq(source, nil)
	eq(CR.MatPrice(4340), 350)
	eq(CR.AHPrice(2320), 50, "sale value stays the AH price")

	local cost, missing, _, mats = CR.CostPerCraft("1:1|2589*2,2320*1,4340*1", CR.MatPrice)
	eq(cost, 200 + 10 + 350); eq(missing, 0)
	eq(mats[1].id, 4340); eq(mats[1].vendor, true)
	eq(mats[2].id, 2589); eq(mats[2].vendor, nil)
	eq(mats[3].id, 2320); eq(mats[3].vendor, true)

	local lines = ns.Lines.AddMats({}, mats)
	eq(lines[1][2], PUI.MoneyIcons(350) .. "|cff808080 vendor|r")
	eq(lines[2][2], PUI.MoneyIcons(200))

	-- the tooltip shows the vendor price, for the whole stack
	local out = ns.Lines.Tooltip({ key = "2320", id = 2320, count = 20 }, { tooltipHistory = false }, time())
	local byLabel = {}
	for _, line in ipairs(out) do byLabel[line[1]] = line[2] end
	eq(byLabel["Buy from vendor|cff808080 (x20)|r"], PUI.MoneyIcons(200))

	items["2320"], items["2589"] = nil, nil
	ns.db.vendor = {}
end)

test("crafts are ranked by profit, incomplete and unpriced ones last", function()
	local prices = { [10] = 100, [20] = 50 }
	local out = { [1] = 1000, [2] = 400, [3] = 2000, [5] = 300 }
	local listed = { [1] = 7 }
	local recipes = {
		[1] = "1:1|10*2",          -- cost 200, net 1000-50-100 = 850, profit 650
		[2] = "1:1|20*1",          -- cost 50, net 400-20-100 = 280, profit 230
		[3] = "1:1|10*1,99*1",     -- mat 99 unpriced: profit 2000-100-100-100 = 1700, but tier 2
		[4] = "1:1|10*1",          -- no AH price for the item: tier 3
		[5] = "1:1|10*5",          -- cost 500, net 300-15-100 = 185, loss -315
	}
	local rows = CR.Rank(recipes, function(id) return prices[id] end, nil,
		function(id) return out[id] end, function(id) return listed[id] end)
	eq(#rows, 5)
	eq(rows[1].id, 1); eq(rows[1].profit, 650); eq(rows[1].listed, 7); eq(rows[1].tier, 1)
	eq(rows[2].id, 2); eq(rows[2].profit, 230)
	eq(rows[3].id, 5); eq(rows[3].profit, -315)
	eq(rows[4].id, 3); eq(rows[4].tier, 2); eq(rows[4].missing, 1)
	eq(rows[5].id, 4); eq(rows[5].tier, 3); eq(rows[5].profit, nil); eq(rows[5].listed, nil)
	eq(#CR.Rank(nil, function() end, nil, function() end), 0)
end)

test("saved professions become tabs sorted by name", function()
	local me = CR:CharTable()
	for k in pairs(me) do me[k] = nil end
	me[197] = { name = "Tailoring", r = {} }
	me[164] = { name = "Blacksmithing", r = {} }
	local tabs = CR:Professions()
	eq(#tabs, 2)
	eq(tabs[1].key, 164); eq(tabs[1].text, "Blacksmithing")
	eq(tabs[2].key, 197)
	me[197], me[164] = nil, nil
end)

test("shopping: the cap follows the days before today, not today's listings", function()
	local SH, P = ns.Shopping, ns.Pricing
	local now = 100 * 86400 + 3600
	local today = P.DayIndex(now)
	eq(SH.CapBase(nil, now), nil)
	eq(SH.CapBase({ h = { [today] = "900:900:3" } }, now), nil, "today alone")
	eq(SH.CapBase({ h = { [today] = "900:900:3", [today - 1] = "40:40:1", [today - 2] = "60:60:2" } }, now), 50)
	eq(SH.CapBase({ h = { [today - 30] = "40:40:1" } }, now), nil, "too old")
	eq(SH.CapBase({ h = { [today - 1] = "40:40:0" } }, now), nil, "a lowest price only")
end)

test("shopping: price cap, commodity and item offers", function()
	local SH = ns.Shopping
	eq(SH.Cap(100, 1.2), 120)
	eq(SH.Cap(nil, 1.2), nil)
	eq(SH.Cap(0, 1.2), nil)

	-- cheapest first, stops at the cap, skips your own listings, never more than needed
	local listings = { { 90, 5, true }, { 100, 10 }, { 110, 10 }, { 130, 50 } }
	local qty, total = SH.CommodityOffer(listings, 15, 120)
	eq(qty, 15); eq(total, 10 * 100 + 5 * 110)
	qty, total = SH.CommodityOffer(listings, 100, 120)
	eq(qty, 20); eq(total, 10 * 100 + 10 * 110)
	qty = SH.CommodityOffer(listings, 10, 50)
	eq(qty, 0)

	-- item auctions: cheapest per unit under the cap, preferring one that does not overbuy
	local auctions = {
		{ 1, 1000, 20 },        -- 50 each, but 20 > 5 needed
		{ 2, 330, 5 },          -- 66 each, fits
		{ 3, 300, 5, true },    -- own auction
		{ 4, 2000, 5 },         -- 400 each: over the cap
	}
	eq(SH.ItemOffer(auctions, 5, 120)[1], 2)
	eq(SH.ItemOffer(auctions, 20, 120)[1], 1)
	eq(SH.ItemOffer(auctions, 5, 40), nil)
end)

test("shopping plan: mats to buy, crafts to do, bags used first", function()
	local SH = ns.Shopping
	local prices = { [2589] = 100, [2320] = 50 }
	local recipes = { [2996] = "1:1|2589*2" }
	local priceOf = function(id) return prices[id] end
	local recipeOf = function(id) return recipes[id] end
	local bags = { [2589] = 4 }
	local ownedOf = function(id) return bags[id] or 0 end

	-- 3 crafts of a bag (4238) = 3 bolts + 1 thread each; a bolt = 2 cloth
	local buy, steps = SH.Plan("2:2|2996*3,2320*1", 3, priceOf, recipeOf, ownedOf, 4238)
	local byId = {}
	for _, m in ipairs(buy) do byId[m.id] = m end
	eq(byId[2589].need, 18)   -- 9 bolts x 2 cloth
	eq(byId[2589].have, 4)
	eq(byId[2320].need, 3)
	eq(byId[2996], nil, "bolts are crafted, not bought")
	eq(#steps, 2)
	eq(steps[1].id, 2996); eq(steps[1].crafts, 9); eq(steps[1].depth, 1)
	eq(steps[2].id, 4238); eq(steps[2].crafts, 3); eq(steps[2].depth, 0, "the recipe itself last")

	-- bolts in the bags mean fewer crafts and less cloth
	bags[2996] = 4
	buy, steps = SH.Plan("2:2|2996*3,2320*1", 3, priceOf, recipeOf, ownedOf, 4238)
	byId = {}
	for _, m in ipairs(buy) do byId[m.id] = m end
	eq(steps[1].crafts, 5); eq(steps[1].have, 4)
	eq(byId[2589].need, 10)

	-- a bolt cheaper on the AH than its cloth is bought instead
	prices[2996] = 150
	buy, steps = SH.Plan("2:2|2996*3,2320*1", 3, priceOf, recipeOf, ownedOf, 4238)
	byId = {}
	for _, m in ipairs(buy) do byId[m.id] = m end
	eq(byId[2996].need, 9); eq(byId[2996].have, 4)
	eq(byId[2589], nil)
	eq(#steps, 1)

	-- a recipe making 2 per craft needs half the crafts
	prices[2996] = nil
	recipes[2996] = "2:2|2589*2"
	bags = {}
	buy, steps = SH.Plan("1:1|2996*3", 1, priceOf, recipeOf, ownedOf, 4238)
	eq(steps[1].crafts, 2); eq(steps[1].makes, 2)
	eq(buy[1].need, 4)
end)

test("shopping finds mats for the auction house's Buy Now and counts what you buy", function()
	local SH = ns.Shopping
	local me = CR:CharTable()
	me[197] = { name = "Tailoring", r = { [5000] = "1:1|2589*20,2592*2" } }
	local items = ns.Pricing:Realm().items
	items["2589"] = { m = 100, t = time() }
	-- cheaper in total and per unit: listed second. Its cap comes from yesterday's 50.
	items["2592"] = { m = 50, t = time(), h = { [ns.Pricing.DayIndex(time()) - 1] = "50:50:1" } }
	GetItemCount = function(id) return id == 2589 and 5 or 0 end
	C_AuctionHouse = {
		HasFullCommoditySearchResults = function() return true end,
		GetNumCommoditySearchResults = function() return 2 end,
		GetCommoditySearchResultInfo = function(_, i)
			if i == 1 then return { unitPrice = 100, quantity = 10 } end
			return { unitPrice = 130, quantity = 5 }   -- over the 120 cap (market stays 100)
		end,
	}
	local box = CreateFrame("EditBox")
	AuctionHouseFrame = { SearchBar = { SearchBox = box } }
	_FIRE("AUCTION_HOUSE_SHOW")

	truthy(SH:Start(5000, 1), "list made")
	local cloth = SH.list.mats[1]
	eq(cloth.id, 2589); eq(cloth.need, 20)
	eq(SH.Remaining(cloth), 15, "5 in bags")
	eq(SH.current, cloth)
	eq(SH:ButtonText(), "Find " .. ns.Pricing.ItemName(2589))

	SH:Find()
	eq(box:GetText(), ns.Pricing.ItemName(2589), "name in the search box")

	-- the listings the auction house shows: only those under the cap count
	_FIRE("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
	eq(SH.offer.qty, 10); eq(SH.offer.total, 1000)
	truthy(SH.message:find("quantity to 10", 1, true), "says how many")
	truthy(SH.message:find("Only 10 of 15", 1, true), "says the rest is over the cap")

	-- the quote is over the cap: a warning before you confirm
	_FIRE("COMMODITY_PRICE_UPDATED", 400, 4000)
	truthy(SH.message:find("over your cap", 1, true), "warns")

	-- a purchase through the auction house's own buttons counts once it succeeds
	SH.OnConfirmCommodities(2589, 10)
	eq(SH.Bought(2589), 0, "not before the answer")
	_FIRE("COMMODITY_PURCHASE_SUCCEEDED")
	eq(SH.Bought(2589), 10)
	eq(SH.Remaining(cloth), 5)
	eq(SH.current, cloth, "still 5 to buy")
	_FIRE("COMMODITY_PURCHASE_SUCCEEDED")
	eq(SH.Bought(2589), 10, "one answer, one count")

	-- a failed purchase does not count
	SH.OnConfirmCommodities(2589, 5)
	_FIRE("COMMODITY_PURCHASE_FAILED")
	_FIRE("COMMODITY_PURCHASE_SUCCEEDED")
	eq(SH.Bought(2589), 10)

	-- something not on the list does not count
	SH.OnConfirmCommodities(9999, 3)
	_FIRE("COMMODITY_PURCHASE_SUCCEEDED")
	eq(SH.Bought(9999), 0)

	-- the rest bought: on to the next mat
	SH.OnConfirmCommodities(2589, 5)
	_FIRE("COMMODITY_PURCHASE_SUCCEEDED")
	eq(SH.current.id, 2592, "next mat")

	-- skip goes on to the craft step, and round to the skipped mat
	SH:Skip()
	eq(SH.current.kind, "craft"); eq(SH.current.id, 5000)
	eq(SH:ButtonText(), "Craft " .. ns.Pricing.ItemName(5000) .. " (1x)")
	SH:Skip()
	eq(SH.current.id, 2592, "back to the skipped mat")

	-- more crafts: what was bought and the first bag count still hold
	GetItemCount = function(id) return id == 2589 and 15 or 0 end   -- mail collected
	SH:SetCrafts(2)
	eq(SH.list.mats[1].need, 40)
	eq(SH.list.mats[1].have, 5)
	eq(SH.Remaining(SH.list.mats[1]), 20)

	-- nothing under the cap
	SH:Find(SH.list.mats[2])
	C_AuctionHouse.GetNumCommoditySearchResults = function() return 1 end
	C_AuctionHouse.GetCommoditySearchResultInfo = function() return { unitPrice = 900, quantity = 5 } end
	_FIRE("COMMODITY_SEARCH_RESULTS_UPDATED", SH.current.id)
	eq(SH.offer, nil)
	truthy(SH.message:find("Nothing at or under your cap", 1, true), "says why")

	-- not enough gold
	GetMoney = function() return 50 end
	C_AuctionHouse.GetCommoditySearchResultInfo = function() return { unitPrice = 100, quantity = 50 } end
	_FIRE("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)   -- not the current mat: ignored
	SH:Find(SH.list.mats[1])
	_FIRE("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
	truthy(SH.message:find("Not enough money", 1, true), "money message")
	GetMoney = nil

	-- the auction house refusing
	Enum.AuctionHouseError = { NotEnoughMoney = 4 }
	_FIRE("AUCTION_HOUSE_SHOW_ERROR", 4)
	eq(SH.message, "The auction house refused: Not enough money. Nothing was bought.")
	Enum.AuctionHouseError = nil

	SH:Clear()
	_FIRE("AUCTION_HOUSE_CLOSED")
	C_AuctionHouse, GetItemCount, AuctionHouseFrame = nil, nil, nil
	me[197] = nil
	items["2589"], items["2592"] = nil, nil
end)

test("undercut: compare your price with other listings", function()
	local U = ns.Undercut
	-- strictly cheaper by someone else
	local mine, other, atMine = U.Compare({ { 90, 5 }, { 100, 10, true } })
	eq(mine, 100); eq(other, 90); eq(atMine, 0)
	eq(U.StatusFor(mine, other, atMine, 0), "undercut")
	-- others at your price: counted
	mine, other, atMine = U.Compare({ { 100, 5 }, { 100, 10, true }, { 100, 2 }, { 120, 1 } })
	eq(mine, 100); eq(other, 100); eq(atMine, 7)
	-- you are the cheapest
	mine, other, atMine = U.Compare({ { 100, 10, true }, { 120, 1 } })
	eq(U.StatusFor(mine, other, atMine, 0), "lowest"); eq(other, 120)
	-- no own rows: the saved price counts, and a listing at it may be yours
	mine, other, atMine = U.Compare({ { 100, 3 } }, 100)
	eq(atMine, nil)
	eq(U.StatusFor(mine, other, atMine, nil), "lowest")
	eq(U.StatusFor(U.Compare({ { 99, 3 } }, 100)), "undercut")
	-- you list none
	eq(U.Compare({ { 99, 3 } }), nil)

	-- same price: before you (no more than the baseline) or after you (more)
	eq(U.StatusFor(100, 100, 5, 5), "matched")
	eq(U.StatusFor(100, 100, 3, 3), "matched", "some sold")
	eq(U.StatusFor(100, 100, 8, 5), "undercut", "someone listed after you")
	eq(U.StatusFor(100, 100, 5, nil), "matched", "first comparison")
end)

test("undercut: price per unit of your own auctions", function()
	local U = ns.Undercut
	eq(U.OwnedUnit(9500, 26, "commodity"), 9500)
	eq(U.OwnedUnit(1000, 2, "item"), 500)
	eq(U.OwnedUnit(9500, 26, nil), 9500, "not loaded yet: a stack is a commodity")
	eq(U.OwnedUnit(14500, 1, nil), 14500)
	-- the market value tells the two readings apart
	eq(U.OwnedUnit(9500, 26, "item", 9500), 9500)
	eq(U.OwnedUnit(9500, 26, "commodity", 365), 365)
end)

test("undercut: same price counts only when listed after you", function()
	local U = ns.Undercut
	local mine = U:Mine()
	for k in pairs(mine) do mine[k] = nil end
	local search = { { 200, 4 }, { 200, 2, true }, { 300, 1 } }
	C_AuctionHouse = {
		HasFullCommoditySearchResults = function() return true end,
		GetNumCommoditySearchResults = function() return #search end,
		GetCommoditySearchResultInfo = function(_, i)
			local l = search[i]
			return { unitPrice = l[1], quantity = l[2], containsOwnerItem = l[3], numOwnerItems = l[3] and l[2] or 0 }
		end,
	}
	_PRINTED_COUNT = #_PRINTED
	_FIRE("COMMODITY_SEARCH_RESULTS_UPDATED", 2673)
	eq(mine["2673"].s, "matched", "4 units were there when you were first compared")
	eq(mine["2673"].b, 4)
	eq(#_PRINTED, _PRINTED_COUNT, "no alert")
	eq(ns.AuctionLabels.Text({ itemKey = { itemID = 2673 }, status = 0 }), PUI.Color("Tied, you're first", "gold"))

	-- someone lists 3 more at your price
	search[1] = { 200, 7 }
	_FIRE("COMMODITY_SEARCH_RESULTS_UPDATED", 2673)
	eq(mine["2673"].s, "undercut")
	truthy(U.SamePrice(mine["2673"]))
	truthy(#_PRINTED > _PRINTED_COUNT, "alert")
	eq(ns.AuctionLabels.Text({ itemKey = { itemID = 2673 }, status = 0 }), PUI.Color("Undercut (same price)", "bad"))

	-- a full scan that cannot tell your rows apart keeps that
	U.FromScan({ ["2673"] = { { 200, 9 }, { 300, 1 } } }, time())
	eq(mine["2673"].s, "undercut")
	-- a browse result at your price may be yours: ignored
	eq(mine["2673"].o, 200)

	C_AuctionHouse = nil
	for k in pairs(mine) do mine[k] = nil end
end)

test("undercut: every stale auction is searched, one at a time", function()
	local U = ns.Undercut
	local mine = U:Mine()
	for k in pairs(mine) do mine[k] = nil end
	Enum.AuctionStatus = { Active = 0, Sold = 1 }
	local owned = {
		{ itemKey = { itemID = 2673, itemLevel = 1 }, status = 0, quantity = 26, buyoutAmount = 9500 },
		{ itemKey = { itemID = 2870, itemLevel = 25 }, status = 0, quantity = 1, buyoutAmount = 14500 },
	}
	local searches = {}
	-- the market value agrees with 95s each (an earlier test recorded another price)
	ns.Pricing:Realm().items["2673"] = { m = 9500, t = time() }
	C_AuctionHouse = {
		GetNumOwnedAuctions = function() return #owned end,
		GetOwnedAuctionInfo = function(i) return owned[i] end,
		HasFullOwnedAuctionResults = function() return true end,
		IsThrottledMessageSystemReady = function() return true end,
		MakeItemKey = function(id, level) return { itemID = id, itemLevel = level } end,
		SendSearchQuery = function(itemKey) searches[#searches + 1] = itemKey end,
	}
	_FIRE("AUCTION_HOUSE_SHOW")
	_FIRE("OWNED_AUCTIONS_UPDATED")
	eq(mine["2673"].u, 9500, "the price per unit, not 9500 / 26")
	eq(#searches, 0, "spaced out")
	_RUN_TIMERS()
	eq(#searches, 2)
	eq(searches[1].itemID, 2673)
	eq(searches[2].itemID, 2870); eq(searches[2].itemLevel, 25, "gear is searched at its level")

	-- a fresh comparison is not searched again
	mine["2673"].ot, mine["2870"].ot = time(), time()
	_FIRE("OWNED_AUCTIONS_UPDATED")
	_RUN_TIMERS()
	eq(#searches, 2)

	-- a new price keeps what is known about the others
	mine["2673"].o, mine["2673"].s = 9000, "undercut"
	owned[1].buyoutAmount = 8900
	_FIRE("OWNED_AUCTIONS_UPDATED")
	eq(mine["2673"].s, "lowest"); eq(mine["2673"].o, 9000)

	-- closing the auction house stops the queue
	_FIRE("AUCTION_HOUSE_CLOSED")
	_RUN_TIMERS()
	eq(#searches, 2, "closing stops the queued check of the repriced one")

	ns.Pricing:Realm().items["2673"] = nil
	C_AuctionHouse = nil
	for k in pairs(mine) do mine[k] = nil end
end)

test("undercut: owned auctions are read, and a full scan reports what changed", function()
	local U = ns.Undercut
	local mine = U:Mine()
	for k in pairs(mine) do mine[k] = nil end
	Enum.AuctionStatus = { Active = 0, Sold = 1 }
	Enum.ItemCommodityStatus = { Unknown = 0, Item = 1, Commodity = 2 }
	local owned = {
		{ itemKey = { itemID = 2589 }, status = 0, quantity = 20, buyoutAmount = 100 },   -- commodity: per unit
		{ itemKey = { itemID = 2589 }, status = 0, quantity = 10, buyoutAmount = 120 },
		{ itemKey = { itemID = 4306 }, status = 0, quantity = 2, buyoutAmount = 1000 },   -- item: whole auction
		{ itemKey = { itemID = 2996 }, status = 1, quantity = 1, buyoutAmount = 500 },    -- sold
	}
	C_AuctionHouse = {
		GetNumOwnedAuctions = function() return #owned end,
		GetOwnedAuctionInfo = function(i) return owned[i] end,
		HasFullOwnedAuctionResults = function() return true end,
		GetItemCommodityStatus = function(id) return id == 2589 and 2 or 1 end,
	}
	_FIRE("AUCTION_HOUSE_SHOW")
	_FIRE("OWNED_AUCTIONS_UPDATED")
	eq(mine["2589"].u, 100); eq(mine["2589"].q, 30)
	eq(mine["4306"].u, 500)
	eq(mine["2996"], nil, "sold auctions are not listed")

	local alerts = U.FromScan({
		["2589"] = { { 95, 50 }, { 100, 20, true } },   -- undercut
		["4306"] = { { 500, 2, true }, { 700, 1 } },    -- lowest
		["9999"] = { { 50, 1 } },                       -- not yours
	}, time())
	eq(#alerts, 1); eq(alerts[1], "2589")
	eq(mine["2589"].s, "undercut"); eq(mine["2589"].o, 95)
	eq(mine["4306"].s, "lowest")
	eq(mine["9999"], nil)
	-- the same undercut again is not news
	eq(#U.FromScan({ ["2589"] = { { 95, 50 }, { 100, 20, true } } }, time()), 0)
	eq(U:List()[1].key, "2589", "undercut first")

	-- the Auctions tab label
	local AL = ns.AuctionLabels
	eq(AL.Text({ itemKey = { itemID = 2589 }, status = 0 }), PUI.Color("Undercut", "bad") .. " " .. PUI.Money(95))
	eq(AL.Text({ itemKey = { itemID = 4306 }, status = 0 }), PUI.Color("Lowest", "good"))
	eq(AL.Text({ itemKey = { itemID = 2589 }, status = 1 }), nil, "sold")

	_FIRE("AUCTION_HOUSE_CLOSED")
	C_AuctionHouse = nil
	for k in pairs(mine) do mine[k] = nil end
end)

test("a mail read before its name loaded is not recorded twice", function()
	local list = {}
	local early = { k = "s", item = "Breastplate", qty = 1, gross = 16000, cut = 800, who = "", t = 1000 }
	eq((L.Merge(list, { early })), 1)
	local later = { k = "s", item = "Breastplate", qty = 1, gross = 16000, cut = 800, who = "Krasnoff", t = 1001 }
	local added, filled = L.Merge(list, { later })
	eq(added, 0); eq(filled, 1)
	eq(#list, 1); eq(list[1].who, "Krasnoff")

	-- duplicates saved by the old version are cleaned up
	local old = {
		{ k = "s", item = "Breastplate", qty = 1, gross = 16000, who = "", t = 1000 },
		{ k = "s", item = "Breastplate", qty = 1, gross = 16000, who = "Krasnoff", t = 1001 },
		{ k = "b", item = "Tin Ore", qty = 4, gross = 756, who = "Oxide", t = 2000 },
		{ k = "b", item = "Tin Ore", qty = 4, gross = 756, who = "", t = 2000 },
		{ k = "b", item = "Iridescent Pearl", qty = 4, gross = 15929, t = 3000 },   -- no name ever: kept
	}
	eq(L.Dedupe(old), 2)
	eq(#old, 3)
	eq(old[1].who, "Krasnoff"); eq(old[2].who, "Oxide"); eq(old[3].item, "Iridescent Pearl")
end)

test("the log keeps the last lines and errors", function()
	ns.db.log = {}
	ns:Log("hello", 1, nil)
	truthy(ns.db.log[1]:find("hello 1 nil", 1, true), "logged")
	for i = 1, ns.LOG_LINES + 5 do ns:Log("line", i) end
	eq(#ns.db.log, ns.LOG_LINES)
	truthy(ns.db.log[#ns.db.log]:find("line " .. (ns.LOG_LINES + 5), 1, true), "newest last")
	ns.db.log = {}
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

-- API for other Kabobo addons

test("API: prices by itemID or link, and proceeds after cut and deposit", function()
	local api = ns:Peer("KaboboAuctions")
	truthy(api, "Kabobo's Auctions exposes an API")
	local items = ns.db.realms[ns.realmKey].items
	items["7777"] = { m = 1000, n = 900, t = 123 }
	items["7778"] = { n = 500, t = 124 }
	local price, seen = api.Price(7777)
	eq(price, 1000); eq(seen, 123)
	eq((api.Price("|cff1eff00|Hitem:7777::::::::|h[Thing]|h|r")), 1000)
	eq((api.Price(7778)), 500, "lowest buyout without a market value")
	eq(api.Price(7779), nil)
	eq(api.Proceeds(10000), 10000 - 500 - 100)
	eq(api.Proceeds(10000, 0), 10000 - 500)
	items["7777"], items["7778"] = nil, nil
end)

test("item tooltips get price lines through the shared hook", function()
	local items = ns.db.realms[ns.realmKey].items
	items["7777"] = { m = 1000, n = 900, t = time() }
	local lines = {}
	local tooltip = { AddDoubleLine = function(_, l, r) lines[l] = r end }
	_HOVER(tooltip, { id = 7777 })
	eq(lines["AH market"] ~= nil, true)
	lines = {}
	ns.db.settings.tooltip = false
	_HOVER(tooltip, { id = 7777 })
	eq(lines["AH market"], nil)
	ns.db.settings.tooltip = true
	items["7777"] = nil
end)

-- Disenchant value from Kabobo's Professions

test("craft summary adds disenchant value and profit", function()
	local r = CR.AddDisenchant({ yield = 1, cost = 1000 }, 2000, 0)
	eq(r.de, 2000 - 100)   -- 5% cut, no deposit
	eq(r.deMissing, 0)
	eq(r.deProfit, 900)
	r = CR.AddDisenchant({ yield = 2 }, 1000, 1)
	eq(r.de, 2000 - 100, "everything one craft makes")
	eq(r.deProfit, nil, "unknown mats cost")
	r = CR.AddDisenchant({ yield = 1, cost = 5 }, nil)
	eq(r.de, nil, "cannot be disenchanted")
end)

test("profession panel shows disenchant lines only with Kabobo's Professions", function()
	local function labels(summary)
		local out = {}
		for _, line in ipairs(ns.Lines.Craft(summary, false)) do out[line[1]] = line[2] end
		return out
	end
	local base = { cost = 1000, missing = 0, yield = 1, mats = {} }
	eq(labels(base)["Disenchants for"], nil)
	local l = labels({ cost = 1000, missing = 0, yield = 1, mats = {}, de = 1900, deMissing = 1, deProfit = 900 })
	eq(l["Disenchants for"], PUI.MoneyIcons(1900) .. "|cff808080 (1 mats unpriced)|r")
	eq(l["Profit if disenchanted"], PUI.SignedMoney(900, true))
	l = labels({ cost = 1000, missing = 0, yield = 1, mats = {}, de = 0, deMissing = 3 })
	eq(l["Disenchants for"], PUI.Color("no AH prices for its mats yet", "muted"))

	-- SummaryFor asks the peer, with AH prices
	local oldRead = CR.ReadSchematic
	CR.ReadSchematic = function() return 5001, "1:1|2589*2" end
	local asked
	KaboboAddons.KaboboProfessions = { DisenchantValue = function(item, price)
		asked = item
		return 2000, 0
	end }
	local s = ns.CraftPanel.SummaryFor(42)
	eq(asked, 5001)
	eq(s.de, 1900)
	KaboboAddons.KaboboProfessions = nil
	s = ns.CraftPanel.SummaryFor(42)
	eq(s.de, nil, "no peer, no disenchant lines")
	CR.ReadSchematic = oldRead
end)

-- Old prices

local Lines = ns.Lines

test("prices not seen for longer than staleDays are old", function()
	local P, DAY = ns.Pricing, 86400
	local now = 1000 * DAY
	eq(ns.db.settings.staleDays, 3, "default")
	eq(P.StaleAge(now - 2 * DAY, now), nil)
	eq(P.StaleAge(now - 5 * DAY, now), 5 * DAY)
	eq(P.StaleAge(nil, now), nil, "unknown")
	SlashCmdList.KABOBOAUCTIONS("stale 7")
	eq(ns.db.settings.staleDays, 7)
	eq(P.StaleAge(now - 5 * DAY, now), nil)
	SlashCmdList.KABOBOAUCTIONS("stale nonsense")
	eq(ns.db.settings.staleDays, 7, "a bad value changes nothing")
	truthy(_PRINTED[#_PRINTED]:find("after 7 days", 1, true), "prints the current setting")
	SlashCmdList.KABOBOAUCTIONS("stale 3")
	eq(ns.Lines.OldNote(now - 5 * DAY, now), PUI.Color(" (5d old)", "warn"))
	eq(ns.Lines.OldNote(now - DAY, now), "")
end)

test("tooltips flag old AH prices and old mat prices", function()
	local DAY = 86400
	local now = time()
	local items = ns.db.realms[ns.realmKey].items
	items["7777"] = { m = 1000, n = 900, t = now - 5 * DAY }
	local lines = Lines.Tooltip({ key = "7777", id = 7777, count = 1 }, { tooltipHistory = false }, now)
	eq(lines[1][2], PUI.MoneyIcons(1000) .. PUI.Color(" (5d old)", "warn"))
	items["7777"].t = now - 3600
	lines = Lines.Tooltip({ key = "7777", id = 7777, count = 1 }, { tooltipHistory = false }, now)
	eq(lines[1][2], PUI.MoneyIcons(1000) .. PUI.Color(" (1h ago)", "muted"))

	-- mats: the AH price carries when it was seen, vendor prices never get old
	items["2589"] = { m = 100, t = now - 6 * DAY }
	items["2320"] = { m = 50, t = now }
	ns.db.vendor[4340] = 350
	local price, source, seen = CR.MatPrice(2589)
	eq(price, 100); eq(source, nil); eq(seen, now - 6 * DAY)
	local cost, missing, _, mats = CR.CostPerCraft("1:1|2589*2,2320*1,4340*1", CR.MatPrice)
	eq(CR.OldestSeen(mats), now - 6 * DAY)
	eq(Lines.CostText(cost, missing, CR.OldestSeen(mats), now), PUI.MoneyIcons(600) .. PUI.Color(" (6d old)", "warn"))
	local out = Lines.AddMats({}, mats, nil, now)
	eq(out[1][2], PUI.MoneyIcons(350) .. PUI.Color(" vendor", "muted"))
	eq(out[2][2], PUI.MoneyIcons(200) .. PUI.Color(" (6d old)", "warn"))
	eq(out[3][2], PUI.MoneyIcons(50))
	items["7777"], items["2589"], items["2320"] = nil, nil, nil
	ns.db.vendor = {}
end)

test("profession panel flags old prices, including disenchanting", function()
	local DAY = 86400
	local now = time()
	local items = ns.db.realms[ns.realmKey].items
	items["2589"] = { m = 100, t = now - 4 * DAY }
	items["5001"] = { m = 3000, t = now - 10 * DAY }
	local oldRead = CR.ReadSchematic
	CR.ReadSchematic = function() return 5001, "1:1|2589*2" end
	local gotPrice
	KaboboAddons.KaboboProfessions = { DisenchantValue = function(item, price)
		local _, seen = price(2589)
		gotPrice = seen
		return 2000, 0, seen
	end }
	local s = ns.CraftPanel.SummaryFor(42)
	eq(s.matsSeen, now - 4 * DAY)
	eq(s.seen, now - 10 * DAY, "the crafted item's own AH price")
	eq(gotPrice, now - 4 * DAY, "Kabobo's Professions gets when each price was seen")
	eq(s.deSeen, now - 4 * DAY)

	local l = {}
	for _, line in ipairs(Lines.Craft(s, false, now)) do l[line[1]] = line[2] end
	eq(l["Mats cost"], PUI.MoneyIcons(200) .. PUI.Color(" (4d old)", "warn"))
	eq(l["Sells for (AH)"], PUI.MoneyIcons(3000) .. PUI.Color(" (10d old)", "warn"))
	eq(l["Disenchants for"], PUI.MoneyIcons(1900) .. PUI.Color(" (4d old)", "warn"))

	KaboboAddons.KaboboProfessions = nil
	CR.ReadSchematic = oldRead
	items["2589"], items["5001"] = nil, nil
end)

test("API: how old a price is", function()
	local api = ns:Peer("KaboboAuctions")
	eq(api.StaleAge(1000, 1000 + 86400), nil)
	eq(api.StaleAge(1000, 1000 + 4 * 86400), 4 * 86400)
	eq(api.StaleAge(nil), nil)
end)

test("sales: expected expiries come off what disappeared, at any gap", function()
	local Sales = ns.Sales
	-- the chance an auction expired: bands 1 Short < 30 min, 2 Medium, 3 Long 2-12 h, 4 Very long
	-- 12-48 h, 5 unknown 0-48 h
	eq(Sales.ExpiryChance(4, 0.25), 0); eq(Sales.ExpiryChance(3, 0.25), 0)
	near(Sales.ExpiryChance(1, 0.25), 0.5); eq(Sales.ExpiryChance(1, 1), 1)
	near(Sales.ExpiryChance(2, 1), 1 / 3)
	near(Sales.ExpiryChance(4, 24), 1 / 3); eq(Sales.ExpiryChance(4, 60), 1)
	near(Sales.ExpiryChance(5, 24), 0.5)

	-- { unit, qty, yours, seller, band }
	local before = Sales.Snapshot({ { 100, 5, nil, "A", 4 }, { 100, 5, nil, "A", 4 }, { 120, 1, nil, "B", 1 } })
	eq(before["100|5|A"][4], 2)
	local after = Sales.Snapshot({ { 100, 5, nil, "A", 4 }, { 90, 3, nil, "C", 3 } })
	-- 15 minutes: the very long stack cannot have expired (sold: 5); the short one half may have
	near(Sales.Sold(before, after, 0.25), 5.5)
	-- a day: a third of very long auctions run out by then, and the short one surely did
	near(Sales.Sold(before, after, 24), 5 * 2 / 3)
	-- never below zero, and nothing gone means nothing sold
	eq(Sales.Sold(after, after, 24), 0)
	eq(Sales.Sold(before, {}, 60), 0, "everything could have expired")
	-- a snapshot from the older version (plain counts) is taken as 0-48 h left
	near(Sales.Sold({ ["100|5|A"] = 2 }, after, 24), 2.5)
	-- no time left from the client: band 5
	eq(Sales.Snapshot({ { 100, 5, nil, "A" } })["100|5|A"][5], 1)

	-- rate over the observations of the last KEEP_DAYS days
	local now = 1000000
	eq(Sales.Rate({}, now), nil)
	near(Sales.Rate({ { now, 6, 12 }, { now - 3600, 2, 12 } }, now), 8)     -- 8 in 24 h
	local _, hours = Sales.Rate({ { now, 6, 12 }, { now - 3600, 2, 12 } }, now)
	eq(hours, 24)
	eq(Sales.Rate({ { now - 30 * 86400, 50, 24 } }, now), nil, "too old")
	eq(Sales.Text(nil), nil); eq(Sales.Text(8), "~8"); eq(Sales.Text(0.5), "~0.5"); eq(Sales.Text(12.4), "~12")
end)

test("sales: scans at irregular times all count", function()
	local Sales = ns.Sales
	local now = 1000000
	local sales, tracked = {}, { ["2996"] = true }
	local function scan(rows, t) return Sales.Record(sales, { ["2996"] = rows }, tracked, t) end
	local two = { { 100, 5, nil, "A", 4 }, { 100, 5, nil, "A", 4 } }
	local one = { { 100, 5, nil, "A", 4 } }
	eq(Sales.Record(sales, { ["2996"] = two, ["1"] = { { 1, 1 } } }, tracked, now), 0)
	eq(sales["1"], nil, "not tracked")
	eq(scan(two, now + 600), 0, "10 minutes: too soon, the first snapshot stays")
	eq(scan(one, now + 900), 1, "15 minutes")
	near(sales["2996"].g[1][2], 5); eq(sales["2996"].g[1][4], Sales.METHOD)
	eq(scan(one, now + 900 + 6 * 3600), 1, "6 hours, nothing gone")
	eq(sales["2996"].g[2][2], 0)
	eq(scan({}, now + 900 + 36 * 3600), 1, "30 hours: some of it expired")
	near(sales["2996"].g[3][2], 5 * (1 - (30 - 12) / 36))
	eq(scan(two, now + 4 * 86400), 0, "3 days: everything could have expired")
	eq(scan(one, now + 4 * 86400 + 1200), 1, "and the next one counts again")
	local rate = Sales.Rate(sales["2996"].g, now + 4 * 86400 + 1200)
	truthy(rate > 0, "a rate from all of them")

	-- observations from the older method are dropped
	sales["2996"].g[#sales["2996"].g + 1] = { now + 4 * 86400, 99, 1 }
	scan(one, now + 4 * 86400 + 2400)
	for _, o in ipairs(sales["2996"].g) do eq(o[4], Sales.METHOD) end
end)

test("sales: the crafts window says when to scan for Sold/day", function()
	local Sales = ns.Sales
	local sales = Sales:Table()
	for k in pairs(sales) do sales[k] = nil end
	local now = time()
	ns.db.account.lastReplicate = 0
	eq(Sales:Next(now), "first")
	sales["2996"] = { st = now - 300, snap = {}, g = {} }
	local what, wait = Sales:Next(now)
	eq(what, "again"); eq(wait, 600)
	sales["2996"].st = now - 3600
	what, wait = Sales:Next(now)
	eq(wait, 0)
	sales["2996"].g = { { now, 2, 1 } }
	eq(Sales:Next(now), nil, "has data")
	sales["2996"] = nil
end)

test("crafts can be ranked by profit per day", function()
	local prices = { [10] = 100 }
	local out = { [1] = 1000, [2] = 600, [3] = 2000 }
	local rates = { [1] = 1, [2] = 10 }
	local recipes = { [1] = "1:1|10*1", [2] = "1:1|10*1", [3] = "1:1|10*1" }
	local priceOf = function(id) return prices[id] end
	local outputPrice = function(id) return out[id] end
	local rateOf = function(id) return rates[id] end
	-- profits: 1 -> 1000-50-100-100 = 750, 2 -> 600-30-100-100 = 370, 3 -> 1700 (no rate)
	local rows = ns.Crafting.Rank(recipes, priceOf, nil, outputPrice, nil, rateOf)
	eq(rows[1].id, 3); eq(rows[2].id, 1); eq(rows[3].id, 2)
	eq(rows[2].rate, 1); eq(rows[2].perDay, 750)
	rows = ns.Crafting.Rank(recipes, priceOf, nil, outputPrice, nil, rateOf, "day")
	eq(rows[1].id, 2, "370 x 10 a day"); eq(rows[1].perDay, 3700)
	eq(rows[2].id, 1)
	eq(rows[3].id, 3, "no rate: after the ones with one")
end)

test("a crafted mat that is cheaper on the auction house is bought", function()
	local prices = { [2589] = 100, [2320] = 50, [2996] = 150 }
	local recipes = { [2996] = "1:1|2589*2" }
	local priceOf = function(id) return prices[id] end
	local recipeOf = function(id) return recipes[id] end
	-- bolt: 150 on the AH, 200 to craft
	eq((ns.Crafting.CostPerCraft("1:1|2996*3,2320*1", priceOf, recipeOf)), 500)
	prices[2996] = 250
	eq((ns.Crafting.CostPerCraft("1:1|2996*3,2320*1", priceOf, recipeOf)), 650)
end)

test("recipe list label: profit, unpriced mark and sales", function()
	local RP = ns.RecipeProfit
	eq(RP.Text(nil), nil)
	eq(RP.Text({ cost = 100 }), nil, "no AH price for the item")
	local text = RP.Text({ profit = 500, missing = 0 })
	truthy(text:find(PUI.Money(500), 1, true), "profit")
	text = RP.Text({ profit = 500, missing = 1 }, 4)
	truthy(text:find("*", 1, true), "unpriced mark")
	truthy(text:find("~4/d", 1, true), "sales")
end)

test("saved recipe IDs and profession names for craft steps", function()
	local me = ns.Crafting:CharTable()
	ns.Crafting:Store(186, "Mining", { [2840] = "1:1|2770*1" }, true, { [2840] = 2657 })
	local id, prof = ns.Crafting:CraftInfo(2840)
	eq(id, 2657); eq(prof, "Mining")
	-- an incomplete read adds IDs
	ns.Crafting:Store(186, "Mining", { [3576] = "1:1|2771*1" }, false, { [3576] = 3304 })
	eq((ns.Crafting:CraftInfo(3576)), 3304)
	eq((ns.Crafting:CraftInfo(2840)), 2657)
	eq(ns.Crafting:CraftInfo(1), nil)
	me[186] = nil
end)

test("shopping autofill: runs the search and fills quantities and counts, never buys", function()
	local SH = ns.Shopping
	local me = CR:CharTable()
	me[197] = { name = "Tailoring", r = { [5000] = "1:1|2589*6,2592*1" }, ids = { [5000] = 3915 } }
	local items = ns.Pricing:Realm().items
	items["2589"] = { m = 100, t = time() }
	local function never(name) return function() error(name .. " must never be called", 2) end end
	local searched, quantity = 0, nil
	local box = CreateFrame("EditBox")
	C_AuctionHouse = {
		StartCommoditiesPurchase = never("StartCommoditiesPurchase"),
		ConfirmCommoditiesPurchase = never("ConfirmCommoditiesPurchase"),
		PlaceBid = never("PlaceBid"),
		HasFullCommoditySearchResults = function() return true end,
		GetNumCommoditySearchResults = function() return 1 end,
		GetCommoditySearchResultInfo = function() return { unitPrice = 100, quantity = 4 } end,
	}
	local opened, count
	C_TradeSkillUI = { CraftRecipe = never("CraftRecipe"), OpenRecipe = function(id) opened = id end }
	AuctionHouseFrame = {
		SearchBar = { SearchBox = box, StartSearch = function() searched = searched + 1 end },
		CommoditiesBuyFrame = { BuyDisplay = {
			GetItemID = function() return 2589 end,
			SetQuantitySelected = function(_, n) quantity = n end,
		} },
	}
	ProfessionsFrame = { CraftingPage = { CreateMultipleInputBox = { SetValue = function(_, n) count = n end } } }
	ns.db.settings.autoFill = true
	_FIRE("AUCTION_HOUSE_SHOW")

	truthy(SH:Start(5000, 1))
	eq(SH.current.id, 2589)
	local openedItem
	AuctionHouseFrame.SelectBrowseResult = function(_, r) openedItem = r.itemKey.itemID end
	C_AuctionHouse.GetBrowseResults = function()
		return { { itemKey = { itemID = 2590 } }, { itemKey = { itemID = 2589 } } }
	end
	SH:Find()
	eq(box:GetText(), ns.Pricing.ItemName(2589)); eq(searched, 1, "the search runs")
	_FIRE("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	_RUN_TIMERS()
	eq(openedItem, 2589, "the item opens from the results")
	openedItem = nil
	_FIRE("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	_RUN_TIMERS()
	eq(openedItem, nil, "only once per Find")

	-- clicking the item in the results fills the quantity still to buy
	SH.OnBuyFrameItem(2589)
	eq(quantity, 6)
	quantity = nil
	SH.OnBuyFrameItem(9999)
	eq(quantity, nil, "not for another item")
	-- the listings under the cap lower it
	_FIRE("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
	eq(quantity, 4)
	truthy(SH.message:find("Quantity set to 4", 1, true), "says so")

	-- a craft step selects its recipe and fills the count
	local step = SH.list.steps[#SH.list.steps]
	eq(step.recipeID, 3915)
	SH:Find(step)
	eq(opened, 3915)
	SH.OnRecipeShown(3915)
	eq(count, 1)
	count = nil
	SH.OnRecipeShown(1234)
	eq(count, nil, "not for another recipe")

	-- the game blocking something right after: autofill turns itself off
	_FIRE("ADDON_ACTION_BLOCKED", "KaboboAuctions", "StartCommoditiesPurchase()")
	eq(ns.db.settings.autoFill, false)
	SH:Find(SH.list.mats[1])
	eq(searched, 1, "no more searches")
	SH.OnBuyFrameItem(2589)
	eq(quantity, 4, "no more filling")

	ns.db.settings.autoFill = true
	SH:Clear()
	_FIRE("AUCTION_HOUSE_CLOSED")
	C_AuctionHouse, C_TradeSkillUI, AuctionHouseFrame, ProfessionsFrame = nil, nil, nil, nil
	me[197] = nil
	items["2589"] = nil
end)
