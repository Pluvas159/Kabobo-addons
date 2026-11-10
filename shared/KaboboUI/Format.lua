-- KaboboUI: display formatting for money and time, so every addon writes them the same way.
local _, ns = ...
local UI = ns.KaboboUI

local floor = math.floor

local function groupDigits(n)
	if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
	local s = tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (s:gsub("^,", ""))
end

local LETTERS, ICONS = {}, {}
for i = 1, 3 do
	LETTERS[i] = UI.Color(UI.Coins.letters[i], UI.Coins.colors[i])
	-- 0:0 sizes the coin to the line's font height; the x offset of 2 is the gap Blizzard uses.
	ICONS[i] = "|T" .. UI.Coins.icons[i] .. ":0:0:2:0|t"
end

local function formatMoney(copper, suffix)
	if copper == nil then return UI.Color("-", "muted") end
	copper = floor(copper + 0.5)
	local sign = ""
	if copper < 0 then
		sign, copper = "-", -copper
	end
	local g, s, c = floor(copper / 10000), floor((copper % 10000) / 100), copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = groupDigits(g) .. suffix[1] end
	if s > 0 then parts[#parts + 1] = s .. suffix[2] end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. suffix[3] end
	return sign .. table.concat(parts, " ")
end

-- "12g 34s 56c" with colored letters. Zero parts are left out; nil prints a muted dash.
function UI.Money(copper)
	return formatMoney(copper, LETTERS)
end

-- Same as UI.Money with coin icons, for tooltips and panels.
function UI.MoneyIcons(copper)
	return formatMoney(copper, ICONS)
end

-- A gain or a loss: green "+" or red "-" before the amount, nothing before zero.
-- icons = true uses coin icons.
function UI.SignedMoney(copper, icons)
	local fmt = icons and UI.MoneyIcons or UI.Money
	if copper > 0 then return UI.Color("+", "good") .. fmt(copper) end
	if copper < 0 then return UI.Color("-", "bad") .. fmt(-copper) end
	return fmt(0)
end

-- "45s", "12m", "3h", "5d"; "?" for nil or negative.
function UI.Age(seconds)
	if not seconds or seconds < 0 then return "?" end
	if seconds < 60 then return floor(seconds) .. "s" end
	if seconds < 3600 then return floor(seconds / 60) .. "m" end
	if seconds < 86400 then return floor(seconds / 3600) .. "h" end
	return floor(seconds / 86400) .. "d"
end

-- "1h 5m", "2d 3h", "12m", "45s"; "?" for nil or negative. Two units at most, for durations
-- people read at a glance (time to level).
function UI.Duration(seconds)
	if not seconds or seconds < 0 then return "?" end
	local s = floor(seconds)
	if s < 60 then return s .. "s" end
	if s < 3600 then return floor(s / 60) .. "m" end
	local big, small, a, b
	if s < 86400 then
		big, small, a, b = floor(s / 3600), floor((s % 3600) / 60), "h", "m"
	else
		big, small, a, b = floor(s / 86400), floor((s % 86400) / 3600), "d", "h"
	end
	if small == 0 then return big .. a end
	return big .. a .. " " .. small .. b
end

-- Large counts in a few characters: 950, 1.2k, 12.3k, 123k, 1.2M. Rounds down, so a value
-- never reads as the next unit (999,999 is "999k", not "1000k").
function UI.Short(n)
	if not n then return "?" end
	local sign = ""
	if n < 0 then sign, n = "-", -n end
	local div, unit
	if n < 1000 then return sign .. floor(n) end
	if n < 1000000 then div, unit = 1000, "k" else div, unit = 1000000, "M" end
	local v = n / div
	if v >= 100 then return sign .. floor(v) .. unit end
	local tenths = floor(v * 10)
	if tenths % 10 == 0 then return sign .. floor(tenths / 10) .. unit end
	return sign .. floor(tenths / 10) .. "." .. (tenths % 10) .. unit
end

-- "m:ss" countdown.
function UI.Clock(seconds)
	seconds = math.max(0, floor(seconds))
	return string.format("%d:%02d", floor(seconds / 60), seconds % 60)
end
