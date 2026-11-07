-- Kabobo's Auctions: the label/value lines shown in item tooltips and in the profession window.
--
-- One place builds every line, so the tooltip and the profession panel always agree. Lines are
-- { "label", "value", color = key } (see PUI.AddTooltipLines / PUI.LinePanel). Nothing here
-- calls a game API: lines come from saved data and plain item info.
local _, ns = ...
local Lines = ns:NewModule("Lines")
local P, C = ns.Pricing, ns.Crafting
local PUI = ns.KaboboUI
local Money = PUI.MoneyIcons

Lines.HISTORY_DAYS = 14
Lines.MAX_MATS = 10   -- mat lines before "+N more"

local function muted(text) return PUI.Color(text, "muted") end

-- " (5d old)" in the warning color for a price last seen at `seen` once it counts as old (see
-- Pricing.StaleAge), else "".
function Lines.OldNote(seen, now)
	local age = P.StaleAge(seen, now)
	if not age then return "" end
	return PUI.Color(" (" .. PUI.Age(age) .. " old)", "warn")
end

-- "Label (x20)" for a stack, plain "Label" for one item.
local function forStack(label, count)
	if count > 1 then return label .. muted(" (x" .. count .. ")") end
	return label
end

-- "12s 50c (2 mats unpriced)", or a muted note when no mat has a price. seen = when the oldest
-- AH price behind the cost was last seen, flagged once it is old.
function Lines.CostText(cost, missing, seen, now)
	if not cost then return muted("no prices for mats") end
	local text = Money(cost)
	if missing > 0 then text = text .. muted(" (" .. missing .. " mats unpriced)") end
	if now then text = text .. Lines.OldNote(seen, now) end
	return text
end

-- One indented line per base mat, most expensive first: "   6x Linen Cloth    6s", with a
-- muted "vendor" after mats priced from a vendor and an old-price note when `now` is given.
function Lines.AddMats(out, mats, max, now)
	max = max or Lines.MAX_MATS
	for i = 1, math.min(#mats, max) do
		local m = mats[i]
		local value = muted("no price")
		if m.cost then
			value = Money(m.cost) .. (m.vendor and muted(" vendor") or "")
			if now then value = value .. Lines.OldNote(m.seen, now) end
		end
		out[#out + 1] = { "   " .. C.FormatQty(m.qty) .. "x " .. P.ItemName(m.id), value, color = "soft" }
	end
	if #mats > max then
		out[#out + 1] = { "   +" .. (#mats - max) .. " more", " ", color = "muted" }
	end
	return out
end

-- AH market, lowest and history lines, plus what selling `count` units brings in after the AH
-- cut and the deposit.
function Lines.AddPrices(out, entry, count, now, showHistory)
	local age = Lines.OldNote(entry.t, now)
	if age == "" and entry.t then age = muted(" (" .. PUI.Age(now - entry.t) .. " ago)") end
	out[#out + 1] = { "AH market", Money(entry.m) .. age }
	if entry.n then
		out[#out + 1] = { "AH lowest", Money(entry.n) .. (entry.q and muted(" x" .. entry.q) or "") }
	end
	if showHistory then
		local avg, days = P.HistoryAverage(entry, now, Lines.HISTORY_DAYS)
		if avg and days > 1 then
			out[#out + 1] = { "AH " .. Lines.HISTORY_DAYS .. "-day avg", Money(avg) .. muted(" (" .. days .. "d)") }
		end
	end
	local unit = entry.m or entry.n
	if unit then
		local _, _, net = P.NetProceeds(unit, count, P.DEPOSIT)
		if count > 1 then out[#out + 1] = { "AH market x" .. count, Money(unit * count) } end
		out[#out + 1] = { forStack("After cut & deposit", count), Money(net) }
	end
	return out
end

-- What the mats for `count` crafted items cost right now, each at the cheaper of AH and vendor.
function Lines.AddCraftCost(out, recipe, count, showMats, now)
	local cost, missing, mats = C.CostForItems(recipe, count, C.MatPrice, C.RecipeOf)
	out[#out + 1] = { forStack("Mats cost", count), Lines.CostText(cost, missing, C.OldestSeen(mats), now) }
	if showMats then Lines.AddMats(out, mats, nil, now) end
	return out
end

-- Every line of an item tooltip. item = { key, id, name, count }; s = ns.db.settings.
function Lines.Tooltip(item, s, now)
	local out = {}
	local entry = P:Get(item.key)
	if entry then Lines.AddPrices(out, entry, item.count, now, s.tooltipHistory) end
	local vendor = ns.Vendor:Get(item.id)
	if vendor then
		out[#out + 1] = { forStack("Buy from vendor", item.count), Money(math.floor(vendor * item.count + 0.5)) }
	end
	if s.tooltipCraft and item.id then
		local recipe = C:RecipeFor(item.id)
		if recipe then Lines.AddCraftCost(out, recipe, item.count, s.matsList, now) end
	end
	if s.tooltipLedger and item.name then
		local avg, qty = ns.Ledger:AverageSale(item.name)
		if avg then out[#out + 1] = { "You sold at", Money(avg) .. muted(" (" .. qty .. " sold)") } end
	end
	return out
end

-- Lines for one craft in the profession window, from a Crafting.CraftSummary result. With
-- `now`, old prices are flagged.
function Lines.Craft(summary, showMats, now)
	local out = {}
	local per = ""
	if summary.yield and summary.yield ~= 1 then
		per = muted(" (per craft, makes " .. string.format("%g", summary.yield) .. ")")
	end
	out[#out + 1] = { "Mats cost" .. per, Lines.CostText(summary.cost, summary.missing, summary.matsSeen, now) }
	if showMats ~= false then Lines.AddMats(out, summary.mats or {}, nil, now) end
	if summary.value then
		out[#out + 1] = { "Sells for (AH)", Money(summary.value) .. (now and Lines.OldNote(summary.seen, now) or "") }
		out[#out + 1] = { "After cut & deposit", Money(summary.net) }
		if summary.profit then out[#out + 1] = { "Profit", PUI.SignedMoney(summary.profit, true) } end
	else
		out[#out + 1] = { "Sells for (AH)", muted("no AH price yet") }
	end
	-- From Kabobo's Professions, when it is loaded and the item can be disenchanted.
	if summary.de then
		if summary.de > 0 then
			local note = summary.deMissing > 0 and muted(" (" .. summary.deMissing .. " mats unpriced)") or ""
			if now then note = note .. Lines.OldNote(summary.deSeen, now) end
			out[#out + 1] = { "Disenchants for", Money(summary.de) .. note }
			if summary.deProfit then
				out[#out + 1] = { "Profit if disenchanted", PUI.SignedMoney(summary.deProfit, true) }
			end
		else
			out[#out + 1] = { "Disenchants for", muted("no AH prices for its mats yet") }
		end
	end
	return out
end
