-- Kabobo's Auctions: your auctions, and whether someone else now lists the item cheaper, or at
-- your price after you (at the same price, the auction listed later sells first).
--
-- Your auctions are read with C_AuctionHouse.QueryOwnedAuctions when the auction house opens and
-- after you post or cancel one. Every one whose comparison is missing or older than STALE is then
-- searched, one at a time (the check queue). They are also compared against every listing the
-- addon sees: full scans (Scanner sends FullScanListings), item and commodity searches (the Sell
-- tab searches the item you post, so a fresh post is checked right away) and browse results. A
-- change to undercut prints one chat line; a full scan prints one summary.
--
-- Same price: the AH does not say when an auction was listed. So the first comparison at your
-- price saves how many units others list at exactly that price (the baseline, b). More units
-- there later means someone listed after you: undercut. No more than the baseline: "matched",
-- listed before you. The baseline follows the lowest count seen, so units that sold and were
-- relisted still count, and starts again when you change your price.
--
-- Saved layout: db.mine[realmKey][charName][itemKey] = {
--   u = your cheapest unit price, q = quantity you list, t = time() read,
--   k = { itemID, itemLevel, itemSuffix, speciesID } to search it,
--   s = "undercut" | "matched" | "lowest" (nil until compared), o = cheapest other unit price,
--   n = units others list at your price, b = the baseline of n, ot = time() of the comparison }
-- Sends UndercutsChanged when the list or a status changes.
local _, ns = ...
local U = ns:NewModule("Undercut")
local P = ns.Pricing

U.KEEP = 48 * 3600   -- the longest auction; older entries are gone even if never refreshed
U.STALE = 300        -- a comparison older than this is checked again when the AH opens
U.CHECK_GAP = 2      -- seconds between the check queue's searches

local ah = ns:Session("AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED")

-- Pure logic ----------------------------------------------------------------------

-- listings: array of { unitPrice, quantity, own }. own marks your listings when the source
-- knows (searches, full scans). myUnit: your saved cheapest unit price; your own listings in
-- `listings` override it.
-- Returns your unit price (nil when you list none), the cheapest unit price of someone else (nil
-- when nobody else lists it), and how many units others list at exactly your price. That last
-- one is nil when your own rows are not marked: a listing at your price may then be yours.
function U.Compare(listings, myUnit)
	local ownMin, otherMin
	for i = 1, #listings do
		local l = listings[i]
		if l[3] then
			if not ownMin or l[1] < ownMin then ownMin = l[1] end
		elseif not otherMin or l[1] < otherMin then
			otherMin = l[1]
		end
	end
	local mine = ownMin or myUnit
	if not mine then return nil end
	local atMine
	if ownMin then
		atMine = 0
		for i = 1, #listings do
			local l = listings[i]
			if not l[3] and l[1] == mine then atMine = atMine + (l[2] or 0) end
		end
	end
	return mine, otherMin, atMine
end

-- The status for your price `mine`, the cheapest other price, the units others list at your
-- price (atMine, nil when unknown) and the baseline of that (see the top of the file).
function U.StatusFor(mine, other, atMine, baseline)
	if not mine then return nil end
	if other and other < mine then return "undercut" end
	if atMine and atMine > 0 then
		if baseline and atMine > baseline then return "undercut" end
		return "matched"
	end
	return "lowest"
end

-- Price per unit of an owned auction. A commodity's buyoutAmount is per unit, an item auction's
-- is for all of it. kind: "commodity", "item" or nil (the client has not loaded the item yet).
-- market: the item's market value, or nil. A stack's price can then be told apart: of the two
-- readings, the one nearer the market value wins; without one, unknown counts as a commodity
-- (stackable things are commodities on this AH; gear comes one at a time).
function U.OwnedUnit(buyout, qty, kind, market)
	qty = math.max(1, qty or 1)
	if qty == 1 then return buyout end
	local divided = math.floor(buyout / qty + 0.5)
	if market and market > 0 then
		local function off(x) return math.abs(math.log(math.max(x, 1) / market)) end
		return off(buyout) <= off(divided) and buyout or divided
	end
	if kind == "item" then return divided end
	return buyout
end

-- Key of an owned auction or search result: "itemID" or "itemID:suffix".
function U.KeyOf(itemKey, link)
	return (link and P.ItemKeyFromLink(link)) or (itemKey and P.ItemKey(itemKey.itemID, itemKey.itemSuffix))
