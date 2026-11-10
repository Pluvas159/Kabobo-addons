-- Rates: gains over time, as plain tables so they can be saved. No game state is read here.
--
-- A tracker is { start = time(), total = n, t = { times }, v = { amounts } }: when counting
-- began, everything gained since, and the gains of the last WINDOW seconds (one entry per second
-- with a gain), oldest first.
local _, ns = ...
local R = ns:NewModule("Rates")

local floor, min, max = math.floor, math.min, math.max

R.WINDOW = 15 * 60  -- the "recent" rate and the time to level use the last 15 minutes
-- A rate needs some time behind it: one kill ten seconds after login is not 40k an hour.
R.MIN_SPAN = 2 * 60

function R.New(now)
	return { start = now, total = 0, t = {}, v = {} }
end

-- Counts a gain. Losses (reputation going down) are not gains and are left out.
function R.Add(tracker, amount, now)
	if not amount or amount <= 0 then return end
	tracker.total = tracker.total + amount
	local t, v = tracker.t, tracker.v
	local n = #t
	if n > 0 and t[n] == now then
		v[n] = v[n] + amount
	else
		t[n + 1], v[n + 1] = now, amount
	end
end

-- Drops gains older than the window.
function R.Prune(tracker, now, window)
	local cutoff = now - (window or R.WINDOW)
	local t, v = tracker.t, tracker.v
	local drop = 0
	while t[drop + 1] and t[drop + 1] <= cutoff do drop = drop + 1 end
	if drop == 0 then return end
	local nt, nv = {}, {}
	for i = drop + 1, #t do
		nt[#nt + 1], nv[#nv + 1] = t[i], v[i]
	end
	tracker.t, tracker.v = nt, nv
end

-- Per hour over the last window, or since counting began when that is shorter. Returns the rate
-- and the amount gained in the window.
function R.Recent(tracker, now, window)
	window = window or R.WINDOW
	R.Prune(tracker, now, window)
	local sum = 0
	for i = 1, #tracker.v do sum = sum + tracker.v[i] end
	if sum <= 0 then return 0, 0 end
	local span = min(window, max(now - tracker.start, R.MIN_SPAN))
	return sum / span * 3600, sum
end

-- Per hour since counting began.
function R.Session(tracker, now)
	if tracker.total <= 0 then return 0 end
	return tracker.total / max(now - tracker.start, R.MIN_SPAN) * 3600
end

-- Seconds until `remaining` more is gained at `perHour`; nil when it will not happen.
function R.TimeTo(remaining, perHour)
	if not remaining or remaining <= 0 or not perHour or perHour <= 0 then return nil end
	return floor(remaining / perHour * 3600 + 0.5)
end

-- Experience gained between two readings { xp, max, level }. The bar starts over at a level-up,
-- so a higher level, or less experience than before (the event can come before UnitLevel
-- changes), means what was left of the old level plus the new reading.
function R.XPGain(old, new)
	if new.level > old.level or new.xp < old.xp then
		return max(0, old.max - old.xp) + new.xp
	end
	return new.xp - old.xp
end
