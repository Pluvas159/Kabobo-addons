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
