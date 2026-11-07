-- Pluvas' Auctions: price statistics and the price database.
--
-- Item entry layout (kept short because it is saved for every item):
--   m  = market value (copper per unit) from the last full scan or full item search
--   mt = time() the market value was computed
--   n  = lowest unit buyout seen last time
--   q  = total quantity listed last time
--   t  = time() the item was last seen
--   h  = daily history: [dayIndex] = "avgMarket:dayMin:samples"
local _, ns = ...
local P = ns:NewModule("Pricing")

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local DAY = 86400
P.MARKET_SHARE = 0.30   -- market value looks at the cheapest 30% of listed units
P.OUTLIER_LOW = 0.5     -- ...and ignores units below 50% or above 150% of their median
P.OUTLIER_HIGH = 1.5

-- Item keys ---------------------------------------------------------------

-- "itemID" or "itemID:suffixID" for random-suffix items ("of the Bear").
function P.ItemKey(itemID, suffixID)
	if not itemID then return nil end
	suffixID = tonumber(suffixID)
	if suffixID and suffixID ~= 0 then
		return itemID .. ":" .. suffixID
	end
	return tostring(itemID)
end

-- item:itemID:enchant:gem1:gem2:gem3:gem4:suffixID:...
function P.ItemKeyFromLink(link)
	if type(link) ~= "string" then return nil end
	local itemString = link:match("item:([%-%d:]+)")
	if not itemString then return nil end
	local fields = ns.Split(itemString, ":")
	local itemID = tonumber(fields[1])
	if not itemID then return nil end
	return P.ItemKey(itemID, fields[7])
end

-- Statistics --------------------------------------------------------------

