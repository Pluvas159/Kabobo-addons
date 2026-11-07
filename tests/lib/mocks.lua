-- Minimal stand-ins for the WoW API, enough to load the addon outside the game.
_NS = {}
unpack = unpack or table.unpack
_REAL_PRINT = print

time = os.time
date = os.date
debugprofilestop = function() return os.clock() * 1000 end

local printed = {}
_PRINTED = printed
print = function(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	printed[#printed + 1] = table.concat(parts, " ")
end

geterrorhandler = function() return function(err) error(err, 0) end end
hooksecurefunc = function() end
tinsert = table.insert
UISpecialFrames = {}
SlashCmdList = {}

-- Frames record registered events so tests can fire them.
_EVENT_FRAMES = {}
function CreateFrame()
	local f = { events = {}, scripts = {} }
	function f:RegisterEvent(e) self.events[e] = true end
	function f:SetScript(name, fn) self.scripts[name] = fn end
	_EVENT_FRAMES[#_EVENT_FRAMES + 1] = f
	return f
end

function _FIRE(event, ...)
	for _, f in ipairs(_EVENT_FRAMES) do
		if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
	end
end

-- Timers run in due-time order on a virtual clock when the test calls _RUN_TIMERS().
local timers, clock, seq = {}, 0, 0
C_Timer = {}
local function schedule(delay, fn)
	seq = seq + 1
	timers[#timers + 1] = { due = clock + (delay or 0), seq = seq, fn = fn }
end
function C_Timer.After(delay, fn) schedule(delay, fn) end
function C_Timer.NewTimer(delay, fn)
	local t = {}
	function t:Cancel() self.cancelled = true end
	schedule(delay, function() if not t.cancelled then fn() end end)
	return t
end
function C_Timer.NewTicker() return { Cancel = function() end } end
function _RUN_TIMERS(untilTime)
	local guard = 0
	while #timers > 0 do
		table.sort(timers, function(a, b)
			if a.due ~= b.due then return a.due < b.due end
			return a.seq < b.seq
		end)
		if untilTime and timers[1].due > untilTime then break end
		local t = table.remove(timers, 1)
		clock = t.due
		t.fn()
		guard = guard + 1
		assert(guard < 100000, "timer loop did not settle")
	end
end

GetNormalizedRealmName = function() return "Forever" end
UnitFactionGroup = function() return "Horde" end
UnitName = function() return "Pluvas" end
GetMoney = function() return _MONEY or 0 end
