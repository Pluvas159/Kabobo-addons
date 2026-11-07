-- Kabobo's Auctions: auction house scanning.
--
-- Full scan: C_AuctionHouse.ReplicateItems() returns every auction at once. The Forever server
-- allows this once per account every 15 minutes, so the time is saved account-wide.
-- Passive capture: anything you browse or search in the normal AH window is recorded too, so
-- prices stay fresh between full scans.
--
-- C_AuctionHouse is only called while the auction house is open. Sends ScanStateChanged when
-- the state, the progress or the AH's open state changes, and PricesChanged after a full scan.
local _, ns = ...
local S = ns:NewModule("Scanner")
local P = ns.Pricing

S.COOLDOWN = 15 * 60
S.CHUNK = 1000           -- auctions processed per frame, to avoid freezing the game
S.SETTLE = 2             -- seconds without new rows before the result is treated as complete
S.TIMEOUT = 120          -- seconds to wait for the server to answer at all

S.state = "idle"         -- idle | waiting | processing
S.progress = 0

local ah = ns:Session("AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED")
local settleTimer, timeoutTimer
local lastCount = -1

local function setState(state, progress)
	S.state, S.progress = state, progress or 0
	ns:Send("ScanStateChanged", S.state, S.progress)
end

function S:IsOpen()
	return ah.open
end

function S:CooldownRemaining()
	local last = ns.db.account.lastReplicate or 0
	return math.max(0, S.COOLDOWN - (time() - last))
end

local function cancelTimers()
	if settleTimer then settleTimer:Cancel(); settleTimer = nil end
	if timeoutTimer then timeoutTimer:Cancel(); timeoutTimer = nil end
end

-- Full scan ---------------------------------------------------------------

-- Whether a replicate row's seller is this character (name, or name-realm).
function S.IsMe(owner, ownerFullName)
	local me = ns.charName
	if not me then return false end
	return owner == me or ownerFullName == me or ownerFullName == (me .. "-" .. tostring(ns.realm))
end

-- Turns one replicate row into (itemKey, unit price, quantity, yours, seller, time-left band 1-4
-- or nil), or nil for rows without a buyout or item data. Replicate buyouts are for the whole
-- stack.
local function readRow(index)
	local _, _, qty, _, _, _, _, _, _, buyout, _, _, _, owner, ownerFullName, _, itemID = C_AuctionHouse.GetReplicateItemInfo(index)
	if not (itemID and qty and qty > 0 and buyout and buyout > 0) then return nil end
	local link = C_AuctionHouse.GetReplicateItemLink(index)
	local band = C_AuctionHouse.GetReplicateItemTimeLeft and ns.Try(C_AuctionHouse.GetReplicateItemTimeLeft, index)
	band = type(band) == "number" and band + 1 or nil
	return (link and P.ItemKeyFromLink(link)) or P.ItemKey(itemID), buyout / qty, qty, S.IsMe(owner, ownerFullName) or nil,
		ownerFullName or owner or "", band
end

