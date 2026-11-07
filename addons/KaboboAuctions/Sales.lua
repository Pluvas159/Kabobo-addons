-- Kabobo's Auctions: how fast items you can craft leave the auction house, and how many you sold.
--
-- The game does not tell addons what other players buy. So after each full scan, the listings of
-- every item this account can craft are compared with the previous full scan: auctions (same
-- price, size and seller) that were there before and are gone now left the auction house. That
-- counts sales, but also auctions that expired or were cancelled, so it reads high; it is an
-- estimate ("~4/day"). Only scans 1 to 36 hours apart are compared: closer ones see too little,
-- further ones mostly see auctions expire.
--
-- Your own sales are exact: they come from the ledger (auction mail).
--
-- Saved layout: db.realms[realmKey].sales[itemKey] = {
--   snap = { ["unit|qty|seller"] = auctions } from the last full scan, st = time() of it,
--   g = { { time, units gone, hours between the scans }, ... } (the last KEEP_DAYS days) }
local _, ns = ...
local Sales = ns:NewModule("Sales")
local P = ns.Pricing

local DAY = 86400
Sales.MIN_HOURS = 1
Sales.MAX_HOURS = 36
Sales.KEEP_DAYS = 14

-- Pure logic ----------------------------------------------------------------------

-- Full scan rows of one item ({ unit, qty, own, seller }) -> { ["unit|qty|seller"] = count }.
function Sales.Snapshot(listings)
	local snap = {}
	for _, l in ipairs(listings or {}) do
		local sig = math.floor(l[1] + 0.5) .. "|" .. math.floor(l[2]) .. "|" .. tostring(l[4] or "")
		snap[sig] = (snap[sig] or 0) + 1
	end
	return snap
end

-- Units in `old` that are not in `new`.
function Sales.Gone(old, new)
	local gone = 0
	for sig, n in pairs(old or {}) do
		local missing = n - ((new and new[sig]) or 0)
		if missing > 0 then gone = gone + missing * (tonumber(sig:match("^[^|]*|(%d+)|")) or 1) end
	end
	return gone
end

-- Units per day from observations { { time, gone, hours }, ... } of the last KEEP_DAYS days,
-- or nil without any.
function Sales.Rate(obs, now)
	local gone, hours = 0, 0
	for _, o in ipairs(obs or {}) do
		if o[1] >= now - Sales.KEEP_DAYS * DAY then
			gone, hours = gone + o[2], hours + o[3]
		end
	end
	if hours <= 0 then return nil end
	return gone / hours * 24
end

-- "~4", "~0.5", "~0"; nil for nil.
function Sales.Text(rate)
	if not rate then return nil end
	if rate >= 10 then return "~" .. math.floor(rate + 0.5) end
	if rate >= 0.05 then return "~" .. string.format("%.1f", rate):gsub("%.0$", "") end
	return "~0"
end

-- Records one full scan for the tracked item keys. sales: the saved table; grouped: Scanner's
-- { [itemKey] = rows }; tracked: { [itemKey] = true }. Returns the number of items compared.
function Sales.Record(sales, grouped, tracked, now)
	local compared = 0
	for key in pairs(tracked) do
		local snap = Sales.Snapshot(grouped[key])
		local e = sales[key]
		if not e then
			e = { g = {} }
			sales[key] = e
		end
		e.g = e.g or {}
		if e.snap and e.st then
			local hours = (now - e.st) / 3600
			if hours >= Sales.MIN_HOURS and hours <= Sales.MAX_HOURS then
				e.g[#e.g + 1] = { now, Sales.Gone(e.snap, snap), hours }
				compared = compared + 1
			end
		end
		-- A scan too soon after the last one keeps the older snapshot, so the next scan that is
		-- far enough apart still has something to compare with.
		if not e.st or (now - e.st) / 3600 >= Sales.MIN_HOURS then
			e.snap, e.st = snap, now
		end
		local keep = {}
		for _, o in ipairs(e.g) do
			if o[1] >= now - Sales.KEEP_DAYS * DAY then keep[#keep + 1] = o end
		end
		e.g = keep
	end
	return compared
end

-- Saved data ----------------------------------------------------------------------

-- Output items of every recipe saved on this realm, by any of your characters.
function Sales.Tracked()
	local tracked = {}
	local realm = ns.db.crafts[ns.realmKey]
	for _, char in pairs(realm or {}) do
		for _, prof in pairs(char) do
			for id in pairs(prof.r or {}) do tracked[tostring(id)] = true end
		end
	end
	return tracked
end

function Sales:Table()
	local realm = P:Realm()
	if not realm then return nil end
	realm.sales = realm.sales or {}
	return realm.sales
end

-- Estimated units per day that leave the auction house, or nil before two scans compared.
function Sales:RateOf(itemID)
	local sales = Sales:Table()
	local e = sales and sales[tostring(itemID)]
	return e and Sales.Rate(e.g, time()) or nil
end

-- Units you sold in the last `days` days (from the ledger), by item name.
function Sales:YouSold(itemID, days)
	local name = P.ItemName(itemID)
	if not name then return 0 end
	local since, qty = time() - (days or 30) * DAY, 0
	for _, e in ipairs(ns.Ledger:Transactions() or {}) do
		if e.k == "s" and e.item == name and e.t >= since then qty = qty + e.qty end
	end
	return qty
end

ns:On("FullScanListings", function(grouped)
	local sales = Sales:Table()
	if not sales then return end
	local compared = Sales.Record(sales, grouped, Sales.Tracked(), time())
	ns:Debug("sales: compared", compared, "craftable items with the last full scan")
end)
