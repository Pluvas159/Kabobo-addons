-- Progress: experience and reputation of the watched faction, counted into Rates trackers.
-- Data only: it announces ProgressChanged and never touches the UI.
local _, ns = ...
local P = ns:NewModule("Progress")
local R = ns.Rates

local lastXP, lastRep -- previous readings, to turn the absolute values into gains

local function charData()
	return ns.Ensure(ns.db, "chars", ns.charKey)
end

-- { xp, max, level }, or nil when there is no experience to earn (max level, XP turned off).
function P.ReadXP()
	if GameRulesUtil and GameRulesUtil.IsPlayerAtEffectiveMaxLevel and GameRulesUtil.IsPlayerAtEffectiveMaxLevel() then
		return nil
	end
	if IsXPUserDisabled and IsXPUserDisabled() then return nil end
	local max = UnitXPMax("player")
	if not max or max <= 0 then return nil end
	return { xp = UnitXP("player") or 0, max = max, level = UnitLevel("player") or 0 }
end

-- { id, name, standing, top, reaction } of the faction on the reputation bar, or nil.
-- standing counts from the bottom of Hated, so it only grows as reputation is gained, across
-- standings; top is where the next standing begins.
function P.ReadRep()
	local get = C_Reputation and C_Reputation.GetWatchedFactionData
	local d = get and get()
	if not d or not d.factionID or d.factionID == 0 or not d.currentStanding then return nil end
	return {
		id = d.factionID,
		name = d.name,
		standing = d.currentStanding,
		top = d.nextReactionThreshold,
		reaction = d.reaction,
	}
end

function P:Reset()
	local now = time()
	local c = charData()
	c.xp, c.rep = R.New(now), R.New(now)
	c.faction = lastRep and lastRep.id
	lastXP = P.ReadXP()
	ns:Send("ProgressChanged")
end

function P:OnLogin()
	local now = time()
	local c = charData()
	-- Carry on after a /reload or a quick relog; a longer break starts a new session.
	local fresh = not c.saved or now - c.saved > R.WINDOW or type(c.xp) ~= "table" or type(c.rep) ~= "table"
	if fresh then
		c.xp, c.rep, c.faction = R.New(now), R.New(now), nil
	end
	lastXP = P.ReadXP()
	lastRep = P.ReadRep() -- often not loaded yet at login; the first UPDATE_FACTION sets it
	if lastRep and c.faction ~= lastRep.id then
		c.rep, c.faction = R.New(now), lastRep.id
	end
end

function P:OnLogout()
	charData().saved = time()
end

local function onXP()
	local now = time()
	local reading = P.ReadXP()
	if not reading then
		lastXP = nil
		return
	end
	if lastXP then
		local gain = R.XPGain(lastXP, reading)
		-- The bar started over but UnitLevel has not caught up yet: remember the level-up, so the
		-- reading with the new level does not count it again.
		if reading.xp < lastXP.xp and reading.level <= lastXP.level then
			reading.level = lastXP.level + 1
		end
		lastXP = reading
		if gain > 0 then
			R.Add(charData().xp, gain, now)
			ns:Send("ProgressChanged")
		end
	else
		lastXP = reading
	end
end

local function onRep()
	local now = time()
	local reading = P.ReadRep()
	local c = charData()
	if not reading then
		lastRep = nil
		return
	end
	if c.faction ~= reading.id then
		-- A different faction on the bar: its rate starts from here.
		c.rep, c.faction = R.New(now), reading.id
		lastRep = reading
		ns:Send("ProgressChanged")
		return
	end
	local gain = lastRep and lastRep.id == reading.id and (reading.standing - lastRep.standing) or 0
	lastRep = reading
	if gain > 0 then
		R.Add(c.rep, gain, now)
	end
	-- Also on no gain: the standing or the name on the bar may have changed.
	ns:Send("ProgressChanged")
end

ns:On("PLAYER_XP_UPDATE", function(unit)
	if unit and unit ~= "player" then return end
	onXP()
end)
ns:On("PLAYER_LEVEL_UP", onXP)
ns:On("UPDATE_FACTION", onRep)

-- Status for display ---------------------------------------------------------------

-- Anything gained in the last hour, i.e. a rate that is still changing.
function P:HasRecent(now)
	local c = ns.db and ns.charKey and ns.db.chars[ns.charKey]
	if not c or not c.xp then return false end
	R.Prune(c.xp, now)
	R.Prune(c.rep, now)
	return #c.xp.t > 0 or #c.rep.t > 0
end

local function status(tracker, now, remaining)
	local perHour, recent = R.Recent(tracker, now, R.WINDOW)
	local hourPerHour = R.Recent(tracker, now, R.HOUR)
	local elapsed = now - tracker.start
	local history = R.History(tracker, now)
	return {
		perHour = perHour,          -- last 15 minutes
		recent = recent,            -- gained in the last 15 minutes
		ttl = R.TimeTo(remaining, perHour),
		-- The last hour. Until there are more than 15 minutes of gains it is the same as the above.
		hourPerHour = hourPerHour,
		hourTtl = R.TimeTo(remaining, hourPerHour),
		hasHour = history > R.WINDOW,
		session = R.Session(tracker, now),
		gained = tracker.total,
		elapsed = elapsed,
		remaining = remaining,
	}
end

-- Experience status, or nil when there is no experience to earn.
function P:XPStatus(now)
	local c = ns.db.chars[ns.charKey]
	local reading = lastXP or P.ReadXP()
	if not c or not c.xp or not reading then return nil end
	local s = status(c.xp, now, reading.max - reading.xp)
	s.level = reading.level
	return s
end

-- Reputation status of the watched faction, or nil when no faction is watched.
function P:RepStatus(now)
	local c = ns.db.chars[ns.charKey]
	local reading = lastRep or P.ReadRep()
	if not c or not c.rep or not reading or c.faction ~= reading.id then return nil end
	local remaining = reading.top and (reading.top - reading.standing) or nil
	local s = status(c.rep, now, remaining)
	s.name = reading.name
	s.reaction = reading.reaction
	return s
end

-- " 12.3k/h, level 24 in 42m; last hour 9.8k/h, 55m; session 8.1k/h" for chat.
function P.Describe(s, goal)
	local PUI = ns.KaboboUI
	local line = " " .. PUI.Short(s.perHour) .. "/h"
	if s.ttl then line = line .. ", " .. goal .. " in " .. PUI.Duration(s.ttl) end
	if s.hasHour then
		line = line .. "; last hour " .. PUI.Short(s.hourPerHour) .. "/h"
		if s.hourTtl then line = line .. ", " .. PUI.Duration(s.hourTtl) end
	end
	return line .. "; session " .. PUI.Short(s.session) .. "/h"
end

function P:PrintStatus()
	local now = time()
	local xp, rep = P:XPStatus(now), P:RepStatus(now)
	if xp then
		ns:Print("experience" .. P.Describe(xp, "level " .. (xp.level + 1)))
	end
	if rep then
		ns:Print(rep.name .. P.Describe(rep, "next standing"))
	end
	if not xp and not rep then ns:Print("no experience to earn and no faction on the reputation bar.") end
end
