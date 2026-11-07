-- Kabobo's Auctions: your auctions, and whether someone else now lists the item cheaper or at
-- your price. Both are "undercut": at the same price, the auction listed later sells first.
--
-- Your auctions are read with C_AuctionHouse.QueryOwnedAuctions when the auction house opens and
-- after you post or cancel one. They are compared against every listing the addon sees: full
-- scans (Scanner sends FullScanListings), item and commodity searches (the Sell tab searches the
-- item you post, so a fresh post is checked right away) and browse results. A change to undercut
-- prints one chat line; a full scan prints one summary.
--
-- Saved layout: db.mine[realmKey][charName][itemKey] = {
--   u = your cheapest unit price, q = quantity you list, t = time() read,
--   s = "undercut" | "lowest" (nil until compared; "matched" from older versions counts as
--   undercut), o = cheapest other unit price (equal to u: undercut at the same price),
--   ot = time() of that comparison }
-- Sends UndercutsChanged when the list or a status changes.
local _, ns = ...
local U = ns:NewModule("Undercut")
local P = ns.Pricing

U.KEEP = 48 * 3600   -- the longest auction; older entries are gone even if never refreshed

local ah = ns:Session("AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED")

-- Pure logic ----------------------------------------------------------------------

-- listings: array of { unitPrice, quantity, own }. own marks your listings when the source
-- knows (searches, full scans); without it, only listings strictly cheaper than myUnit count.
-- myUnit: your saved cheapest unit price; your own listings in `listings` override it.
-- Returns status ("undercut", "lowest", or nil when you list none), your unit price and the
-- cheapest unit price of someone else (nil when nobody else lists it). Someone else at your
-- price is an undercut too: the later auction sells first. That needs your own rows marked;
-- without them a listing at your price may be yours, so only strictly cheaper counts.
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
	if otherMin and otherMin < mine then return "undercut", mine, otherMin end
	if ownMin and otherMin == mine then return "undercut", mine, otherMin end
	return "lowest", mine, otherMin
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

-- Your auctions as list items, undercut first: { key, entry }.
function U:List()
	local mine = U:Mine()
	local order = { undercut = 1, matched = 1, lowest = 3 }
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
	local same = e.o == e.u
	local what = ns.KaboboUI.Color(same and "Undercut at your price" or "Undercut", "bad")
	return what .. ": " .. itemLink(key) .. (e.q and e.q > 1 and (" x" .. e.q) or "")
		.. "  yours " .. Money(e.u) .. ", " .. (same and "someone else also lists at " or "cheapest now ") .. Money(e.o)
end

local function sound()
	if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then ns.Try(PlaySound, SOUNDKIT.RAID_WARNING) end
end

-- Records a comparison for one item. Returns true when it is newly undercut (or by a new price),
-- which is worth an alert.
local function record(key, status, mine, other, now)
	local all = U:Mine()
	if not (all and status) then return false end
	local e = all[key]
	if not e then
		e = { u = mine, t = now }
		all[key] = e
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
	local status, mine, other = U.Compare(listings, saved and saved.u)
	if not status then return end
	local now = time()
	if record(key, status, mine, other, now) and ns.db.settings.undercutAlerts then
		ns:Print(alertLine(key, all[key]))
		sound()
	end
	ns:Send("UndercutsChanged")
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

-- Price per unit of an owned auction. Commodity buyouts are per unit; an item auction's buyout
-- is for all of it.
local function ownedUnit(info)
	local qty = math.max(1, info.quantity or 1)
	local AH = C_AuctionHouse
	local status = AH.GetItemCommodityStatus and info.itemKey and ns.Try(AH.GetItemCommodityStatus, info.itemKey.itemID)
	local commodity = Enum and Enum.ItemCommodityStatus and status == Enum.ItemCommodityStatus.Commodity
	if commodity then return info.buyoutAmount end
	return math.floor(info.buyoutAmount / qty + 0.5)
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
		if info and info.status == active and info.buyoutAmount and info.buyoutAmount > 0 then
			local key = U.KeyOf(info.itemKey, info.itemLink)
			if key then
				local unit = ownedUnit(info)
				local s = seen[key]
				if not s then
					s = { u = unit, q = 0 }
					seen[key] = s
				end
				if unit < s.u then s.u = unit end
				s.q = s.q + (info.quantity or 1)
			end
		end
	end
	-- Replace the list, keeping a comparison that is still about the same price.
	for key, s in pairs(seen) do
		local old = all[key]
		local keep = old and old.u == s.u
		all[key] = { u = s.u, q = s.q, t = now, s = keep and old.s or nil, o = keep and old.o or nil, ot = keep and old.ot or nil }
	end
	for key in pairs(all) do
		if not seen[key] then all[key] = nil end
	end
	ns:Send("UndercutsChanged")
end)

ns:On("AUCTION_HOUSE_SHOW", queryOwnedSoon)
ns:On("AUCTION_HOUSE_AUCTION_CREATED", queryOwnedSoon)
ns:On("AUCTION_CANCELED", queryOwnedSoon)

-- Listings seen -------------------------------------------------------------------

ns:On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
	local AH = C_AuctionHouse
	if not (itemID and AH and AH.HasFullCommoditySearchResults(itemID)) then return end
	local listings = {}
	for i = 1, AH.GetNumCommoditySearchResults(itemID) do
		local r = AH.GetCommoditySearchResultInfo(itemID, i)
		if r and r.unitPrice and r.unitPrice > 0 then
			listings[#listings + 1] = { r.unitPrice, r.quantity or 0, r.containsOwnerItem }
			-- A row can hold your units and someone else's at the same price.
			if r.containsOwnerItem and (r.totalNumberOfOwners or 1) > 1 then
				listings[#listings + 1] = { r.unitPrice, (r.quantity or 0) - (r.numOwnerItems or 0) }
			end
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
		if key and all[key] and r.minPrice and r.minPrice > 0 then
			check(key, { { r.minPrice, r.totalQuantity or 0 } })
		end
	end
end)

-- After a full scan: every item you list, one summary.
-- grouped: { [itemKey] = { { unit, qty, own }, ... } } from Scanner.
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
			local status, mine, other = U.Compare(listings, all[key] and all[key].u)
			if record(key, status, mine, other, now) then alerts[#alerts + 1] = key end
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
