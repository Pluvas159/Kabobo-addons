-- Kabobo's Auctions: sales, purchases and gold tracking.
--
-- Sales and purchases are read from auction house invoice mail ("Auction successful", "Auction
-- won") whenever the mailbox is open. The same mail is seen many times, so each mail is matched
-- against what is already recorded before it is added. Sends LedgerChanged after each change.
--
-- Transaction layout (db.ledger[realmKey].tx, sorted by t):
--   k     = "s" (sold) or "b" (bought)
--   item  = item name (invoices carry no link)
--   qty   = stack size
--   gross = sale price or price paid (copper, whole stack)
--   cut   = auction house cut (sales only)
--   who   = buyer / seller name
--   t     = estimated time() the mail arrived
--   char  = character that received the mail
local _, ns = ...
local L = ns:NewModule("Ledger")

local DAY = 86400
L.MAIL_DAYS = 30          -- auction house mail is kept this many days
L.MATCH_WINDOW = 3600     -- seconds two copies of the same mail may differ by

-- Pure logic (unit tested) ------------------------------------------------

local function sameTx(a, b, window)
	return a.k == b.k
		and a.item == b.item
		and a.gross == b.gross
		and a.qty == b.qty
		and (a.who or "") == (b.who or "")
		and math.abs(a.t - b.t) <= window
end

local function byTime(a, b) return a.t < b.t end

-- Adds every transaction in `incoming` that is not already in `list` (sorted by t, and kept
-- sorted). Each existing entry can match only one incoming entry, so two identical sales (same
-- buyer, item, price and time) are both kept. Only entries near the incoming times are
-- compared, so the cost does not grow with the length of the history.
function L.Merge(list, incoming, window)
	window = window or L.MATCH_WINDOW
	if #incoming == 0 then return 0 end
	local oldest = math.huge
	for _, rec in ipairs(incoming) do
		if rec.t < oldest then oldest = rec.t end
	end
	oldest = oldest - window

	local n, used, added = #list, {}, 0
	for _, rec in ipairs(incoming) do
		local found = false
		for i = n, 1, -1 do
			local e = list[i]
			if e.t < oldest then break end
			if not used[e] and sameTx(e, rec, window) then
				used[e] = true
				found = true
				break
			end
		end
		if not found then
			list[#list + 1] = rec
			added = added + 1
		end
	end
	if added > 0 then table.sort(list, byTime) end
	return added
end

-- Totals for transactions at or after `since` (nil = all time).
function L.Summarize(list, since)
	local r = { sales = 0, cut = 0, bought = 0, soldCount = 0, boughtCount = 0 }
	for _, e in ipairs(list) do
		if not since or e.t >= since then
			if e.k == "s" then
				r.sales = r.sales + e.gross
				r.cut = r.cut + (e.cut or 0)
				r.soldCount = r.soldCount + 1
			elseif e.k == "b" then
				r.bought = r.bought + e.gross
				r.boughtCount = r.boughtCount + 1
			end
		end
	end
	r.netSales = r.sales - r.cut
	r.profit = r.netSales - r.bought
	return r
end

-- Per-item totals, sorted by net sales (highest first).
function L.TopItems(list, since)
	local byItem = {}
	for _, e in ipairs(list) do
		if not since or e.t >= since then
			local it = byItem[e.item]
			if not it then
				it = { item = e.item, sold = 0, soldQty = 0, net = 0, bought = 0, boughtQty = 0 }
				byItem[e.item] = it
			end
			if e.k == "s" then
				it.sold = it.sold + e.gross
				it.soldQty = it.soldQty + e.qty
				it.net = it.net + e.gross - (e.cut or 0)
			else
				it.bought = it.bought + e.gross
				it.boughtQty = it.boughtQty + e.qty
			end
		end
	end
	local out = {}
	for _, it in pairs(byItem) do
		it.profit = it.net - it.bought
		out[#out + 1] = it
	end
	table.sort(out, function(a, b)
		if a.net ~= b.net then return a.net > b.net end
		return a.item < b.item
	end)
	return out
end

-- Sales per item name: { [name] = { total = copper before the cut, qty = units } }.
function L.SalesByItem(list)
	local out = {}
	for _, e in ipairs(list) do
		if e.k == "s" then
			local s = out[e.item]
			if not s then
				s = { total = 0, qty = 0 }
				out[e.item] = s
			end
			s.total = s.total + e.gross
			s.qty = s.qty + e.qty
		end
	end
	return out
end

-- Saved data --------------------------------------------------------------

function L:Transactions()
	local realm = ns.Ensure(ns.db.ledger, ns.realmKey)
	realm.tx = realm.tx or {}
	return realm.tx
end

-- Tooltips ask for the average sale price on every hover, so it comes from an index that is
-- built once and dropped whenever the ledger changes.
local salesIndex

local function changed(txChanged)
	if txChanged then salesIndex = nil end
	ns:Send("LedgerChanged")
end

-- Average price per unit you sold an item for (before the AH cut), and the units sold.
function L:AverageSale(itemName)
	if not itemName or not ns.realmKey then return nil end
	salesIndex = salesIndex or L.SalesByItem(L:Transactions())
	local s = salesIndex[itemName]
	if not s or s.qty == 0 then return nil end
	return math.floor(s.total / s.qty + 0.5), s.qty
end

function L:Reset()
	ns.db.ledger[ns.realmKey] = nil
	ns:Print("ledger for " .. ns.realmKey .. " deleted.")
	changed(true)
end

-- Mail reading ------------------------------------------------------------

local function readInvoice(index, now)
	local _, _, _, _, _, _, daysLeft = GetInboxHeaderInfo(index)
	local invoiceType, itemName, playerName, bid, _, _, consignment, _, _, _, count = GetInboxInvoiceInfo(index)
	if (invoiceType ~= "seller" and invoiceType ~= "buyer") or not itemName or not bid then
		return nil
	end
	return {
		k = invoiceType == "seller" and "s" or "b",
		item = itemName,
		qty = (count and count > 0) and count or 1,
		gross = bid,
		cut = invoiceType == "seller" and (consignment or 0) or nil,
		who = playerName,
		t = math.floor(now - (L.MAIL_DAYS - (daysLeft or L.MAIL_DAYS)) * DAY),
		char = ns.charName,
	}
end

local function record(incoming)
	local added = L.Merge(L:Transactions(), incoming)
	if added > 0 then
		ns:Debug("ledger: " .. added .. " new auction mails recorded")
		changed(true)
	end
	return added
end

function L:ScanInbox()
	if not GetInboxInvoiceInfo then return end
	local now, incoming = time(), {}
	for i = 1, (GetInboxNumItems() or 0) do
		local rec = readInvoice(i, now)
		if rec then incoming[#incoming + 1] = rec end
	end
	record(incoming)
end

ns:On("MAIL_INBOX_UPDATE", function() L:ScanInbox() end)

-- Catch a mail right as its money or items are taken, in case the inbox was emptied before
-- MAIL_INBOX_UPDATE had a chance to fire.
local captureIndex = ns:Guard("Mail capture", function(index)
	if not index then return end
	local rec = readInvoice(index, time())
	if rec then record({ rec }) end
end)

function L:OnLogin()
	for _, fname in ipairs({ "TakeInboxMoney", "AutoLootMailItem", "TakeInboxItem" }) do
		if _G[fname] then hooksecurefunc(fname, captureIndex) end
	end
	L:UpdateGold()
end

-- Gold tracking -----------------------------------------------------------

function L:GoldTable()
	return ns.Ensure(ns.db.gold, ns.realmKey)
end

function L:UpdateGold()
	if not ns.realmKey then return end
	local me = ns.Ensure(L:GoldTable(), ns.charName)
	me.days = me.days or {}
	me.money = GetMoney()
	me.days[ns.DayStart()] = me.money
	-- Keep a year of daily balances.
	local cutoff = time() - 366 * DAY
	for day in pairs(me.days) do
		if day < cutoff then me.days[day] = nil end
	end
end

-- Gold of every character on this realm/faction, and the change since yesterday.
function L:GoldSummary()
	local today = ns.DayStart()
	local total, change = 0, 0
	for _, c in pairs(L:GoldTable()) do
		total = total + (c.money or 0)
		-- Balance at the end of the latest day before today, if any.
		local prevDay, prevMoney
		for day, m in pairs(c.days or {}) do
			if day < today and (not prevDay or day > prevDay) then
				prevDay, prevMoney = day, m
			end
		end
		if prevMoney then change = change + (c.money or 0) - prevMoney end
	end
	return total, change
end

ns:On("PLAYER_MONEY", function()
	L:UpdateGold()
	changed(false)
end)

function L:OnLogout()
	L:UpdateGold()
end