-- listings: array of { unitPrice, quantity }. Sorted in place.
-- Returns { min, market, qty, auctions } or nil when there is nothing to price.
function P.ComputeStats(listings)
	local n = #listings
	if n == 0 then return nil end
	table.sort(listings, function(a, b) return a[1] < b[1] end)

	local total = 0
	for i = 1, n do total = total + listings[i][2] end
	if total <= 0 then return nil end

	-- The cheapest share of all listed units.
	local cap = max(1, ceil(total * P.MARKET_SHARE))
	local subset, taken = {}, 0
	for i = 1, n do
		local take = min(listings[i][2], cap - taken)
		if take <= 0 then break end
		subset[#subset + 1] = { listings[i][1], take }
		taken = taken + take
	end

	-- Weighted median of that share.
	local half, acc, median = taken / 2, 0, subset[#subset][1]
	for i = 1, #subset do
		acc = acc + subset[i][2]
		if acc >= half then
			median = subset[i][1]
			break
		end
	end

	-- Mean of the units near the median, so one 1c or 9999g listing cannot skew it.
	local lo, hi = median * P.OUTLIER_LOW, median * P.OUTLIER_HIGH
	local sum, count = 0, 0
	for i = 1, #subset do
		local unit, qty = subset[i][1], subset[i][2]
		if unit >= lo and unit <= hi then
			sum = sum + unit * qty
			count = count + qty
		end
	end
	local market = count > 0 and floor(sum / count + 0.5) or median

	return { min = listings[1][1], market = market, qty = total, auctions = n }
end

-- Selling costs -------------------------------------------------------------

P.AH_CUT = 0.05          -- the auction house keeps 5% of every sale (confirmed from AH invoices)
-- Deposit per auction: a flat 1 silver on Forever, whatever the item or stack size
-- (confirmed in game by Pluvas, 2026-11-07).
P.DEPOSIT = 100

-- Item name from the item cache, or "item:<id>" while the client has not loaded it yet.
function P.ItemName(itemID)
	local name = ns.Try((C_Item and C_Item.GetItemInfo) or GetItemInfo, itemID)
	return name or ("item:" .. tostring(itemID))
end

-- Selling `count` units at `unitPrice`: returns gross, AH cut, and what is left after the cut
-- and the deposit.
function P.NetProceeds(unitPrice, count, deposit)
	local gross = unitPrice * (count or 1)
	local cut = floor(gross * P.AH_CUT + 0.5)
	return gross, cut, gross - cut - (deposit or 0)
end

-- History -----------------------------------------------------------------

function P.DayIndex(t)
	return floor(t / DAY)
end

local function parseDay(s)
	local m, lo, c = s:match("^(%d+):(%d+):(%d+)$")
	return tonumber(m), tonumber(lo), tonumber(c)
end
P.ParseDay = parseDay

local function addToHistory(entry, now, market, low)
	entry.h = entry.h or {}
	local day = P.DayIndex(now)
	local old = entry.h[day]
	if old then
		local m, lo, c = parseDay(old)
		if m then
			if market then
				m = floor((m * c + market) / (c + 1) + 0.5)
				c = c + 1
			end
			if low and low < lo then lo = low end
			entry.h[day] = m .. ":" .. lo .. ":" .. c
			return
		end
	end
	if market then
		entry.h[day] = market .. ":" .. (low or market) .. ":1"
	elseif low then
		-- No market value yet today: use the lowest price as a stand-in, but with 0 samples
		-- so the first real market value replaces it.
		entry.h[day] = low .. ":" .. low .. ":0"
	end
end

-- Record full statistics (from a full scan or a complete item/commodity search).
function P.Record(items, key, stats, now)
	local entry = items[key]
	if not entry then
		entry = {}
		items[key] = entry
	end
	entry.m = stats.market
	entry.mt = now
	entry.n = stats.min
	entry.q = stats.qty
	entry.t = now
	addToHistory(entry, now, stats.market, stats.min)
	return entry
end

-- Record only a lowest price (from browse results, where only the cheapest is known).
function P.RecordMin(items, key, minPrice, qty, now)
	local entry = items[key]
	if not entry then
		entry = {}
		items[key] = entry
	end
	entry.n = minPrice
	entry.q = qty or entry.q
	entry.t = now
	if not entry.m then entry.m = minPrice; entry.mt = now end
	addToHistory(entry, now, nil, minPrice)
	return entry
end

-- Average daily market value over the last `days` days (only days with real samples).
function P.HistoryAverage(entry, now, days)
	if not entry or not entry.h then return nil end
	local today = P.DayIndex(now)
	local sum, count = 0, 0
	for day, s in pairs(entry.h) do
		if day > today - days then
			local m, _, c = parseDay(s)
			if m and c and c > 0 then
				sum = sum + m
				count = count + 1
			end
		end
	end
	if count == 0 then return nil end
	return floor(sum / count + 0.5), count
end

-- Drop history days older than keepDays.
function P.Prune(items, now, keepDays)
	local cutoff = P.DayIndex(now) - keepDays
	for _, entry in pairs(items) do
		if entry.h then
			for day in pairs(entry.h) do
				if day <= cutoff then entry.h[day] = nil end
			end
		end
	end
end

-- Saved data ----------------------------------------------------------------

-- This realm/faction's price data, created on first use. Only call after login.
function P:Realm()
	local realm = ns.Ensure(ns.db.realms, ns.realmKey)
	realm.items = realm.items or {}
	realm.lastScan = realm.lastScan or 0
	return realm
end

-- Entry for an item key, or nil. Read-only, for tooltips and other hot paths.
function P:Get(key)
	if not key or not ns.realmKey then return nil end
	local realm = ns.db.realms[ns.realmKey]
	return realm and realm.items and realm.items[key]
end

-- Number of items with price data, and time() of the last full scan (0 = never).
function P:Summary()
	local realm = ns.realmKey and ns.db.realms[ns.realmKey]
	local count = 0
	if realm and realm.items then
		for _ in pairs(realm.items) do count = count + 1 end
	end
	return count, realm and realm.lastScan or 0
end

function P:Reset()
	ns.db.realms[ns.realmKey] = nil
	ns:Print("price data for " .. ns.realmKey .. " deleted.")
	ns:Send("PricesChanged")
end

function P:OnLogin()
	local now = time()
	for _, realm in pairs(ns.db.realms) do
		if realm.items then P.Prune(realm.items, now, ns.db.settings.historyDays) end
	end
end
