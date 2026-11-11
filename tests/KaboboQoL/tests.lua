-- Kabobo's QoL: tests. See tests/lib/harness.lua for test/eq/near/truthy.
local ns = _NS
local R, P, B = ns.Rates, ns.Progress, ns.BarText
local PUI = ns.KaboboUI

-- Client stand-ins this addon needs. Kept here because only this addon uses them.
local now = 1000000
time = function() return now end
local xp = { xp = 1000, max = 10000, level = 20 }
UnitXP = function() return xp.xp end
UnitXPMax = function() return xp.max end
UnitLevel = function() return xp.level end
local watched -- C_Reputation.GetWatchedFactionData() result
C_Reputation = { GetWatchedFactionData = function() return watched end }
FACTION_STANDING_LABEL5 = "Friendly"
FACTION_STANDING_LABEL6 = "Honored"
function GameTooltip:GetOwner() return self.owner end
function GameTooltip:SetOwner(owner) self.owner = owner end
local tooltipLines = {}
function GameTooltip:AddDoubleLine(l, r) tooltipLines[#tooltipLines + 1] = { l, r } end

-- Blizzard's status bars: two containers, each with a bar of every kind (4 = XP, 1 = rep).
-- Font strings made on a bar's overlay are kept as overlay.label, so tests can read them.
local function bar()
	local f = CreateFrame("Frame")
	local overlay = CreateFrame("Frame", nil, f)
	function overlay:CreateFontString() self.label = _NEW_FRAME(nil, self); return self.label end
	f.OverlayFrame = overlay
	return f
end
local containers = {}
for i = 1, 2 do containers[i] = { bars = { [1] = bar(), [4] = bar() } } end
StatusTrackingBarManager = { barContainers = containers }
StatusTrackingBarInfo = { BarsEnum = { Reputation = 1, Experience = 4 } }

_FIRE("ADDON_LOADED", "KaboboQoL")
_FIRE("PLAYER_LOGIN")

local function char() return ns.db.chars[ns.charKey] end
-- The font string BarText added to a bar.
local function label(container, index)
	return containers[container].bars[index].OverlayFrame.label
end

test("saved variables and defaults", function()
	truthy(KaboboQoLDB, "KaboboQoLDB")
	eq(ns.db.settings.xp, true)
	eq(ns.db.settings.rep, true)
	truthy(char().xp, "xp tracker")
	eq(char().xp.start, now)
end)

-- Rates (pure)

test("rate over the window, merged per second", function()
	local t = R.New(0)
	R.Add(t, 100, 600); R.Add(t, 50, 600); R.Add(t, 0, 610); R.Add(t, -5, 610)
	eq(#t.t, 1); eq(t.v[1], 150); eq(t.total, 150)
	-- 10 minutes of counting: 150 in 600 s
	near((R.Recent(t, 600)), 900)
	near(R.Session(t, 600), 900)
end)

test("rate uses the last 15 minutes once counting is older than that", function()
	local t = R.New(0)
	R.Add(t, 1000, 100)    -- leaves the 15 minutes at 1000
	R.Add(t, 300, 950)
	local perHour, recent = R.Recent(t, 1000)
	eq(recent, 300); near(perHour, 300 / 900 * 3600)
	eq(#t.t, 2, "kept for the hour")
	near(R.Session(t, 1000), 1300 / 1000 * 3600)
end)

test("hour rate uses the last hour, or since counting began", function()
	local t = R.New(0)
	R.Add(t, 1000, 100)
	R.Add(t, 300, 950)
	local perHour, recent = R.Recent(t, 1000, R.HOUR)
	eq(recent, 1300); near(perHour, 1300 / 1000 * 3600)
	R.Add(t, 200, 3800)    -- the gain at 100 is now more than an hour old
	perHour, recent = R.Recent(t, 3800, R.HOUR)
	eq(recent, 500); near(perHour, 500)
	eq(#t.t, 2, "gains older than an hour are dropped")
end)

test("a fresh session is not judged on a few seconds", function()
	local t = R.New(0)
	R.Add(t, 100, 10)
	near((R.Recent(t, 10)), 100 / R.MIN_SPAN * 3600)
end)

test("no gains in the window means no rate", function()
	local t = R.New(0)
	R.Add(t, 100, 10)
	local perHour, recent = R.Recent(t, 2000)
	eq(perHour, 0); eq(recent, 0)
end)

test("rates only average over the time the gains cover", function()
	-- counting began two hours ago, but the gains are only complete for the last 15 minutes
	local t = R.New(0)
	t.since = 7200 - 900
	R.Add(t, 2250, 7000)
	near((R.Recent(t, 7200, R.HOUR)), 9000, 1e-6, "not 2250 an hour")
	near((R.Recent(t, 7200, R.WINDOW)), 9000)
	near(R.Session(t, 7200), 2250 / 2)
end)

test("trackers saved before the hour estimate get a since", function()
	local t = { start = 0, total = 0, t = {}, v = {} }
	R.AddSince(t, 7200)
	eq(t.since, 7200 - R.WINDOW)
	local young = { start = 7000, total = 0, t = {}, v = {} }
	R.AddSince(young, 7200)
	eq(young.since, 7000)
	local current = R.New(5)
	R.AddSince(current, 7200)
	eq(current.since, 5, "left alone")
	R.AddSince(nil, 1)
end)

test("time to a goal", function()
	eq(R.TimeTo(1000, 2000), 1800)
	eq(R.TimeTo(0, 2000), nil)
	eq(R.TimeTo(1000, 0), nil)
	eq(R.TimeTo(nil, 10), nil)
end)

test("experience gains across a level-up", function()
	eq(R.XPGain({ xp = 100, max = 1000, level = 10 }, { xp = 300, max = 1000, level = 10 }), 200)
	-- bar started over, UnitLevel not updated yet
	eq(R.XPGain({ xp = 900, max = 1000, level = 10 }, { xp = 50, max = 1100, level = 10 }), 150)
	-- level-up with more experience than before (a big quest)
	eq(R.XPGain({ xp = 100, max = 1000, level = 10 }, { xp = 600, max = 1100, level = 11 }), 1500)
end)

-- Progress

test("experience gains are counted and shown on both experience bars", function()
	now = now + 60
	xp.xp = 1500
	_FIRE("PLAYER_XP_UPDATE", "player")
	eq(char().xp.total, 500)
	local s = P:XPStatus(now)
	near(s.perHour, 500 / R.MIN_SPAN * 3600)
	eq(s.remaining, 8500)
	truthy(s.ttl, "time to level")
	local text = label(1, 4):GetText()
	truthy(text and text:find("15k xp/h", 1, true), "xp/h on the bar: " .. tostring(text))
	truthy(text:find("to level", 1, true), "time to level on the bar")
	eq(label(2, 4):GetText(), text, "second container shows the same")
	truthy(label(1, 4):IsShown(), "label shown")
end)

test("other units' experience events are ignored", function()
	_FIRE("PLAYER_XP_UPDATE", "pet")
	eq(char().xp.total, 500)
end)

test("a level-up before UnitLevel catches up is counted once", function()
	now = now + 30
	xp.xp = 200                         -- bar started over: 8500 left + 200
	_FIRE("PLAYER_XP_UPDATE", "player")
	eq(char().xp.total, 500 + 8700)
	xp.level, xp.max = 21, 11000        -- now the level updates
	_FIRE("PLAYER_LEVEL_UP", 21)
	_FIRE("PLAYER_XP_UPDATE", "player")
	eq(char().xp.total, 500 + 8700)
end)

test("reputation: first reading is a baseline, then gains count", function()
	watched = { factionID = 72, name = "Stormwind", currentStanding = 3500, currentReactionThreshold = 3000,
		nextReactionThreshold = 9000, reaction = 5 }
	_FIRE("UPDATE_FACTION")
	eq(char().faction, 72)
	eq(char().rep.total, 0)
	eq(label(1, 1):IsShown(), false, "no rep text without a rate")
	now = now + 10
	watched.currentStanding = 3750
	_FIRE("UPDATE_FACTION")
	eq(char().rep.total, 250)
	local s = P:RepStatus(now)
	eq(s.remaining, 5250)
	local text = label(1, 1):GetText()
	truthy(text and text:find("rep/h", 1, true) and text:find("to Honored", 1, true), "rep text: " .. tostring(text))
end)

test("reputation losses are not gains", function()
	watched.currentStanding = 3700
	_FIRE("UPDATE_FACTION")
	eq(char().rep.total, 250)
	watched.currentStanding = 3800 -- back up from the lower value
	_FIRE("UPDATE_FACTION")
	eq(char().rep.total, 350)
end)

test("a different watched faction starts over", function()
	watched = { factionID = 47, name = "Ironforge", currentStanding = 100, nextReactionThreshold = 3000, reaction = 4 }
	_FIRE("UPDATE_FACTION")
	eq(char().faction, 47)
	eq(char().rep.total, 0)
	eq(label(1, 1):IsShown(), false)
end)

test("toggling a setting hides its bar text", function()
	SlashCmdList.KABOBOQOL("xp")
	eq(ns.db.settings.xp, false)
	eq(label(1, 4):IsShown(), false)
	SlashCmdList.KABOBOQOL("xp")
	truthy(label(1, 4):IsShown(), "back on")
end)

test("hover tooltip lists the rates", function()
	tooltipLines = {}
	local xpBar = containers[1].bars[4]
	xpBar.scripts.OnEnter(xpBar)
	eq(GameTooltip.owner, xpBar)
	eq(tooltipLines[1][1], "Last 15 min")
	eq(tooltipLines[2][1], "This session")
	eq(tooltipLines[3][1], "Gained")
	eq(tooltipLines[4][1], "Level 22")
	xpBar.scripts.OnLeave(xpBar)
	eq(GameTooltip:IsShown(), false)
end)

test("after 15 minutes without gains only the hour is left; after an hour, nothing", function()
	now = now + R.WINDOW + 1
	eq(P:HasRecent(now), true)
	B:Refresh()
	local s = P:XPStatus(now)
	eq(s.perHour, 0)
	truthy(s.hourPerHour > 0, "hour rate")
	truthy(s.hasHour, "more than 15 minutes of gains")
	local text = label(1, 4):GetText()
	truthy(text and text:find("^hour: ") and text:find("to level", 1, true), "hour-only text: " .. tostring(text))
	now = now + R.HOUR
	eq(P:HasRecent(now), false)
	B:Refresh()
	eq(label(1, 4):IsShown(), false)
	truthy(P:XPStatus(now).session > 0, "session rate stays")
end)

test("a /reload keeps the session; a long break starts a new one", function()
	local start = char().xp.start
	_FIRE("PLAYER_LOGOUT")
	now = now + 30
	_FIRE("PLAYER_LOGIN")
	eq(char().xp.start, start, "kept after a reload")
	_FIRE("PLAYER_LOGOUT")
	now = now + R.WINDOW + 1
	_FIRE("PLAYER_LOGIN")
	eq(char().xp.start, now, "new session after a break")
	eq(char().xp.total, 0)
end)

test("reset starts counting from now", function()
	now = now + 5
	SlashCmdList.KABOBOQOL("reset")
	eq(char().xp.start, now)
end)

test("bar text formats", function()
	eq(B.XPText(nil), nil)
	eq(B.XPText({ perHour = 0 }), nil)
	eq(B.XPText({ perHour = 12345 }), "12.3k xp/h")
	eq(B.XPText({ perHour = 12345, ttl = 2520 }), "12.3k xp/h" .. B.SEP .. "42m to level")
	eq(B.RepText({ perHour = 320, ttl = 4200, reaction = 4 }), "320 rep/h" .. B.SEP .. "1h 10m to Friendly")
	eq(B.RepText({ perHour = 320, ttl = 60, reaction = 8 }), "320 rep/h" .. B.SEP .. "1m to next")
	eq(B.RepText({ perHour = 320 }), "320 rep/h")
	-- the hour estimate joins once counting is older than 15 minutes, when it differs
	local both = { perHour = 12345, ttl = 2520, hourPerHour = 9800, hourTtl = 3300, hasHour = true }
	eq(B.XPText(both), "12.3k xp/h" .. B.SEP .. "42m to level (hour: 55m)")
	both.hasHour = false
	eq(B.XPText(both), "12.3k xp/h" .. B.SEP .. "42m to level")
	eq(B.XPText({ perHour = 12345, ttl = 2520, hourTtl = 2530, hasHour = true }), "12.3k xp/h" .. B.SEP .. "42m to level")
	eq(B.XPText({ perHour = 0, hourPerHour = 9800, hourTtl = 3300, hasHour = true }), "hour: 9.8k xp/h" .. B.SEP .. "55m to level")
end)

test("tooltip has both estimates once counting is older than 15 minutes", function()
	local s = { perHour = 12345, ttl = 2520, hourPerHour = 9800, hourTtl = 3300, hasHour = true,
		session = 9000, gained = 20000, elapsed = 4000, remaining = 8640 }
	local lines = B.TooltipLines(s, "xp", "Level 24")
	local labels = {}
	for i, l in ipairs(lines) do labels[i] = l[1] end
	eq(table.concat(labels, "|"), "Last 15 min|Last hour|This session|Gained|Level 24|   at the last 15 min|   at the last hour")
	eq(lines[2][2], "9.8k xp/h")
	eq(lines[6][2], "42m"); eq(lines[7][2], "55m")
	s.hasHour = false
	eq(#B.TooltipLines(s, "xp", "Level 24"), 5)
end)
