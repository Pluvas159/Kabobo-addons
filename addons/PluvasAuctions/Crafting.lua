-- Pluvas' Auctions: what this character can craft, and what the mats cost on the AH.
--
-- Recipes are read only while a profession window is open (TRADE_SKILL_LIST_UPDATE), the one
-- context the C_TradeSkillUI functions are built for. Tooltips read only the saved copy and
-- never call C_TradeSkillUI, so a client quirk cannot take a tooltip down with it.
--
-- Saved layout: db.crafts[realmKey][charName][professionID] = { name = "Tailoring",
--   r = { [outputItemID] = recipe } }
-- recipe string: "min:max|itemID*qty,itemID*qty" (min/max = items made per craft)
local _, ns = ...
local C = ns:NewModule("Crafting")
local P = ns.Pricing

local SCAN_BATCH = 40   -- recipes read per frame

-- Recipe strings ----------------------------------------------------------

-- mats: array of { itemID, quantity }
function C.Encode(minYield, maxYield, mats)
	local parts = {}
	for i = 1, #mats do
		parts[i] = math.floor(mats[i][1]) .. "*" .. math.floor(mats[i][2])
	end
	return math.floor(minYield) .. ":" .. math.floor(maxYield) .. "|" .. table.concat(parts, ",")
end

