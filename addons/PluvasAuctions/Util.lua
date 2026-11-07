-- Pluvas' Auctions: formatting and small helpers. No game state is touched here.
local _, ns = ...

local floor, abs = math.floor, math.abs

local GOLD = "|cffffd700"
local SILVER = "|cffc7c7cf"
local COPPER = "|cffeda55f"

local function groupDigits(n)
	if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
	local s = tostring(n)
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

-- Colored "12g 34s 56c" text. Zero parts are left out; nil prints a dash.
function ns.Money(copper)
	if copper == nil then return "|cff808080-|r" end
	copper = floor(copper + 0.5)
	local sign = ""
	if copper < 0 then
		sign = "-"
		copper = -copper
	end
	local g = floor(copper / 10000)
	local s = floor((copper % 10000) / 100)
	local c = copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = groupDigits(g) .. GOLD .. "g|r" end
	if s > 0 then parts[#parts + 1] = s .. SILVER .. "s|r" end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. COPPER .. "c|r" end
	return sign .. table.concat(parts, " ")
end

-- "45s", "12m", "3h", "5d"
function ns.Age(seconds)
	if not seconds or seconds < 0 then return "?" end
	if seconds < 60 then return floor(seconds) .. "s" end
	if seconds < 3600 then return floor(seconds / 60) .. "m" end
	if seconds < 86400 then return floor(seconds / 3600) .. "h" end
	return floor(seconds / 86400) .. "d"
end

-- "mm:ss"
function ns.Clock(seconds)
	seconds = math.max(0, floor(seconds))
	return string.format("%d:%02d", floor(seconds / 60), seconds % 60)
end

-- time() of local midnight for the given time (defaults to now).
function ns.DayStart(t)
	local d = date("*t", t or time())
	d.hour, d.min, d.sec = 0, 0, 0
	return time(d)
end

-- Split a string on a single-character separator, keeping empty fields.
function ns.Split(s, sep)
	local out = {}
	local start = 1
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
