-- PluvasUI: display formatting for money and time, so every addon writes them the same way.
local _, ns = ...
local UI = ns.PluvasUI

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

-- "m:ss" countdown.
function UI.Clock(seconds)
	seconds = math.max(0, floor(seconds))
	return string.format("%d:%02d", floor(seconds / 60), seconds % 60)
end
