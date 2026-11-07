-- Pluvas' Auctions: price lines in item tooltips.
local _, ns = ...
local T = ns:NewModule("Tooltip")
local P = ns.Pricing

local LABEL = { 0.13, 0.72, 0.81 }   -- addon accent color for line labels
local GRAY = "|cff808080"

local function itemKeyAndName(tooltip, data)
	local link
	if tooltip and tooltip.GetItem then
		local ok, _, l = pcall(tooltip.GetItem, tooltip)
		if ok then link = l end
	end
	if not link and data and data.hyperlink then link = data.hyperlink end
	local key = P.ItemKeyFromLink(link)
	if not key and data and data.id then key = P.ItemKey(data.id) end
	local name = link and link:match("%[(.-)%]")
	return key, name
end

local function addLine(tooltip, label, value)
	tooltip:AddDoubleLine(label, value, LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
end

function T:AddLines(tooltip, key, name)
	local s = ns.db.settings
	local now = time()
	local entry = P:Get(key)

	if entry then
		local age = entry.t and (GRAY .. " (" .. ns.Age(now - entry.t) .. " ago)|r") or ""
		addLine(tooltip, "AH market", ns.Money(entry.m) .. age)
		if entry.n then
			local qty = entry.q and (GRAY .. " x" .. entry.q .. "|r") or ""
			addLine(tooltip, "AH lowest", ns.Money(entry.n) .. qty)
		end
		if s.tooltipHistory then
			local avg, days = P.HistoryAverage(entry, now, 14)
			if avg and days > 1 then
				addLine(tooltip, "AH 14-day avg", ns.Money(avg) .. GRAY .. " (" .. days .. "d)|r")
			end
		end
	end

	if s.tooltipLedger and name and ns.realmKey then
		local avg, qty = ns.Ledger.AverageSale(ns.Ledger:Transactions(), name)
		if avg then
			addLine(tooltip, "You sold at", ns.Money(avg) .. GRAY .. " (" .. qty .. " sold)|r")
		end
	end
end

function T:OnLogin()
	if not (TooltipDataProcessor and Enum and Enum.TooltipDataType) then
		ns:Debug("TooltipDataProcessor not available, tooltips disabled")
		return
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		if not ns.db.settings.tooltip or not tooltip.AddDoubleLine then return end
		local key, name = itemKeyAndName(tooltip, data)
		if key then T:AddLines(tooltip, key, name) end
	end)
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
	local avg = P.HistoryAverage(entry, now, 14)
	ns:Print(string.format("%s market %s, lowest %s (x%s), 14-day avg %s, seen %s ago.",
		text, ns.Money(entry.m), ns.Money(entry.n), tostring(entry.q or "?"),
		ns.Money(avg), ns.Age(now - (entry.t or now))))
end