end

local function itemName(key)
	return P.ItemName(tonumber(tostring(key):match("^(%d+)")))
end

-- The item's link for chat (shift-click it to search it in the auction house), or its name.
local function itemLink(key)
	local id = tonumber(tostring(key):match("^(%d+)"))
	local link = id and GetItemInfo and select(2, GetItemInfo(id))
	return link or itemName(key)
end

-- Saved data ----------------------------------------------------------------------

function U:Mine()
	return ns.Ensure(ns.db.mine, ns.realmKey, ns.charName)
end

-- Undercut at your price: someone listed at it after you.
function U.SamePrice(e)
	return e.s == "undercut" and e.o ~= nil and e.o == e.u
end

-- The status of an entry in words, and its color key: "Undercut", "Undercut (same price)",
-- "Tied, you're first", "Lowest"; nil before it was compared.
function U.StatusText(e)
	if U.SamePrice(e) then return "Undercut (same price)", "bad" end
	if e.s == "undercut" then return "Undercut", "bad" end
	if e.s == "matched" then return "Tied, you're first", "gold" end
	if e.s == "lowest" then return "Lowest", "good" end
	return nil
end

-- Your auctions as list items, undercut first: { key, entry }.
function U:List()
	local mine = U:Mine()
	local order = { undercut = 1, matched = 2, lowest = 3 }
	local list = {}
	for key, e in pairs(mine or {}) do list[#list + 1] = { key = key, e = e } end
	table.sort(list, function(a, b)
		local oa, ob = order[a.e.s] or 4, order[b.e.s] or 4
		if oa ~= ob then return oa < ob end
		return tostring(a.key) < tostring(b.key)
	end)
	return list
end

function U:Prune(now)
	local mine = U:Mine()
	if not mine then return end
	for key, e in pairs(mine) do
		if (e.t or 0) < now - U.KEEP then mine[key] = nil end
	end
end

-- Alerts --------------------------------------------------------------------------

local function alertLine(key, e)
	local Money = ns.KaboboUI.Money
	local same = U.SamePrice(e)
	local what = ns.KaboboUI.Color(same and "Undercut at your price" or "Undercut", "bad")
	return what .. ": " .. itemLink(key) .. (e.q and e.q > 1 and (" x" .. e.q) or "")
		.. "  yours " .. Money(e.u) .. ", "
		.. (same and "someone listed after you at " or "cheapest now ") .. Money(e.o)
end

local function sound()
	if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then ns.Try(PlaySound, SOUNDKIT.RAID_WARNING) end
end

-- Records a comparison for one item (see U.Compare for mine/other/atMine). Returns true when it
-- is newly undercut (or by a new price), which is worth an alert.
local function record(key, mine, other, atMine, now)
	local all = U:Mine()
	if not (all and mine) then return false end
	local e = all[key]
	if not e then
		e = { u = mine, t = now }
		all[key] = e
	end
	if e.u ~= mine then e.b = nil end   -- a new price: a new baseline
	if atMine then
		e.b = e.b and math.min(e.b, atMine) or atMine
		e.n = atMine
	end
	local status = U.StatusFor(mine, other, atMine, e.b)
	-- A source that does not mark your listings (atMine nil) cannot judge your own price: keep
	-- what a search that could judge it found.
	if not atMine and other == mine and e.u == mine and (e.s == "matched" or e.s == "undercut") then
		status = e.s
	end
	local news = status == "undercut" and (e.s ~= status or e.o ~= other or e.u ~= mine)
	e.u, e.s, e.o, e.ot = mine, status, other, now
	return news
end

-- One item seen in a search or the browse list.
local function check(key, listings)
	if not key then return end
	local all = U:Mine()
	local saved = all and all[key]
	local mine, other, atMine = U.Compare(listings, saved and saved.u)
	if not mine then return end
	ns:Debug("undercut: compared", key, "yours", mine, "other", other, "at yours", atMine)
	if record(key, mine, other, atMine, time()) and ns.db.settings.undercutAlerts then
		ns:Print(alertLine(key, all[key]))
		sound()
	end
	ns:Send("UndercutsChanged")
end

-- The check queue -----------------------------------------------------------------
--
-- Searches your items one at a time, CHECK_GAP seconds apart, only while the AH is open. The
-- search results come back as ordinary search events, compared above.

local queue, queued, pumpTimer = {}, {}, nil

local function stopQueue()
	if pumpTimer then pumpTimer:Cancel(); pumpTimer = nil end
	queue, queued = {}, {}
end

local function pump()
	pumpTimer = nil
	local AH = C_AuctionHouse
	if not (ah.open and AH and AH.SendSearchQuery and AH.MakeItemKey) then return stopQueue() end
	if #queue == 0 then return end
	if AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady() then
		pumpTimer = C_Timer.NewTimer(U.CHECK_GAP, ns:Guard("Undercut checks", pump))
		return
	end
	local key = table.remove(queue, 1)
	queued[key] = nil
	local e = U:Mine() and U:Mine()[key]
	local k = e and e.k
	if k and k[1] then
		ns:Debug("undercut: checking", key)
		local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
		ns.Try(AH.SendSearchQuery, AH.MakeItemKey(k[1], k[2] or 0, k[3] or 0, k[4]),
			{ { sortOrder = order, reverseSort = false } }, true)
	end
	if #queue > 0 then pumpTimer = C_Timer.NewTimer(U.CHECK_GAP, ns:Guard("Undercut checks", pump)) end
end

-- Queues a search for each of your auctions whose comparison is missing or older than STALE.
function U:QueueStale(now)
	local all = U:Mine()
	if not (all and ah.open) then return 0 end
	local added = 0
	for key, e in pairs(all) do
		if e.k and not queued[key] and (not e.ot or now - e.ot > U.STALE) then
			queue[#queue + 1] = key
			queued[key] = true
			added = added + 1
		end
	end
	table.sort(queue, function(a, b) return tostring(a) < tostring(b) end)
	if added > 0 and not pumpTimer then
		ns:Debug("undercut: queued", added, "checks")
		pumpTimer = C_Timer.NewTimer(U.CHECK_GAP, ns:Guard("Undercut checks", pump))
	end
	return added
end

-- Reading your auctions -----------------------------------------------------------

local function queryOwned()
	local AH = C_AuctionHouse
	if not (ah.open and AH and AH.QueryOwnedAuctions) then return end
	if AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady() then return end
	local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Name or 1
	ns.Try(AH.QueryOwnedAuctions, { { sortOrder = order, reverseSort = false } })
end
local queryOwnedSoon = ns:Debounce("Owned auctions", 1, queryOwned)

-- "commodity", "item", or nil while the client has not loaded the item.
local function commodityKind(itemID)
	local AH, E = C_AuctionHouse, Enum and Enum.ItemCommodityStatus
	local status = AH.GetItemCommodityStatus and ns.Try(AH.GetItemCommodityStatus, itemID)
	if E and status == E.Commodity then return "commodity" end
	if E and status == E.Item then return "item" end
	if C_Item and C_Item.RequestLoadItemDataByID then ns.Try(C_Item.RequestLoadItemDataByID, itemID) end
	return nil
end

local function ownedUnit(info, key)
	local entry = P:Get(key)
	return U.OwnedUnit(info.buyoutAmount, info.quantity, commodityKind(info.itemKey.itemID), entry and entry.m)
end

ns:On("OWNED_AUCTIONS_UPDATED", function()
	local AH = C_AuctionHouse
	local all = U:Mine()
	if not (all and AH and ah.open) then return end
	-- A list still loading would look like sold auctions; wait for all of it.
	if AH.HasFullOwnedAuctionResults and not AH.HasFullOwnedAuctionResults() then return end
	local active = Enum and Enum.AuctionStatus and Enum.AuctionStatus.Active or 0
	local now, seen = time(), {}
	for i = 1, AH.GetNumOwnedAuctions() or 0 do
		local info = AH.GetOwnedAuctionInfo(i)
		if info and info.status == active and info.buyoutAmount and info.buyoutAmount > 0 and info.itemKey then
			local key = U.KeyOf(info.itemKey, info.itemLink)
			if key then
				local unit = ownedUnit(info, key)
				local s = seen[key]
				if not s then
					local ik = info.itemKey
					s = { u = unit, q = 0, k = { ik.itemID, ik.itemLevel, ik.itemSuffix, ik.battlePetSpeciesID } }
					seen[key] = s
				end
				if unit < s.u then s.u = unit end
				s.q = s.q + (info.quantity or 1)
			end
		end
	end
	-- Replace the list. A comparison at the same price is kept; at a new price, what is known
	-- about the others still says whether someone is cheaper, and the check queue does the rest.
	for key, s in pairs(seen) do
		local old = all[key]
		local e = { u = s.u, q = s.q, t = now, k = s.k }
		if old then
			e.o, e.ot = old.o, old.ot
			if old.u == s.u then
				e.s, e.n, e.b = old.s, old.n, old.b
			elseif old.o then
				e.s = old.o < s.u and "undercut" or (old.o > s.u and "lowest" or nil)
				e.ot = nil   -- check it again soon
			end
		end
		all[key] = e
	end
	for key in pairs(all) do
		if not seen[key] then all[key] = nil end
	end
	ns:Send("UndercutsChanged")
	U:QueueStale(now)
end)

ns:On("AUCTION_HOUSE_SHOW", queryOwnedSoon)
ns:On("AUCTION_HOUSE_AUCTION_CREATED", queryOwnedSoon)
ns:On("AUCTION_CANCELED", queryOwnedSoon)
ns:On("AUCTION_HOUSE_CLOSED", stopQueue)

-- Listings seen -------------------------------------------------------------------

ns:On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
	local AH = C_AuctionHouse
	if not (itemID and AH and AH.HasFullCommoditySearchResults(itemID)) then return end
	local listings = {}
	for i = 1, AH.GetNumCommoditySearchResults(itemID) do
		local r = AH.GetCommoditySearchResultInfo(itemID, i)
		if r and r.unitPrice and r.unitPrice > 0 then
			local own = r.containsOwnerItem and (r.numOwnerItems or r.quantity or 0) or 0
			if own > 0 then listings[#listings + 1] = { r.unitPrice, own, true } end
			-- A row can hold your units and someone else's at the same price.
			local others = (r.quantity or 0) - own
			if others > 0 then listings[#listings + 1] = { r.unitPrice, others } end
		end
	end
	check(P.ItemKey(itemID), listings)
end)

ns:On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
	local AH = C_AuctionHouse
	if not (itemKey and AH and AH.HasFullItemSearchResults(itemKey)) then return end
	local listings = {}
	for i = 1, AH.GetNumItemSearchResults(itemKey) do
		local r = AH.GetItemSearchResultInfo(itemKey, i)
		if r and r.buyoutAmount and r.buyoutAmount > 0 then
			local qty = math.max(1, r.quantity or 1)
			listings[#listings + 1] = { math.floor(r.buyoutAmount / qty + 0.5), qty, r.containsOwnerItem }
		end
	end
	check(U.KeyOf(itemKey), listings)
end)

-- Browse results give only the cheapest price per item, so only strictly cheaper counts.
ns:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
	local all = U:Mine()
	if not (all and next(all) and C_AuctionHouse) then return end
	for _, r in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
		local key = U.KeyOf(r.itemKey)
		local e = key and all[key]
		if e and r.minPrice and r.minPrice > 0 and r.minPrice < e.u then
			check(key, { { r.minPrice, r.totalQuantity or 0 } })
		end
	end
end)

-- After a full scan: every item you list, one summary.
-- grouped: { [itemKey] = { { unit, qty, own, seller }, ... } } from Scanner.
function U.FromScan(grouped, now)
	local all = U:Mine()
	if not all then return {} end
	local keys = {}
	for key in pairs(all) do keys[key] = true end
	for key, listings in pairs(grouped) do
		if not keys[key] then
			for i = 1, #listings do
				if listings[i][3] then keys[key] = true; break end
			end
		end
	end
	local alerts = {}
	for key in pairs(keys) do
		local listings = grouped[key]
		if listings then
			local mine, other, atMine = U.Compare(listings, all[key] and all[key].u)
			if record(key, mine, other, atMine, now) then alerts[#alerts + 1] = key end
		end
	end
	table.sort(alerts, function(a, b) return tostring(a) < tostring(b) end)
	return alerts
end

ns:On("FullScanListings", function(grouped)
	local alerts = U.FromScan(grouped, time())
	ns:Send("UndercutsChanged")
	if #alerts == 0 or not ns.db.settings.undercutAlerts then return end
	local all = U:Mine()
	ns:Print(#alerts .. " of your auctions were undercut:")
	for i = 1, math.min(#alerts, 10) do print("  " .. alertLine(alerts[i], all[alerts[i]])) end
	if #alerts > 10 then print("  +" .. (#alerts - 10) .. " more: /ka, My auctions") end
	sound()
end)

function U:OnLogin()
	U:Prune(time())
end
