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

-- Frames ------------------------------------------------------------------------------
--
-- A generic stand-in for frames, font strings and textures, enough to run UI code outside the
-- game:
--   - RegisterEvent is recorded, so _FIRE(event, ...) reaches OnEvent scripts
--   - Show/Hide/SetShown track visibility and fire OnShow/OnHide; frames start shown, as in game
--   - HookScript chains after the current script
--   - SetPoint/ClearAllPoints/GetPoint record anchors; SetSize/SetHeight/SetWidth record size
--     (SetHeight fires OnSizeChanged)
--   - SetText/GetText keep text
--   - named frames become globals; other setters (Set*, Enable*, Register*, ...) do nothing
-- Fields that do not exist (e.g. frame.TitleText) stay nil, like in game.
_EVENT_FRAMES = {}

local ACTION_VERBS = { "Set", "Enable", "Disable", "Register", "Lock", "Unlock", "Clear", "Start", "Stop" }

local FrameMethods = {}
function FrameMethods:RegisterEvent(e) self.events[e] = true end
function FrameMethods:UnregisterEvent(e) self.events[e] = nil end
function FrameMethods:SetScript(name, fn) self.scripts[name] = fn end
function FrameMethods:GetScript(name) return self.scripts[name] end
function FrameMethods:HookScript(name, fn)
	local old = self.scripts[name]
	self.scripts[name] = function(...)
		if old then old(...) end
		fn(...)
	end
end
function FrameMethods:Show()
	if self.shown then return end
	self.shown = true
	if self.scripts.OnShow then self.scripts.OnShow(self) end
end
function FrameMethods:Hide()
	if not self.shown then return end
	self.shown = false
	if self.scripts.OnHide then self.scripts.OnHide(self) end
end
function FrameMethods:SetShown(v) if v then self:Show() else self:Hide() end end
function FrameMethods:IsShown() return self.shown end
function FrameMethods:IsVisible() return self.shown end
function FrameMethods:SetSize(w, h) self.width, self.height = w, h end
function FrameMethods:SetWidth(w) self.width = w end
function FrameMethods:SetHeight(h)
	local changed = self.height ~= h
	self.height = h
	if changed and self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self, self.width, h) end
end
function FrameMethods:GetWidth() return self.width or 0 end
function FrameMethods:GetHeight() return self.height or 0 end
function FrameMethods:SetPoint(...) self.points[#self.points + 1] = { ... } end
function FrameMethods:ClearAllPoints() self.points = {} end
function FrameMethods:GetPoint(i)
	local p = self.points[i or 1]
	if p then return unpack(p) end
end
function FrameMethods:GetNumPoints() return #self.points end
function FrameMethods:SetText(t) self.text = t end
function FrameMethods:GetText() return self.text end
function FrameMethods:GetParent() return self.parent end
function FrameMethods:GetName() return self.name end
function FrameMethods:CreateFontString() return _NEW_FRAME(nil, self) end
function FrameMethods:CreateTexture() return _NEW_FRAME(nil, self) end

local frameMeta = { __index = function(_, k)
	local m = FrameMethods[k]
	if m then return m end
	if type(k) == "string" then
		for _, verb in ipairs(ACTION_VERBS) do
			if k:sub(1, #verb) == verb then return function() end end
		end
	end
	return nil
end }

function _NEW_FRAME(name, parent)
	local f = setmetatable({ events = {}, scripts = {}, points = {}, shown = true, name = name, parent = parent }, frameMeta)
	if name then _G[name] = f end
	return f
end

function CreateFrame(_, name, parent)
	local f = _NEW_FRAME(name, parent)
	_EVENT_FRAMES[#_EVENT_FRAMES + 1] = f
	return f
end

UIParent = _NEW_FRAME("UIParent")
GameTooltip = _NEW_FRAME("GameTooltip")
GameTooltip_Hide = function() GameTooltip:Hide() end

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

-- Item tooltips: TooltipDataProcessor post-calls are kept in _TOOLTIP_CALLS. _HOVER(tooltip,
-- data) runs every item post-call, as the game does after building an item tooltip.
Enum = Enum or {}
Enum.TooltipDataType = { Item = 0 }
_TOOLTIP_CALLS = {}
TooltipDataProcessor = {
	AddTooltipPostCall = function(kind, fn) _TOOLTIP_CALLS[#_TOOLTIP_CALLS + 1] = { kind = kind, fn = fn } end,
}
function _HOVER(tooltip, data)
	for _, c in ipairs(_TOOLTIP_CALLS) do
		if c.kind == Enum.TooltipDataType.Item then c.fn(tooltip, data) end
	end
end

GetNormalizedRealmName = function() return "Forever" end
UnitFactionGroup = function() return "Horde" end
UnitName = function() return "Pluvas" end
GetMoney = function() return _MONEY or 0 end