-- Returns minYield, maxYield, mats (array of { itemID, quantity }), or nil.
function C.Decode(s)
	if type(s) ~= "string" then return nil end
	local lo, hi, list = s:match("^(%d+):(%d+)|(.*)$")
	if not lo then return nil end
	local mats = {}
	for id, qty in list:gmatch("(%d+)%*(%d+)") do
		mats[#mats + 1] = { tonumber(id), tonumber(qty) }
	end
	return tonumber(lo), tonumber(hi), mats
end

C.MAX_DEPTH = 8   -- deepest chain of crafted mats followed (bolt -> cloth -> ... )

-- Cost of one unit of an item. If recipeOf(itemID) gives a recipe (the character can craft it),
-- it is priced from its own mats, recursively down to the base mats; otherwise priceOf(itemID)
-- is used. A crafted mat whose own mats cannot all be priced falls back to its AH price when it
-- has one. Cycles (A from B, B from A) stop at the AH price.
-- Returns cost (a float, nil when nothing could be priced), the number of unpriced base mats,
-- and the base mats used for one unit: { [itemID] = quantity } (quantities can be fractional
-- when a craft makes several items).
function C.UnitCost(itemID, priceOf, recipeOf, seen, depth)
	seen, depth = seen or {}, depth or 0
	local recipe = recipeOf and not seen[itemID] and depth < C.MAX_DEPTH and recipeOf(itemID)
	local lo, hi, mats = C.Decode(recipe)
	if not lo then
		local price = priceOf(itemID)
		return price, price and 0 or 1, { [itemID] = 1 }
	end

	seen[itemID] = true
	local total, missing, priced, used = 0, 0, false, {}
	for i = 1, #mats do
		local qty = mats[i][2]
		local cost, m, sub = C.UnitCost(mats[i][1], priceOf, recipeOf, seen, depth + 1)
		if cost then
			total = total + cost * qty
			priced = true
		end
		missing = missing + m
		for id, q in pairs(sub) do used[id] = (used[id] or 0) + q * qty end
	end
	seen[itemID] = nil

	local yield = (lo + hi) / 2
	if yield <= 0 then yield = 1 end
	for id, q in pairs(used) do used[id] = q / yield end
	if missing == 0 then return total / yield, 0, used end
	if depth > 0 then
		local price = priceOf(itemID)
		if price then return price, 0, { [itemID] = 1 } end
	end
	if not priced then return nil, missing, used end
	return total / yield, missing, used
end

-- { [itemID] = qty } scaled by `times` -> array of { id, qty, unit, cost }, most expensive
-- first and unpriced mats last. unit/cost are nil for unpriced mats.
local function matList(used, times, priceOf)
	local list = {}
	for id, q in pairs(used) do
		local qty = q * times
		local unit = priceOf(id)
		list[#list + 1] = { id = id, qty = qty, unit = unit, cost = unit and math.floor(unit * qty + 0.5) }
	end
	table.sort(list, function(a, b)
		if (a.cost ~= nil) ~= (b.cost ~= nil) then return a.cost ~= nil end
		if a.cost and a.cost ~= b.cost then return a.cost > b.cost end
		return a.id < b.id
	end)
	return list
end

-- Mats cost of one craft. priceOf(itemID) returns copper per unit or nil; recipeOf(itemID)
-- (optional) returns a recipe string for mats the character can craft, which are then priced
-- from their own mats.
-- Returns cost (nil when no mat has a price), number of unpriced base mats, the average number
-- of items one craft makes, and the base mats for one craft (see matList).
function C.CostPerCraft(recipe, priceOf, recipeOf)
	local lo, hi = C.Decode(recipe)
	if not lo then return nil, 0, 1, {} end
	local yield = (lo + hi) / 2
	if yield <= 0 then yield = 1 end
	-- UnitCost on a stand-in item whose recipe is this one gives cost per item.
	local SELF = -1
	local function recipeOfOrSelf(id)
		if id == SELF then return recipe end
		return recipeOf and recipeOf(id)
	end
	local perItem, _, used = C.UnitCost(SELF, priceOf, recipeOfOrSelf)
	local mats = matList(used, yield, priceOf)
	local missing = 0
	for i = 1, #mats do
		if not mats[i].unit then missing = missing + 1 end
	end
	if not perItem then return nil, missing, yield, mats end
	return math.floor(perItem * yield + 0.5), missing, yield, mats
end

-- Mats cost of `count` crafted items (a craft that makes 2 items halves the cost per item).
-- Returns cost, number of unpriced mats, and the base mats for those items (see matList).
function C.CostForItems(recipe, count, priceOf, recipeOf)
	local cost, missing, yield, mats = C.CostPerCraft(recipe, priceOf, recipeOf)
	local scale = (count or 1) / yield
	for i = 1, #mats do
		local m = mats[i]
		m.qty = m.qty * scale
		m.cost = m.unit and math.floor(m.unit * m.qty + 0.5)
	end
	if not cost then return nil, missing, mats end
	return math.floor(cost * scale + 0.5), missing, mats
end

-- Mats cost of one crafted item.
function C.CostPerItem(recipe, priceOf, recipeOf)
	local cost, missing = C.CostForItems(recipe, 1, priceOf, recipeOf)
	return cost, missing
end

-- "6", "1.5", "0.33": mat quantities, which can be fractional when a craft makes several items.
function C.FormatQty(q)
	return string.format("%g", math.floor(q * 100 + 0.5) / 100)
end

-- Everything the profession window shows for one craft:
-- { cost, missing, yield, mats, value, net, profit }. value/net/profit are nil when the crafted
-- item has no AH price; profit is nil when the cost is unknown. The output is sold as one
-- auction, so one flat deposit.
function C.CraftSummary(recipe, priceOf, recipeOf, outputPrice)
	local cost, missing, yield, mats = C.CostPerCraft(recipe, priceOf, recipeOf)
	local r = { cost = cost, missing = missing, yield = yield, mats = mats }
	if outputPrice then
		local made = math.floor(yield + 0.5)
		if made < 1 then made = 1 end
		local gross, _, net = P.NetProceeds(outputPrice, made, P.DEPOSIT)
		r.value, r.net = gross, net
		if cost then r.profit = net - cost end
	end
	return r
end

-- Turn a C_TradeSkillUI recipe schematic into (outputItemID, recipe string), or nil.
-- Only basic reagents count: optional and finishing reagents are not part of the base cost.
function C.FromSchematic(schematic)
	if type(schematic) ~= "table" or not schematic.outputItemID then return nil end   -- enchants make no item
	local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
	local mats = {}
	for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
		local isBasic
		if slot.reagentType ~= nil and basic ~= nil then
			isBasic = slot.reagentType == basic
		else
			isBasic = slot.required ~= false
		end
		local first = slot.reagents and slot.reagents[1]
		if isBasic and first and first.itemID and (slot.quantityRequired or 0) > 0 then
			mats[#mats + 1] = { first.itemID, slot.quantityRequired }
		end
	end
	if #mats == 0 then return nil end
	local lo = schematic.quantityMin or 1
	local hi = schematic.quantityMax or lo
	return schematic.outputItemID, C.Encode(lo, hi, mats)
end

-- Recipe lookup for C.UnitCost / C.CostPerCraft: what this character can craft.
function C.RecipeOf(itemID)
	return C:RecipeFor(itemID)
end

-- AH price per unit of a mat: market value, or the lowest buyout when there is no market value.
function C.MatPrice(itemID)
	local entry = P:Get(tostring(itemID))
	return entry and (entry.m or entry.n) or nil
end

-- Saved data --------------------------------------------------------------

-- This character's professions: { [professionID] = { name, r = { [outputItemID] = recipe } } }.
-- nil before login.
function C:CharTable()
	return ns.Ensure(ns.db.crafts, ns.realmKey, ns.charName)
end

-- Recipe string for the item if this character can craft it, else nil.
function C:RecipeFor(itemID)
	local me = itemID and C:CharTable()
	if not me then return nil end
	for _, prof in pairs(me) do
		local r = prof.r and prof.r[itemID]
		if r then return r end
	end
	return nil
end

-- Store one profession's recipes. A complete read replaces what was saved; an incomplete one
-- (some client calls failed) only adds to it, so a client hiccup cannot wipe good data.
function C:Store(professionID, name, recipes, complete)
	local me = C:CharTable()
	if not me then return end
	local old = me[professionID]
	if not complete and old and old.r then
		for id, r in pairs(recipes) do old.r[id] = r end
		old.name = name or old.name
		return
	end
	me[professionID] = { name = name, r = recipes }
end

-- Drop professions this character no longer has. Only runs when the client lists at least one
-- profession, so a login before profession data arrives cannot wipe everything.
function C:PruneProfessions()
	local known, any = ns:KnownProfessions()
	local me = any and C:CharTable()
	if not me then return end
	-- Match on ID or name, since the base profession ID and the skill line are not confirmed to
	-- be the same number on Forever.
	local have = {}
	for name, p in pairs(known) do
		have[name] = true
		if p.line then have[p.line] = true end
	end
	for professionID, prof in pairs(me) do
		if not have[professionID] and not (prof.name and have[prof.name]) then
			me[professionID] = nil
		end
	end
end

-- Reading the profession window ---------------------------------------------
--
-- C_TradeSkillUI is only called while the trade skill session is open, for the character's own
-- professions (not linked, guild or NPC crafting views).

local trade = ns:Session("TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE")
local scanning = false

-- The recipe the profession window shows, for the profession window panel.
function C:ReadSchematic(recipeID)
	local TS = C_TradeSkillUI
	-- Blizzard may draw the recipe before our TRADE_SKILL_SHOW handler runs, so also accept a
	-- shown profession window.
	local open = trade.open or (ProfessionsFrame and ProfessionsFrame.IsShown and ProfessionsFrame:IsShown())
	if not (TS and open and recipeID) then return nil end
	return C.FromSchematic(ns.Try(TS.GetRecipeSchematic, recipeID, false))
end

local function viewingOwnProfession(TS, api)
	return trade.open and not (api:Call(TS.IsTradeSkillLinked) or api:Call(TS.IsTradeSkillGuild)
		or api:Call(TS.IsNPCCrafting))
end

function C:Scan()
	local TS = C_TradeSkillUI
	if scanning or not (TS and TS.GetAllRecipeIDs) then return end
	local api = ns.NewCaller()
	if not viewingOwnProfession(TS, api) then return end
	local base = api:Call(TS.GetBaseProfessionInfo)
	local professionID = base and base.professionID
	if not professionID or professionID == 0 then return end
	local ids = api:Call(TS.GetAllRecipeIDs)
	if type(ids) ~= "table" or #ids == 0 then return end

	scanning = true
	local recipes, count = {}, 0
	ns:Spread({
		name = "Crafting scan",
		count = #ids,
		size = SCAN_BATCH,
		-- The window can close between frames; drop the read rather than call the API closed.
		alive = function() return trade.open end,
		step = function(i)
			local info = api:Call(TS.GetRecipeInfo, ids[i])
			if not (info and info.learned) then return end
			local out, recipe = C.FromSchematic(api:Call(TS.GetRecipeSchematic, ids[i], false))
			if out then
				recipes[out] = recipe
				count = count + 1
			end
		end,
		done = function(ok)
			scanning = false
			if not ok then return end   -- keep what was saved; the next window update retries
			C:Store(professionID, base.professionName, recipes, api.failures == 0)
			if api.failures > 0 then ns:Debug("crafting: " .. api.failures .. " recipe reads failed") end
			ns:Debug("crafting: stored", count, "recipes for profession", professionID)
		end,
	})
end

-- The list fires several updates while it fills; read it once it settles. Also fires when a
-- recipe is learned while the window is open.
local scanSoon = ns:Debounce("Crafting scan", 0.5, function() C:Scan() end)
ns:On("TRADE_SKILL_SHOW", scanSoon)
ns:On("TRADE_SKILL_LIST_UPDATE", scanSoon)

function C:OnLogin()
	C:PruneProfessions()
end
