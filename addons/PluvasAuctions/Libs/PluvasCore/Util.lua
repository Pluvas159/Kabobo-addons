-- PluvasCore: small helpers for data and game info. Nothing here calls a window-bound API.
local _, ns = ...

-- Walks t[k1][k2]..., creating missing tables, and returns the last one. Returns nil when a key
-- is nil (e.g. ns.realmKey before login), so callers can bail out instead of writing junk.
function ns.Ensure(t, ...)
	for i = 1, select("#", ...) do
		local k = select(i, ...)
		if k == nil then return nil end
		local child = t[k]
		if type(child) ~= "table" then
			child = {}
			t[k] = child
		end
		t = child
	end
	return t
end

-- Splits a string on a single-character separator, keeping empty fields.
function ns.Split(s, sep)
	local out, start = {}, 1
	while true do
		local i = s:find(sep, start, true)
		if not i then
			out[#out + 1] = s:sub(start)
			return out
		end
		out[#out + 1] = s:sub(start, i - 1)
		start = i + 1
	end
end

-- time() of local midnight for the given time (defaults to now).
function ns.DayStart(t)
	local d = date("*t", t or time())
	d.hour, d.min, d.sec = 0, 0, 0
	return time(d)
end

-- pcall that returns the first result, or nil when fn is missing or raises.
function ns.Try(fn, ...)
	if not fn then return nil end
	local ok, value = pcall(fn, ...)
	if ok then return value end
	return nil
end

-- This character's professions: name -> { skill, max, line }, and whether any were listed.
-- Reads spellbook skill data only, which is safe at any time. `any` is false early in a login,
-- before the client has profession data, so never prune saved data on an empty result.
function ns:KnownProfessions()
	local out, any = {}, false
	if not (GetProfessions and GetProfessionInfo) then return out, false end
	for _, index in pairs({ GetProfessions() }) do
		local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
		if name then
			out[name] = { skill = rank, max = maxRank, line = skillLine }
			any = true
		end
	end
	return out, any
end
