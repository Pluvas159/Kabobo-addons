-- Pluvas' Auctions: price lines in item tooltips, and /pa price.
--
-- The tooltip hook reads only saved data and plain item info (see Lines.lua). Never ask
-- C_AuctionHouse.CalculateItemDeposit here: on Forever it crashes the whole client
-- (ACCESS_VIOLATION, which pcall cannot catch) when called from a tooltip. The deposit is a
-- flat Pricing.DEPOSIT per auction.
local _, ns = ...
local T = ns:NewModule("Tooltip")
local P, Lines = ns.Pricing, ns.Lines
local PUI = ns.PluvasUI

-- What the tooltip shows: item key, name, itemID, and (for a real item in your bags or bank)
-- its stack size.
local function tooltipItem(tooltip, data)
	local link
	if tooltip and tooltip.GetItem then
		local ok, _, l = pcall(tooltip.GetItem, tooltip)
		if ok then link = l end
	end
	if not link and data and data.hyperlink then link = data.hyperlink end
	local key = P.ItemKeyFromLink(link)
	if not key and data and data.id then key = P.ItemKey(data.id) end
	if not key then return nil end

	local item = {
		key = key,
		name = link and link:match("%[(.-)%]"),
		id = (data and data.id) or tonumber(key:match("^%d+")),
		count = 1,
	}
	-- Only real items carry a GUID; links in chat, AH rows and vendor items do not.
	if data and data.guid and C_Item and C_Item.GetItemLocation then
		local loc = ns.Try(C_Item.GetItemLocation, data.guid)
		if loc and loc.IsValid and loc:IsValid() then
			local n = ns.Try(C_Item.GetStackCount, loc)
			if type(n) == "number" and n > 0 then item.count = n end
		end
	end
	return item
end

-- Adds the price lines for item ({ key, id, name, count }) to a tooltip.
function T:AddLines(tooltip, item)
	PUI.AddTooltipLines(tooltip, Lines.Tooltip(item, ns.db.settings, time()))
end

function T:OnLogin()
	if not (TooltipDataProcessor and Enum and Enum.TooltipDataType) then
		ns:Debug("TooltipDataProcessor not available, tooltips disabled")
		return
	end
	-- Guarded: a bug here turns the price lines off for the session instead of erroring on
	-- every hover.
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns:Guard("Tooltip prices", function(tooltip, data)
		if not ns.db.settings.tooltip or not tooltip.AddDoubleLine then return end
		local item = tooltipItem(tooltip, data)
		if item then T:AddLines(tooltip, item) end
	end))
end

-- /pa price <link>
function T:PrintPrice(text)
	local key = P.ItemKeyFromLink(text)
	if not key then
		ns:Print("usage: /pa price <shift-click an item>")
		return
	end
	local entry = P:Get(key)
	if not entry then
		ns:Print(text .. ": no price data yet.")
		return
	end
	local now = time()
	local avg = P.HistoryAverage(entry, now, Lines.HISTORY_DAYS)
	ns:Print(string.format("%s market %s, lowest %s (x%s), %d-day avg %s, seen %s ago.",
		text, PUI.Money(entry.m), PUI.Money(entry.n), tostring(entry.q or "?"), Lines.HISTORY_DAYS,
		PUI.Money(avg), PUI.Age(now - (entry.t or now))))
end
