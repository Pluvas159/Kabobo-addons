-- Pluvas' Auctions: tests for the parts that do not need the game client.
-- test/eq/near come from tests/lib/harness.lua; WoW stand-ins from tests/lib/mocks.lua.
local ns = _NS
local P, L = ns.Pricing, ns.Ledger

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

test("average sale per unit", function()
	local avg, qty = L.AverageSale({ sale(1, 1000), sale(2, 3000) }, "Linen Cloth")
	eq(avg, 100); eq(qty, 40)
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
	local items = ns:RealmData().items
	eq(items["2589"].n, 100)
	eq(items["2589"].q, 30)
	eq(items["15210:1180"].m, 50000)
	eq(items["4306"], nil)
	-- cooldown now blocks another scan
	ns.Scanner:FullScan()
	eq(ns.Scanner.state, "idle")
	assert(ns.Scanner:CooldownRemaining() > 0)
end)

test("money formatting", function()
	eq(ns.Money(0), "0|cffeda55fc|r")
	eq(ns.Money(123456), "12|cffffd700g|r 34|cffc7c7cfs|r 56|cffeda55fc|r")
	eq(ns.Money(-10000), "-1|cffffd700g|r")
	eq(ns.Money(12345670000), "1,234,567|cffffd700g|r")
end)
