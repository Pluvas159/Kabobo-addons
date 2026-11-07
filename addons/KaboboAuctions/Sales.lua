-- Kabobo's Auctions: how many of the items you can craft sell per day, and how many you sold.
--
-- The game does not tell addons what other players buy. So after each full scan, the listings of
-- every item this account can craft are compared with the previous full scan, however long ago it
-- was (15 minutes to 48 hours): auctions (same price, size and seller) that were there before and
-- are gone now either sold (or were cancelled) or expired. Each auction's time-left band tells
-- them apart: one that had more time left than the gap cannot have expired, and for one that
-- could have, the chance it did is the part of its band below the gap (time left taken as even
-- across the band). The expected expiries are taken off what disappeared; the rest sold.
--   sold per day = all units sold / all hours compared, over the last KEEP_DAYS days
-- So every scan adds to it, whatever its gap, and it settles as scans come in. It is an estimate
-- ("~4"): auctions listed and sold between two scans are never seen (long gaps undercount fast
-- sellers), and cancels look like sales.
--
-- Your own sales are exact: they come from the ledger (auction mail).
--
-- Saved layout: db.realms[realmKey].sales[itemKey] = {
--   snap = { ["unit|qty|seller"] = { auctions per band 1..5 } } from the last full scan (a plain
--   count from older versions = band 5), st = time() of it,
--   g = { { time, units sold, hours between the scans, 2 }, ... } (the last KEEP_DAYS days; the
--   2 marks this method, older observations are dropped) }
local _, ns = ...
local Sales = ns:NewModule("Sales")
local P = ns.Pricing

local DAY = 86400
Sales.MIN_HOURS = 0.25   -- the server's full scan cooldown
Sales.MAX_HOURS = 48     -- the longest auction: past it, everything could have expired
Sales.KEEP_DAYS = 14
Sales.SOLID_HOURS = 6    -- below this many hours compared, the estimate is shown as thin
Sales.METHOD = 2

-- Time-left bands (Enum.AuctionHouseTimeLeftBand + 1) as hours left { from, to }. Band 5 is
-- "unknown": anything up to the longest auction.
Sales.BANDS = { { 0, 0.5 }, { 0.5, 2 }, { 2, 12 }, { 12, 48 }, { 0, 48 } }
Sales.UNKNOWN = 5

-- Pure logic ----------------------------------------------------------------------

-- Full scan rows of one item ({ unit, qty, own, seller, band }) ->
-- { ["unit|qty|seller"] = { auctions in band 1, ..., band 5 } }.
function Sales.Snapshot(listings)
	local snap = {}
	for _, l in ipairs(listings or {}) do
		local sig = math.floor(l[1] + 0.5) .. "|" .. math.floor(l[2]) .. "|" .. tostring(l[4] or "")
		local bands = snap[sig]
		if not bands then
			bands = { 0, 0, 0, 0, 0 }
			snap[sig] = bands
		end
		local b = Sales.BANDS[l[5] or 0] and l[5] or Sales.UNKNOWN
		bands[b] = bands[b] + 1
	end
	return snap
end

-- The chance an auction in `band` expired within `gap` hours.
function Sales.ExpiryChance(band, gap)
	local r = Sales.BANDS[band] or Sales.BANDS[Sales.UNKNOWN]
	if gap <= r[1] then return 0 end
	if gap >= r[2] then return 1 end
	return (gap - r[1]) / (r[2] - r[1])
end

-- A snapshot entry as band counts (older versions saved a plain count).
local function bandsOf(v)
	if type(v) == "table" then return v end
	if type(v) == "number" then return { 0, 0, 0, 0, v } end
	return { 0, 0, 0, 0, 0 }
end

local function total(bands)
	local n = 0
	for i = 1, #bands do n = n + bands[i] end
	return n
end

-- Units estimated sold between two snapshots `gap` hours apart: of each group of identical
-- auctions, how many are gone, minus how many of those were expected to expire. The auctions
-- most likely to expire are taken to be the ones gone, so the estimate errs low.
function Sales.Sold(old, new, gap)
	local sold = 0
	for sig, v in pairs(old or {}) do
		local bands = bandsOf(v)
		local gone = total(bands) - total(bandsOf(new and new[sig]))
		if gone > 0 then
			local chances = {}
			for b = 1, #bands do
				local p = Sales.ExpiryChance(b, gap)
				for _ = 1, bands[b] do chances[#chances + 1] = p end
			end
			table.sort(chances, function(a, c) return a > c end)
			local expired = 0
			for i = 1, gone do expired = expired + (chances[i] or 1) end
			local qty = tonumber(sig:match("^[^|]*|(%d+)|")) or 1
			sold = sold + (gone - expired) * qty
		end
	end
	return sold
end

-- Units per day from observations { { time, sold, hours }, ... } of the last KEEP_DAYS days,
-- or nil without any; and the hours compared.
function Sales.Rate(obs, now)
	local sold, hours = 0, 0
	for _, o in ipairs(obs or {}) do
		if o[1] >= now - Sales.KEEP_DAYS * DAY then
			sold, hours = sold + o[2], hours + o[3]
		end
	end
	if hours <= 0 then return nil, 0 end
	return sold / hours * 24, hours
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
				e.g[#e.g + 1] = { now, Sales.Sold(e.snap, snap, hours), hours, Sales.METHOD }
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
			if o[4] == Sales.METHOD and o[1] >= now - Sales.KEEP_DAYS * DAY then keep[#keep + 1] = o end
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

-- Estimated units sold per day, or nil before two scans were compared; and whether the estimate
-- is solid (SOLID_HOURS of scans compared).
function Sales:RateOf(itemID)
	local sales = Sales:Table()
	local e = sales and sales[tostring(itemID)]
	if not e then return nil, false end
	local rate, hours = Sales.Rate(e.g, time())
	return rate, hours >= Sales.SOLID_HOURS
end

-- "~4" for a rate, muted while it is thin; nil for nil.
function Sales.Label(rate, solid)
	local text = Sales.Text(rate)
	if text and not solid then return ns.KaboboUI.Color(text, "muted") end
	return text
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

-- What to do before Gone/day shows anything, or nil once it has data:
-- "first" (no full scan seen yet), or "again" with the seconds to wait (0: scan now).
function Sales:Next(now)
	local sales = Sales:Table()
	if not sales then return nil end
	local newest
	for _, e in pairs(sales) do
		if e.g and #e.g > 0 then return nil end
		if e.st and (not newest or e.st > newest) then newest = e.st end
	end
	if not newest then return "first" end
	local wait = math.max(Sales.MIN_HOURS * 3600 - (now - newest), ns.Scanner:CooldownRemaining(), 0)
	return "again", math.ceil(wait)
end

ns:On("FullScanListings", function(grouped)
	local sales = Sales:Table()
	if not sales then return end
	local compared = Sales.Record(sales, grouped, Sales.Tracked(), time())
	ns:Debug("sales: compared", compared, "craftable items with the last full scan")
end)
