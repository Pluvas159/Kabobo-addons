-- Pluvas' Auctions: price lines in item tooltips.
local _, ns = ...
local T = ns:NewModule("Tooltip")
local P = ns.Pricing

local LABEL = { 0.13, 0.72, 0.81 }   -- addon accent color for line labels
local GRAY = "|cff808080"

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
		local ok, loc = pcall(C_Item.GetItemLocation, data.guid)
		if ok and loc and loc.IsValid and loc:IsValid() then
			local okCount, n = pcall(C_Item.GetStackCount, loc)
			if okCount and type(n) == "number" and n > 0 then item.count = n end
		end
	end
	return item
end

-- The deposit is a flat P.DEPOSIT per auction. Never ask C_AuctionHouse.CalculateItemDeposit
-- here: on Forever it crashes the whole client (ACCESS_VIOLATION, which pcall cannot catch)
-- when called from a tooltip.

local function addLine(tooltip, label, value)
	tooltip:AddDoubleLine(label, value, LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
end

local MAX_MAT_LINES = 8

-- One indented line per base mat: "  6x Linen Cloth    6s".
function T:AddMatLines(tooltip, mats)
	for i = 1, math.min(#mats, MAX_MAT_LINES) do
		local m = mats[i]
		local left = "   " .. ns.Crafting.FormatQty(m.qty) .. "x " .. P.ItemName(m.id)
		local right = m.cost and ns.MoneyIcons(m.cost) or (GRAY .. "no price|r")
		tooltip:AddDoubleLine(left, right, 0.85, 0.85, 0.85, 1, 1, 1)
	end
	if #mats > MAX_MAT_LINES then
		tooltip:AddDoubleLine("   +" .. (#mats - MAX_MAT_LINES) .. " more", " ", 0.5, 0.5, 0.5, 1, 1, 1)
	end
end

function T:AddLines(tooltip, item)
	local s = ns.db.settings
	local now = time()
	local entry = P:Get(item.key)
	local name = item.name

	if entry then
		local age = entry.t and (GRAY .. " (" .. ns.Age(now - entry.t) .. " ago)|r") or ""
		addLine(tooltip, "AH market", ns.MoneyIcons(entry.m) .. age)
		if entry.n then
			local qty = entry.q and (GRAY .. " x" .. entry.q .. "|r") or ""
			addLine(tooltip, "AH lowest", ns.MoneyIcons(entry.n) .. qty)
		end
		if s.tooltipHistory then
			local avg, days = P.HistoryAverage(entry, now, 14)
			if avg and days > 1 then
				addLine(tooltip, "AH 14-day avg", ns.MoneyIcons(avg) .. GRAY .. " (" .. days .. "d)|r")
			end
		end

		-- What selling what you hold would bring in: the whole stack, minus the AH cut and deposit.
		local unit = entry.m or entry.n
		if unit then
			local count = item.count
			local _, _, net = P.NetProceeds(unit, count, P.DEPOSIT)
			if count > 1 then
				addLine(tooltip, "AH market x" .. count, ns.MoneyIcons(unit * count))
			end
			local label = "After cut & deposit"
			if count > 1 then label = label .. GRAY .. " (x" .. count .. ")|r" end
			addLine(tooltip, label, ns.MoneyIcons(net))
		end
	end

	-- Items this character can craft: what the mats for the stack cost on the AH right now.
	if s.tooltipCraft and item.id then
		local C = ns.Crafting
		local recipe = C:RecipeFor(item.id)
		if recipe then
			local count = item.count
			local cost, missing, mats = C.CostForItems(recipe, count, C.MatPrice, C.RecipeOf)
			local label = "Mats cost (AH)"
			if count > 1 then label = label .. GRAY .. " (x" .. count .. ")|r" end
			local value
			if cost then
				value = ns.MoneyIcons(cost)
				if missing > 0 then
					value = value .. GRAY .. " (" .. missing .. " mats unpriced)|r"
				end
			else
				value = GRAY .. "no AH prices for mats|r"
			end
			addLine(tooltip, label, value)
			if s.matsList then T:AddMatLines(tooltip, mats) end
		end
	end

	if s.tooltipLedger and name and ns.realmKey then
		local avg, qty = ns.Ledger.AverageSale(ns.Ledger:Transactions(), name)
		if avg then
			addLine(tooltip, "You sold at", ns.MoneyIcons(avg) .. GRAY .. " (" .. qty .. " sold)|r")
		end
	end
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
	local avg = P.HistoryAverage(entry, now, 14)
	ns:Print(string.format("%s market %s, lowest %s (x%s), 14-day avg %s, seen %s ago.",
		text, ns.Money(entry.m), ns.Money(entry.n), tostring(entry.q or "?"),
		ns.Money(avg), ns.Age(now - (entry.t or now))))
end