-- Reads every row over several frames, then records one entry per item.
local function process(count)
	cancelTimers()
	setState("processing", 0)
	local started = debugprofilestop and debugprofilestop() or 0
	local grouped = {}   -- itemKey -> { { unit, qty, yours, seller, band }, ... }
	local seen, skipped = 0, 0

	ns:Spread({
		name = "Full scan",
		count = count,
		size = S.CHUNK,
		alive = function() return ah.open end,
		step = function(i)
			local key, unit, qty, mine, seller, band = readRow(i - 1)   -- replicate rows start at 0
			if not key then
				skipped = skipped + 1
				return
			end
			local list = grouped[key]
			if not list then
				list = {}
				grouped[key] = list
			end
			list[#list + 1] = { unit, qty, mine, seller, band }
			seen = seen + 1
		end,
		progress = function(done, total) setState("processing", done / total) end,
		done = function(ok, err)
			if not ok then
				setState("idle")
				ns:Print(err and "the full scan failed; nothing was saved."
					or "auction house closed during the scan, results discarded.")
				return
			end
			local now, realm, items = time(), P:Realm(), 0
			for key, listings in pairs(grouped) do
				local stats = P.ComputeStats(listings)
				if stats then
					P.Record(realm.items, key, stats, now)
					items = items + 1
				end
			end
			realm.lastScan = now
			-- Undercut compares your listings (marked) against everyone else's.
			ns:Send("FullScanListings", grouped)
			local elapsed = debugprofilestop and (debugprofilestop() - started) / 1000 or 0
			setState("idle")
			ns:Send("PricesChanged")
			ns:Print(string.format("full scan done: %d auctions, %d items priced in %.1fs.", seen, items, elapsed))
			if skipped > 0 then ns:Debug(skipped .. " auctions had no buyout or no item data") end
		end,
	})
end

-- The result is complete once the row count stops changing for S.SETTLE seconds.
local function checkSettled()
	settleTimer = nil
	if S.state ~= "waiting" then return end
	local count = C_AuctionHouse.GetNumReplicateItems() or 0
	if count > 0 and count == lastCount then
		process(count)
	else
		lastCount = count
		settleTimer = C_Timer.NewTimer(S.SETTLE, checkSettled)
	end
end

function S:FullScan()
	if not ah.open then
		ns:Print("open the auction house first.")
		return
	end
	if S.state ~= "idle" then
		ns:Print("a scan is already running.")
		return
	end
	local remaining = S:CooldownRemaining()
	if remaining > 0 then
		ns:Print("the server allows one full scan every 15 minutes. Next scan in "
			.. ns.KaboboUI.Clock(remaining) .. ".")
		return
	end

	lastCount = -1
	setState("waiting")
	ns.db.account.lastReplicate = time()
	C_AuctionHouse.ReplicateItems()
	ns:Print("full scan requested, waiting for the auction house...")

	timeoutTimer = C_Timer.NewTimer(S.TIMEOUT, function()
		timeoutTimer = nil
		if S.state ~= "waiting" then return end
		cancelTimers()
		setState("idle")
		ns:Print("the auction house did not answer the full scan. Try again later.")
	end)
end

ns:On("REPLICATE_ITEM_LIST_UPDATE", function()
	if S.state ~= "waiting" then return end
	lastCount = C_AuctionHouse.GetNumReplicateItems() or 0
	if settleTimer then settleTimer:Cancel() end
	settleTimer = C_Timer.NewTimer(S.SETTLE, checkSettled)
end)

-- Passive capture ---------------------------------------------------------

local function keyFromItemKey(itemKey)
	if not itemKey or not itemKey.itemID then return nil end
	return P.ItemKey(itemKey.itemID, itemKey.itemSuffix)
end

-- Browse results only tell us the cheapest price and total quantity per item.
ns:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
	local results = C_AuctionHouse.GetBrowseResults()
	if not results then return end
	local items, now = P:Realm().items, time()
	for _, r in ipairs(results) do
		local key = keyFromItemKey(r.itemKey)
		if key and r.minPrice and r.minPrice > 0 then
			P.RecordMin(items, key, r.minPrice, r.totalQuantity, now)
		end
	end
end)

-- A complete commodity search gives every listing, so it can update the market value.
ns:On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
	if not itemID or not C_AuctionHouse.HasFullCommoditySearchResults(itemID) then return end
	local listings = {}
	for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
		local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
		if r and r.unitPrice and r.unitPrice > 0 and r.quantity and r.quantity > 0 then
			listings[#listings + 1] = { r.unitPrice, r.quantity }
		end
	end
	local stats = P.ComputeStats(listings)
	if stats then P.Record(P:Realm().items, P.ItemKey(itemID), stats, time()) end
end)

ns:On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
	if not itemKey or not C_AuctionHouse.HasFullItemSearchResults(itemKey) then return end
	local listings = {}
	for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
		local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
		if r and r.buyoutAmount and r.buyoutAmount > 0 then
			local qty = (r.quantity and r.quantity > 0) and r.quantity or 1
			listings[#listings + 1] = { r.buyoutAmount, qty }
		end
	end
	local stats = P.ComputeStats(listings)
	local key = keyFromItemKey(itemKey)
	if stats and key then P.Record(P:Realm().items, key, stats, time()) end
end)

-- AH open/close -----------------------------------------------------------

ns:On("AUCTION_HOUSE_SHOW", function()
	setState(S.state, S.progress)
end)

ns:On("AUCTION_HOUSE_CLOSED", function()
	if S.state == "waiting" then cancelTimers() end
	-- A processing scan notices the closed AH before its next batch and reports it.
	setState(S.state == "waiting" and "idle" or S.state, S.progress)
end)
