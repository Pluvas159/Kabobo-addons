-- BarText: a small line at the right end of Blizzard's experience and reputation bars
-- ("12.3k xp/h · 42m to level (hour: 55m)"), and a tooltip with the details on hover.
--
-- The bars belong to StatusTrackingBarManager (Blizzard_StatusTrackingBar): each of its two
-- containers holds one bar of every kind and shows one at a time, so both containers' bars get a
-- line. We only add font strings and HookScript; nothing of Blizzard's is replaced.
local _, ns = ...
local B = ns:NewModule("BarText")
local PUI = ns.KaboboUI

B.TICK = 10      -- seconds between refreshes while a rate is changing (gains leave the window)
B.ALPHA = 0.8    -- a touch fainter than Blizzard's own bar text
B.SEP = "  \194\183  " -- middle dot

local labels = { xp = {}, rep = {} } -- font strings we added, per kind
local attached = {}                  -- [bar] = "xp" or "rep"
local ticker

-- Text ------------------------------------------------------------------------------

local function standingLabel(reaction)
	if not reaction then return nil end
	local key = "FACTION_STANDING_LABEL" .. reaction
	if GetText then
		local ok, text = pcall(GetText, key, UnitSex and UnitSex("player"))
		if ok and text and text ~= key then return text end
	end
	return _G[key]
end
B.StandingLabel = standingLabel

-- Bar text from a Progress status, or nil when nothing was gained in the last hour:
--   "12.3k xp/h  ·  42m to level (hour: 55m)"
-- The rate and its estimate are from the last 15 minutes; the estimate from the last hour joins
-- in brackets once counting is older than 15 minutes (before that the two are the same). After
-- 15 minutes without gains only the hour is left: "hour: 9.8k xp/h  ·  55m to level".
local function barText(s, unit, goal)
	if not s then return nil end
	if s.perHour > 0 then
		local text = PUI.Short(s.perHour) .. " " .. unit .. "/h"
		if s.ttl then
			local quarter = PUI.Duration(s.ttl)
			text = text .. B.SEP .. quarter .. " to " .. goal
			local hour = s.hasHour and s.hourTtl and PUI.Duration(s.hourTtl)
			if hour and hour ~= quarter then text = text .. " (hour: " .. hour .. ")" end
		end
		return text
	end
	if s.hourPerHour and s.hourPerHour > 0 then
		local text = "hour: " .. PUI.Short(s.hourPerHour) .. " " .. unit .. "/h"
		if s.hourTtl then text = text .. B.SEP .. PUI.Duration(s.hourTtl) .. " to " .. goal end
		return text
	end
	return nil
end

function B.XPText(s)
	return barText(s, "xp", "level")
end

function B.RepText(s)
	return barText(s, "rep", s and standingLabel(s.reaction and s.reaction + 1) or "next")
end

local function count(n)
	n = math.floor(n + 0.5)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

-- Tooltip lines (label/value) from a Progress status. goal names what comes next ("Level 24").
function B.TooltipLines(s, unit, goal)
	local function rate(perHour) return PUI.Short(perHour) .. " " .. unit .. "/h" end
	local function eta(ttl) return ttl and PUI.Duration(ttl) or PUI.Color("-", "muted") end
	local lines = { { "Last 15 min", rate(s.perHour) } }
	if s.hasHour then lines[#lines + 1] = { "Last hour", rate(s.hourPerHour) } end
	lines[#lines + 1] = { "This session", rate(s.session) }
	lines[#lines + 1] = { "Gained", count(s.gained) .. " in " .. PUI.Duration(s.elapsed) }
	if goal and s.remaining and s.remaining > 0 then
		lines[#lines + 1] = { goal, count(s.remaining) .. " to go" }
		lines[#lines + 1] = { "   at the last 15 min", eta(s.ttl), color = "soft" }
		if s.hasHour then lines[#lines + 1] = { "   at the last hour", eta(s.hourTtl), color = "soft" } end
	end
	return lines
end

-- Refresh ---------------------------------------------------------------------------

local function setAll(kind, text)
	for _, label in ipairs(labels[kind]) do
		label:SetText(text or "")
		label:SetShown(text ~= nil)
	end
end

local function tick()
	B:Refresh()
	if not ns.Progress:HasRecent(time()) and ticker then
		ticker:Cancel()
		ticker = nil
	end
end

function B:Refresh()
	if not next(attached) then return end
	local now = time()
	local settings = ns.db.settings
	setAll("xp", settings.xp and B.XPText(ns.Progress:XPStatus(now)) or nil)
	setAll("rep", settings.rep and B.RepText(ns.Progress:RepStatus(now)) or nil)
	-- Rates fall as gains age out of the window, so keep refreshing while there are any.
	if not ticker and ns.Progress:HasRecent(now) then
		ticker = C_Timer.NewTicker(B.TICK, ns:Guard("BarText tick", tick))
	end
end

-- Hover -----------------------------------------------------------------------------

local function onEnter(bar)
	local kind = attached[bar]
	if not kind or not ns.db.settings[kind] then return end
	local now = time()
	local title, lines
	if kind == "xp" then
		local s = ns.Progress:XPStatus(now)
		if not s or s.gained <= 0 then return end
		title, lines = "Experience", B.TooltipLines(s, "xp", "Level " .. (s.level + 1))
	else
		local s = ns.Progress:RepStatus(now)
		if not s or s.gained <= 0 then return end
		title, lines = s.name or "Reputation", B.TooltipLines(s, "rep", standingLabel(s.reaction and s.reaction + 1) or "Next standing")
	end
	PUI.ShowTooltip(bar, title, nil, "ANCHOR_CURSOR")
	PUI.AddTooltipLines(GameTooltip, lines)
	GameTooltip:Show()
end

local function onLeave(bar)
	if GameTooltip:GetOwner() == bar then GameTooltip:Hide() end
end

-- Attaching -------------------------------------------------------------------------

local function decorate(bar, kind)
	if not bar or attached[bar] then return end
	attached[bar] = kind
	local font = _G[PUI.Fonts.bar] and "bar" or "body"
	local label = PUI.Text(bar.OverlayFrame or bar, font, "RIGHT")
	-- Blizzard centers its own text at y = 1; ours sits at the right end, out of its way.
	label:SetPoint("RIGHT", bar, "RIGHT", -8, 1)
	label:SetTextColor(PUI.RGB("soft"))
	label:SetAlpha(B.ALPHA)
	label:Hide()
	labels[kind][#labels[kind] + 1] = label
	bar:HookScript("OnEnter", ns:Guard("BarText tooltip", onEnter))
	bar:HookScript("OnLeave", ns:Guard("BarText tooltip hide", onLeave))
end

local function barIndex(key, fallback)
	local info = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
	return info and info[key] or fallback
end

function B:Attach()
	local manager = StatusTrackingBarManager
	if not manager or not manager.barContainers then
		ns:Debug("no StatusTrackingBarManager: bar text is off")
		return
	end
	local xpIndex, repIndex = barIndex("Experience", 4), barIndex("Reputation", 1)
	for _, container in ipairs(manager.barContainers) do
		if container.bars then
			decorate(container.bars[xpIndex], "xp")
			decorate(container.bars[repIndex], "rep")
		end
	end
	B:Refresh()
end

function B:OnLogin()
	if StatusTrackingBarManager then
		B:Attach()
	else
		ns:WhenLoaded("Blizzard_StatusTrackingBar", function() B:Attach() end)
	end
end

ns:On("ProgressChanged", function() B:Refresh() end)
ns:On("SettingChanged", function() B:Refresh() end)
