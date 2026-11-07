-- PluvasCore: timing helpers. Reading a game window safely, debouncing bursts of events, and
-- spreading long loops over frames.
local _, ns = ...

-- Sessions ------------------------------------------------------------------------
--
-- Tracks a game window from its open and close events. Client APIs built for a window (trade
-- skill, trainer, merchant, auction house) are only called while its session is open.
--   local trade = ns:Session("TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE")
--   if trade.open then ... end
-- Create sessions before the module's own handlers for the same events, so `open` is already
-- set when they run.
function ns:Session(openEvent, closeEvent)
	local session = { open = false }
	ns:On(openEvent, function() session.open = true end)
	ns:On(closeEvent, function() session.open = false end)
	return session
end

-- Merchants -----------------------------------------------------------------------
--
-- Every item the open vendor window sells: array of { link, id, name, price, quantity,
-- extended, available }. price is in copper for one purchase of `quantity` items; available is
-- -1 for unlimited supply; extended is true when the item also costs tokens or other items.
-- Call only while a MERCHANT_SHOW / MERCHANT_CLOSED session is open.
local function merchantItem(i)
	local link = ns.Try(GetMerchantItemLink, i)
	local item = { link = link, id = link and tonumber(link:match("item:(%d+)")) }
	local info = C_MerchantFrame and ns.Try(C_MerchantFrame.GetItemInfo, i)
	if type(info) == "table" then
		item.name, item.price, item.quantity = info.name, info.price, info.stackCount
		item.extended, item.available = info.hasExtendedCost, info.numAvailable
	elseif GetMerchantItemInfo then
		local ok, name, _, price, quantity, available, _, _, extended = pcall(GetMerchantItemInfo, i)
		if ok then
			item.name, item.price, item.quantity = name, price, quantity
			item.extended, item.available = extended, available
		end
	end
	item.name = item.name or (link and link:match("%[(.-)%]"))
	if not (item.link or item.name) then return nil end
	return item
end

function ns.MerchantItems()
	local out = {}
	for i = 1, ns.Try(GetMerchantNumItems) or 0 do
		local item = merchantItem(i)
		if item then out[#out + 1] = item end
	end
	return out
end

-- Callers -------------------------------------------------------------------------
--
-- For reading client APIs whose quirks are unknown: an error becomes a nil result and is
-- counted, so a read can tell whether it got everything (failures == 0) before it replaces
-- saved data.

local Caller = {}
Caller.__index = Caller

function Caller:Call(fn, ...)
	if not fn then return nil end
	local ok, value = pcall(fn, ...)
	if ok then return value end
	self.failures = self.failures + 1
	return nil
end

function ns.NewCaller()
	return setmetatable({ failures = 0 }, Caller)
end

-- Debounce ------------------------------------------------------------------------
--
-- Returns a trigger that runs fn once, `delay` seconds after the first trigger of a burst.
-- Lists that fire several update events while they fill are read once they settle. fn is
-- guarded under `name`.
function ns:Debounce(name, delay, fn)
	local pending = false
	local run = ns:Guard(name, fn)
	return function()
		if pending then return end
		pending = true
		C_Timer.After(delay, function()
			pending = false
			run()
		end)
	end
end

-- Spread --------------------------------------------------------------------------
--
-- Runs step(i) for i = 1..count, `size` steps per frame, so long loops never freeze the game.
-- The first batch runs right away.
--   name      used in error reports
--   count     number of steps
--   size      steps per frame (default 50)
--   step      function(i)
--   alive     optional function() -> false to stop before the next batch (window closed)
--   progress  optional function(done, count) between batches
--   done      optional function(ok, err): ok is false when alive() stopped the work (err nil)
--             or a step raised err (reported, not rethrown)
function ns:Spread(opts)
	local name, count, size = opts.name or "task", opts.count or 0, opts.size or 50
	local i = 1

	local function finish(ok, err)
		if not opts.done then return end
		local fine, problem = pcall(opts.done, ok, err)
		if not fine then geterrorhandler()(name .. ": " .. tostring(problem)) end
	end

	local function batch()
		local stop = math.min(i + size - 1, count)
		for n = i, stop do opts.step(n) end
		i = stop + 1
	end

	local function tick()
		if opts.alive and not opts.alive() then return finish(false) end
		local ok, err = pcall(batch)
		if not ok then
			geterrorhandler()(name .. ": " .. tostring(err))
			return finish(false, err)
		end
		if i <= count then
			if opts.progress then opts.progress(i - 1, count) end
			C_Timer.After(0, tick)
		else
			finish(true)
		end
	end

	tick()
end
