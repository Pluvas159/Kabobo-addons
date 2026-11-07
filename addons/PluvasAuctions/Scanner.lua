-- Pluvas' Auctions: auction house scanning.
--
-- Full scan: C_AuctionHouse.ReplicateItems() returns every auction at once. The Forever
-- server allows this once per account every 15 minutes, so the time is saved account-wide.
-- Passive capture: anything you browse or search in the normal AH window is recorded too,
-- so prices stay fresh between full scans.
local _, ns = ...
local S = ns:NewModule("Scanner")
local P = ns.Pricing

S.COOLDOWN = 15 * 60
S.CHUNK = 1000           -- auctions processed per frame, to avoid freezing the game
S.SETTLE = 2             -- seconds without new rows before the result is treated as complete
S.TIMEOUT = 120          -- seconds to wait for the server to answer at all

S.state = "idle"         -- idle | waiting | processing
S.progress = 0

local ahOpen = false
local settleTimer, timeoutTimer
local lastCount = -1
local listeners = {}

function S:OnStateChanged(fn)
	listeners[#listeners + 1] = fn
end

local function notify()
	for i = 1, #listeners do listeners[i](S.state, S.progress) end
end

local function setState(state, progress)
	S.state = state
	S.progress = progress or 0
	notify()
end

function S:IsOpen()
	return ahOpen
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

function S:FullScan()
	if not ahOpen then
		ns:Print("open the auction house first.")
		return
	end
	if S.state ~= "idle" then
		ns:Print("a scan is already running.")
		return
	end
	local remaining = S:CooldownRemaining()
	if remaining > 0 then
		ns:Print("the server allows one full scan every 15 minutes. Next scan in " .. ns.Clock(remaining) .. ".")
		return
	end

	lastCount = -1
	setState("waiting")
	ns.db.account.lastReplicate = time()
	C_AuctionHouse.ReplicateItems()
	ns:Print("full scan requested, waiting for the auction house...")

	timeoutTimer = C_Timer.NewTimer(S.TIMEOUT, function()
		timeoutTimer = nil
		if S.state == "waiting" then
			cancelTimers()
			setState("idle")
			ns:Print("the auction house did not answer the full scan. Try again later.")
		end
	end)
end

local process

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

ns:On("REPLICATE_ITEM_LIST_UPDATE", function()
	if S.state ~= "waiting" then return end
	lastCount = C_AuctionHouse.GetNumReplicateItems() or 0
	if settleTimer then settleTimer:Cancel() end
	settleTimer = C_Timer.NewTimer(S.SETTLE, checkSettled)
end)

process = function(count)
	cancelTimers()
	setState("processing", 0)

	local started = debugprofilestop and debugprofilestop() or 0
	local grouped = {}       -- itemKey -> { {unit, qty}, ... }
	local seen, skipped = 0, 0
	local index = 0

	local function finish()
		local now = time()
		local realm = ns:RealmData()
		local items = 0
		for key, listings in pairs(grouped) do
			local stats = P.ComputeStats(listings)
			if stats then
				P.Record(realm.items, key, stats, now)
				items = items + 1
			end
		end
		realm.lastScan = now
		local elapsed = debugprofilestop and (debugprofilestop() - started) / 1000 or 0
		setState("idle")
		ns:Print(string.format("full scan done: %d auctions, %d items priced in %.1fs.", seen, items, elapsed))
		if skipped > 0 then
			ns:Debug(skipped .. " auctions had no buyout or no item data")
		end
	end

	local function step()
		if not ahOpen then
			setState("idle")
			ns:Print("auction house closed during the scan, results discarded.")
			return
		end
		local last = math.min(index + S.CHUNK, count) - 1
		for i = index, last do
			local _, _, qty, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
			if itemID and qty and qty > 0 and buyout and buyout > 0 then
				local link = C_AuctionHouse.GetReplicateItemLink(i)
				local key = (link and P.ItemKeyFromLink(link)) or P.ItemKey(itemID)
				local list = grouped[key]
				if not list then
					list = {}
					grouped[key] = list
				end
				-- Replicate buyouts are for the whole stack.
				list[#list + 1] = { buyout / qty, qty }
				seen = seen + 1
			else
				skipped = skipped + 1
			end
		end
		index = last + 1
		if index < count then
			setState("processing", index / count)
			C_Timer.After(0, step)
		else
			finish()
		end
	end

	step()
end

-- Passive capture ---------------------------------------------------------

local function keyFromItemKey(itemKey)
	if not itemKey or not itemKey.itemID then return nil end
	return P.ItemKey(itemKey.itemID, itemKey.itemSuffix)
end

-- Browse results only tell us the cheapest price and total quantity per item.
ns:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
	local results = C_AuctionHouse.GetBrowseResults()
	if not results then return end
	local items, now = ns:RealmData().items, time()
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
	if stats then P.Record(ns:RealmData().items, P.ItemKey(itemID), stats, time()) end
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
	if stats and key then P.Record(ns:RealmData().items, key, stats, time()) end
end)

-- AH open/close -----------------------------------------------------------

ns:On("AUCTION_HOUSE_SHOW", function()
	ahOpen = true
	notify()
end)

ns:On("AUCTION_HOUSE_CLOSED", function()
	ahOpen = false
	if S.state == "waiting" then
		cancelTimers()
		setState("idle")
	else
		notify()
	end
end)
