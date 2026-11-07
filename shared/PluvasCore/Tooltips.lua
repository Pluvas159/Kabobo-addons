-- PluvasCore: lines in item tooltips.
--
-- Tooltips are a hot path: what runs here must read only saved data and plain item info
-- (C_Item.GetItemInfo and friends), never a window-bound API (see docs/forever-client.md).
local _, ns = ...

-- The item a tooltip shows: its link (when the tooltip has one) and its itemID. data is the
-- table TooltipDataProcessor passes. Returns nil when the tooltip shows no item.
function ns.TooltipItem(tooltip, data)
	local link
	if tooltip and tooltip.GetItem then
		local ok, _, l = pcall(tooltip.GetItem, tooltip)
		if ok then link = l end
	end
	if not link and data and data.hyperlink then link = data.hyperlink end
	local id = data and data.id
	if not id and type(link) == "string" then id = tonumber(link:match("item:(%d+)")) end
	if not link and not id then return nil end
	return link, id
end

-- Calls fn(tooltip, link, itemID, data) after the game builds any item tooltip. Guarded: a bug
-- turns the feature off for the session instead of erroring on every hover. Returns false when
-- the client has no TooltipDataProcessor.
function ns:OnItemTooltip(name, fn)
	if not (TooltipDataProcessor and Enum and Enum.TooltipDataType) then
		ns:Debug("TooltipDataProcessor not available,", name, "disabled")
		return false
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns:Guard(name, function(tooltip, data)
		if not tooltip or not tooltip.AddDoubleLine then return end
		local link, id = ns.TooltipItem(tooltip, data)
		if link or id then fn(tooltip, link, id, data) end
	end))
	return true
end
