-- Kabobo's Auctions: the shopping list for a recipe: what to buy, bought with the auction
-- house's own Buy Now, then what to craft, crafted with the profession window's own Create.
--
-- SH.Plan walks the recipe tree: each mat is taken from your bags first (as counted when the
-- list was made), and the rest is either bought, or crafted when you know its recipe and crafting
-- it is cheaper than buying it (the same rule as Crafting.UnitCost). So a dagger needing Copper
-- Bars lists Copper Ore to buy and "Copper Bar" to craft. Mats a vendor sells cheaper are listed
-- but not bought here.
--
-- Steps run in order: every buy, then every craft, deepest first (bars before the dagger). Crafts
-- are counted from UNIT_SPELLCAST_SUCCEEDED (a recipe ID is its spell ID), or from the bag count
-- of the crafted item for recipes saved before recipe IDs were kept.
--
-- On this client the purchase functions (StartCommoditiesPurchase, ConfirmCommoditiesPurchase,
-- PlaceBid) are protected: only Blizzard's own auction house buttons may call them, even from a
-- click on an addon button (ADDON_ACTION_BLOCKED). So the list never buys. It:
--   - puts the next mat's name in the auction house search box (Find) and, with
--     settings.autoFill, runs the search and fills in the quantity once you click the item
--   - for a craft step, selects the recipe (C_TradeSkillUI.OpenRecipe) and fills in the craft
--     count (autoFill), or puts its name in the profession window's search box
--   It only fills inputs: Buy Now and Create are always your clicks. Should the game ever block
--   them after the list filled something in (ADDON_ACTION_BLOCKED), autoFill turns itself off.
--   - reads the listings the auction house shows for that mat and says how many to buy and what
--     that costs under the price cap (settings.buyCap x the item's average price of the days
--     before today, or its market value while it has no history)
--   - warns when the auction house's price quote is above the cap, before you confirm
--   - counts what you buy (hooksecurefunc on the purchase functions, which does not taint them)
--     and moves on to the next mat
--
-- States: idle | done. Sends ShoppingChanged whenever the list, the current step or the advice
-- changes.
local ADDON, ns = ...
local SH = ns:NewModule("Shopping")
local C, P = ns.Crafting, ns.Pricing

SH.list = nil     -- { output, recipe, crafts, bags, mats = buy rows, steps = craft rows } (see SH.Plan)
SH.state = "idle"
SH.current = nil  -- the step being done: a buy row or a craft row
SH.offer = nil    -- advice for the current mat: { qty, total } under the cap
SH.message = nil  -- last status line for the window

local bought = {}    -- [itemID] = quantity bought for this list
local made = {}      -- [itemID] = crafts done for this list
local skipped = {}   -- [itemID] = true: skipped with the Skip button
local pending = nil  -- { id, qty }: a commodity purchase confirmed, waiting for the answer
local pendingBids = {} -- [auctionID] = { id, qty }: item buyouts waiting for the answer

-- Pure logic ----------------------------------------------------------------------

SH.CAP_DAYS = 14   -- the cap follows the average market value of this many days before today

-- What the price cap is based on: the average daily market value of the CAP_DAYS days before
-- today, or nil without any. Today is left out because searching an item records today's
-- listings, so a cap from today's value would rise with a price spike.
function SH.CapBase(entry, now)
	if not (entry and entry.h) then return nil end
	local today = P.DayIndex(now)
	local sum, count = 0, 0
	for day, s in pairs(entry.h) do
		if day < today and day >= today - SH.CAP_DAYS then
			local m, _, c = P.ParseDay(s)
			if m and c and c > 0 then sum, count = sum + m, count + 1 end
		end
	end
	if count == 0 then return nil end
	return math.floor(sum / count + 0.5)
end

-- Highest price per unit allowed: ratio x market, or nil when there is no market value.
function SH.Cap(market, ratio)
	if not market or market <= 0 then return nil end
	return math.floor(market * (ratio or 1.2))
end

-- Whether a mat you have a recipe for is crafted rather than bought: Crafting.UnitCost decides
-- (it buys when the mat is cheaper on the AH, or its own mats cannot all be priced).
local function crafted(id, priceOf, recipeOf)
	local _, _, used = C.UnitCost(id, priceOf, recipeOf, nil, 1)
	return not (used and used[id] and next(used, next(used)) == nil)
end

-- What `crafts` crafts of `recipe` (making outputID) take. Each mat comes from your bags first
-- (ownedOf(itemID); one pool for the whole tree), then is bought or crafted (see crafted()).
-- Returns
--   buy   = { { id, need, have, vendor }, ... } the most expensive first, unpriced last
--   steps = { { id, kind = "craft", crafts, makes, need, have, depth }, ... } deepest first,
--           the recipe itself (depth 0) last. crafts = how many times to craft it, makes = items
--           per craft (average), need/have = items needed / taken from bags.
-- `need` is rounded up: a craft that makes 2 needs half the mats per item, but you cannot buy half
-- a cloth.
function SH.Plan(recipe, crafts, priceOf, recipeOf, ownedOf, outputID)
	local pool = {}
	local function take(id, want)
		if pool[id] == nil then pool[id] = ownedOf and ownedOf(id) or 0 end
		local got = math.min(pool[id], want)
		pool[id] = pool[id] - got
		return got
	end
	local buy, buyOf, steps, stepOf = {}, {}, {}, {}

	local function expand(rec, times, depth, seen)
		local _, _, mats = C.Decode(rec)
		for _, mat in ipairs(mats or {}) do
			local id = mat[1]
			local need = math.ceil(mat[2] * times - 1e-6)
			local have = take(id, need)
			local sub = recipeOf and not seen[id] and depth < C.MAX_DEPTH and recipeOf(id)
			if sub and crafted(id, priceOf, recipeOf) then
				local lo, hi = C.Decode(sub)
				local makes = (lo + hi) / 2
				if makes <= 0 then makes = 1 end
				local step = stepOf[id]
				if not step then
					step = { id = id, kind = "craft", crafts = 0, makes = makes, need = 0, have = 0, depth = 0 }
					stepOf[id] = step
					steps[#steps + 1] = step
				end
				step.need, step.have = step.need + need, step.have + have
				step.depth = math.max(step.depth, depth + 1)
				local n = math.ceil((need - have) / makes - 1e-6)
				if n > 0 then
					step.crafts = step.crafts + n
					seen[id] = true
					expand(sub, n, depth + 1, seen)
					seen[id] = nil
				end
			else
				local row = buyOf[id]
				if not row then
					local _, source = priceOf(id)
					row = { id = id, need = 0, have = 0, vendor = source == "vendor" or nil }
					buyOf[id] = row
					buy[#buy + 1] = row
				end
				row.need, row.have = row.need + need, row.have + have
			end
		end
	end

	local lo, hi = C.Decode(recipe)
	if not lo then return buy, steps end
	expand(recipe, crafts, 0, {})
	local makes = (lo + hi) / 2
	steps[#steps + 1] = { id = outputID, kind = "craft", crafts = crafts, makes = makes > 0 and makes or 1,
		need = 0, have = 0, depth = 0 }

	local function cost(m)
		local unit = priceOf(m.id)
		return unit and unit * m.need
	end
	table.sort(buy, function(a, b)
		local ca, cb = cost(a), cost(b)
		if (ca ~= nil) ~= (cb ~= nil) then return ca ~= nil end
		if ca and ca ~= cb then return ca > cb end
		return a.id < b.id
	end)
	table.sort(steps, function(a, b)
		if a.depth ~= b.depth then return a.depth > b.depth end
		return (a.id or 0) < (b.id or 0)
	end)
	return buy, steps
end

-- How many of a commodity to buy: cheapest listings first, only those at or under the cap,
-- up to `remaining`. listings: array of { unitPrice, quantity, own }, cheapest first.
-- Returns quantity and expected total (0, 0 when nothing qualifies).
function SH.CommodityOffer(listings, remaining, cap)
	local qty, total = 0, 0
	for i = 1, #listings do
		local l = listings[i]
		if qty >= remaining or l[1] > cap then break end
		if not l[3] then
			local take = math.min(l[2], remaining - qty)
			qty, total = qty + take, total + take * l[1]
		end
	end
	return qty, total
end

-- Which item auction to buy: the cheapest per unit at or under the cap, not your own. Among
-- those, one that does not buy more than `remaining` wins over one that does.
-- auctions: array of { auctionID, buyout (what the buyout costs), quantity, own }.
function SH.ItemOffer(auctions, remaining, cap)
	local best, bestFits, bestUnit
	for i = 1, #auctions do
		local a = auctions[i]
		local unit = a[2] / a[3]
		if not a[4] and unit <= cap then
			local fits = a[3] <= remaining
			if not best or (fits and not bestFits) or (fits == bestFits and unit < bestUnit) then
				best, bestFits, bestUnit = a, fits, unit
			end
		end
	end
	return best
end

-- What is left of a step: units to buy, or crafts to do.
function SH.Remaining(m)
	if m.kind == "craft" then return math.max(0, m.crafts - (made[m.id] or 0)) end
	return math.max(0, m.need - m.have - (bought[m.id] or 0))
end

function SH.Bought(itemID)
	return bought[itemID] or 0
end

function SH.Made(itemID)
	return made[itemID] or 0
end

-- "NotEnoughMoney" -> "Not enough money": the name of an Enum.AuctionHouseError code.
function SH.ErrorText(code)
	local E = Enum and Enum.AuctionHouseError
	if E then
		for name, value in pairs(E) do
			if value == code then
				return (name:gsub("(%l)(%u)", function(a, b) return a .. " " .. b:lower() end))
			end
		end
	end
	return "error " .. tostring(code)
end

function SH.Skipped(itemID)
	return skipped[itemID] and true or false
end

-- State ---------------------------------------------------------------------------

local Money = function(c) return ns.KaboboUI.Money(c) end

local function set(state, message)
	SH.state = state
	SH.message = message
	ns:Send("ShoppingChanged")
end

-- nil when you can pay `cost`, else the message saying you cannot.
local function cannotAfford(cost)
	local money = GetMoney and GetMoney()
	if not money or not cost or cost <= money then return nil end
	return "Not enough money: this costs " .. Money(cost) .. ", you have " .. Money(money) .. "."
end

local function owned(itemID)
	local count = (C_Item and C_Item.GetItemCount) or GetItemCount
	return count and ns.Try(count, itemID, false) or 0
end

-- The cap for an item: its average of the days before today (SH.CapBase), else its market value.
local function capFor(itemID)
	local base = SH.CapBase(P:Get(tostring(itemID)), time()) or C.AHPrice(itemID)
	return SH.Cap(base, ns.db.settings.buyCap)
end

local function matOf(itemID)
	if not SH.list then return nil end
	for _, m in ipairs(SH.list.mats) do
		if m.id == itemID then return m end
	end
	return nil
end

-- A step still to do: a buy row not sold by a vendor, or a craft row, with something left.
local function buyable(m)
	return not m.vendor and SH.Remaining(m) > 0
end

-- Every step in order: the buy rows, then the craft rows.
local function sequence()
	local seq = {}
	for _, m in ipairs(SH.list.mats) do seq[#seq + 1] = m end
	for _, m in ipairs(SH.list.steps or {}) do seq[#seq + 1] = m end
	return seq
end

-- The first step still to do after `from` (wrapping round, `from` itself last), not skipped
-- first; then a skipped one.
local function nextMat(from)
	local mats = sequence()
	local start = 0
	for i, m in ipairs(mats) do
		if m == from then start = i end
	end
	for pass = 1, 2 do
		for k = 1, #mats do
			local m = mats[(start + k - 1) % #mats + 1]
			if buyable(m) and (pass == 2 or not skipped[m.id]) then return m end
		end
	end
	return nil
end

local function searchBox()
	local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
	return bar and bar.SearchBox
end

-- Puts `name` in the auction house search box, ready for Enter. Only the text: the search
-- itself stays Blizzard's, so its buttons are not tainted. Returns nil, or why it could not.
function SH.FillSearch(name)
	if not ns.Scanner:IsOpen() then return "Open the auction house to search for " .. name .. "." end
	local box = searchBox()
	if not (box and box:IsVisible()) then
		return "Go to the Browse tab of the auction house, then click " .. name .. " again."
	end
	box:SetText(name)
	box:SetFocus()
	ns:Debug("search box:", name)
	return nil
end

local function recipeSearchBox()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	local list = page and page.RecipeList
	return list and list.SearchBox
end

-- The profession window shows the profession named `prof` (or any, when prof is nil).
local function professionOpen(prof)
	local box = recipeSearchBox()
	if not (box and box:IsVisible()) then return false end
	if not prof then return true end
	local TS = C_TradeSkillUI
	local base = TS and TS.GetBaseProfessionInfo and ns.Try(TS.GetBaseProfessionInfo)
	return not (base and base.professionName) or base.professionName == prof
end

-- What to do for the current step.
local function autoFill()
	return ns.db.settings.autoFill and true or false
end

local function instructions(m)
	local name = P.ItemName(m.id)
	if m.kind == "craft" then
		if autoFill() and m.recipeID then
			return "Click Craft: it selects " .. name .. " and fills in " .. SH.Remaining(m)
				.. ". Check it and click Create."
		end
		if not professionOpen(m.prof) then
			return "Open your " .. (m.prof or "profession") .. " window, then click Craft."
		end
		return "Click Craft, then click " .. name .. " in the list, set " .. SH.Remaining(m)
			.. " and click Create."
	end
	if not ns.Scanner:IsOpen() then return "Open the auction house to buy." end
	if autoFill() then
		return "Click Find: it searches " .. name .. ". Click it in the results, check the quantity ("
			.. SH.Remaining(m) .. ") and click Buy Now."
	end
	return "Click Find, press Enter, click " .. name .. " in the results, set the quantity to "
		.. SH.Remaining(m) .. " and click Buy Now."
end

-- Bag count of the crafted item when a craft step without a recipe ID becomes current, so crafts
-- can be counted from the bags.
local function startBagCount(m)
	if m and m.kind == "craft" and not m.recipeID then
		m.base = owned(m.id) - (made[m.id] or 0) * m.makes
	end
end

local function choose(m)
	SH.current = m
	SH.offer = nil
	if not m then return set("done", "Everything on the list is bought and crafted.") end
	startBagCount(m)
	set("idle", instructions(m))
end

-- " Next: craft Copper Bar." after a step is done.
local function nextLine(n)
	if not n then return "" end
	return " Next: " .. (n.kind == "craft" and "craft " or "buy ") .. P.ItemName(n.id) .. "."
end

-- Public --------------------------------------------------------------------------

-- New list for `crafts` crafts of the item. Returns false when this character cannot craft it.
-- keepBought keeps what was bought so far and the bag counts from the first list (same recipe,
-- another number of crafts), so mail collected in between is not counted twice.
function SH:Start(outputItemID, crafts, keepBought)
	local recipe = C:RecipeFor(outputItemID)
	if not recipe then return false end
	crafts = math.max(1, math.floor(crafts or 1))
	-- Bags are counted once per list (and kept for another number of crafts).
	local keep = keepBought and SH.list
	local bags = keep and SH.list.bags or {}
	if not keep then
		bought, made, skipped = {}, {}, {}
	end
	local function ownedOf(id)
		if bags[id] == nil then bags[id] = owned(id) end
		return bags[id]
	end
	local current = SH.current
	local mats, steps = SH.Plan(recipe, crafts, C.MatPrice, C.RecipeOf, ownedOf, outputItemID)
	for _, step in ipairs(steps) do step.recipeID, step.prof = C:CraftInfo(step.id) end
	SH.list = {
		output = outputItemID,
		recipe = recipe,
		crafts = crafts,
		bags = bags,
		mats = mats,
		steps = steps,
	}
	local m
	for _, s in ipairs(sequence()) do
		if current and s.id == current.id and s.kind == current.kind then m = s end
	end
	choose(m and buyable(m) and m or nextMat())
	return true
end

-- Same recipe, another number of crafts. What was bought so far still counts.
function SH:SetCrafts(crafts)
	if SH.list then SH:Start(SH.list.output, crafts, true) end
end

function SH:Clear()
	SH.list, SH.current, SH.offer = nil, nil, nil
	pending = nil
	set("idle", nil)
end

-- Puts the step's recipe in the profession window's search box. Like the auction house, only
-- the text: picking the recipe and Create stay Blizzard's.
local lastAuto = 0   -- time() autoFill last filled something in Blizzard's windows
SH.AUTO_WINDOW = 120 -- a block within this many seconds of that is blamed on it

local function usedAuto(what)
	lastAuto = time()
	ns:Debug("shopping: autofill", what)
end

local function findRecipe(m)
	local name = P.ItemName(m.id)
	local TS = C_TradeSkillUI
	if autoFill() and m.recipeID and TS and TS.OpenRecipe then
		-- The client selects the recipe itself; the count is filled in once it shows (OnRecipeShown).
		usedAuto("open recipe " .. m.recipeID)
		ns.Try(TS.OpenRecipe, m.recipeID)
		return set("idle", "Selected " .. name .. ": check the count (" .. SH.Remaining(m) .. ") and click Create.")
	end
	if not professionOpen(m.prof) then
		return set("idle", "Open your " .. (m.prof or "profession") .. " window, then click Craft.")
	end
	recipeSearchBox():SetText(name)
	ns:Debug("shopping: recipe search", m.id, m.recipeID)
	set("idle", "Click " .. name .. " in the list, set " .. SH.Remaining(m) .. " and click Create.")
end

-- Makes `m` (default: the current step) the one being done, and puts its name in the search box
-- of the auction house (buy) or the profession window (craft). The search itself is Blizzard's.
function SH:Find(m)
	if not SH.list then return end
	m = m or SH.current
	if not m or m.header then return end
	if m.kind == "craft" then
		if SH.Remaining(m) == 0 then
			return set(SH.state, "No more " .. P.ItemName(m.id) .. " to craft.")
		end
		if m ~= SH.current then choose(m) end
		return findRecipe(m)
	end
	if m.vendor then
		return set(SH.state, P.ItemName(m.id) .. " is cheaper at a vendor: buy it there.")
	end
	if SH.Remaining(m) == 0 then
		return set(SH.state, "You already have all the " .. P.ItemName(m.id) .. " you need.")
	end
	if m ~= SH.current then choose(m) end
	if not ns.Scanner:IsOpen() then return set("idle", "Open the auction house to buy.") end
	if not (searchBox() and searchBox():IsVisible()) then
		return set("idle", "Go to the Browse tab of the auction house, then click Find.")
	end
	SH.FillSearch(P.ItemName(m.id))
	local bar = AuctionHouseFrame.SearchBar
	if autoFill() and bar and bar.StartSearch then
		usedAuto("search " .. m.id)
		ns.Try(bar.StartSearch, bar)
		return set("idle", "Click " .. P.ItemName(m.id) .. " in the results: the quantity fills in. Check it and click Buy Now.")
	end
	set("idle", "Press Enter, click " .. P.ItemName(m.id) .. " in the results, set the quantity to "
		.. SH.Remaining(m) .. " and click Buy Now.")
end

-- Filling in Blizzard's inputs (autoFill) -------------------------------------------

-- Sets the quantity in the auction house's commodity buy frame when it shows `itemID`.
local function fillQuantity(itemID, qty)
	local frame = AuctionHouseFrame and AuctionHouseFrame.CommoditiesBuyFrame
	local display = frame and frame.BuyDisplay
	if not (autoFill() and display and display.SetQuantitySelected and qty and qty > 0) then return false end
	if display.GetItemID and ns.Try(display.GetItemID, display) ~= itemID then return false end
	usedAuto("quantity " .. itemID .. " x" .. qty)
	ns.Try(display.SetQuantitySelected, display, qty)
	return true
end

-- After the auction house opens an item in its commodity buy frame (hooked below): the current
-- mat gets the quantity still to buy (the cap advice lowers it once the listings are read).
function SH.OnBuyFrameItem(itemID)
	local m = SH.current
	if not (SH.list and m and m.kind ~= "craft" and m.id == itemID) then return end
	if fillQuantity(itemID, SH.Remaining(m)) then
		set("idle", "Quantity set to " .. SH.Remaining(m) .. ": check it and click Buy Now.")
	end
end

-- After the profession window shows a recipe (hooked below): the current craft step gets its
-- count.
function SH.OnRecipeShown(recipeID)
	local m = SH.current
	if not (autoFill() and SH.list and m and m.kind == "craft" and m.recipeID and m.recipeID == recipeID) then return end
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	local box = page and page.CreateMultipleInputBox
	if not (box and box.SetValue) then return end
	usedAuto("craft count " .. recipeID .. " x" .. SH.Remaining(m))
	ns.Try(box.SetValue, box, SH.Remaining(m))
	set("idle", "Set to " .. SH.Remaining(m) .. " " .. P.ItemName(m.id) .. ": check it and click Create.")
end

-- Hooked after Blizzard's code ran (hooksecurefunc), and filled in on the next frame.
ns:WhenLoaded("Blizzard_AuctionHouseUI", function()
	local frame = AuctionHouseFrame and AuctionHouseFrame.CommoditiesBuyFrame
	if not (frame and frame.SetItemIDAndPrice) then
		return ns:Debug("commodity buy frame not found, no quantity fill")
	end
	hooksecurefunc(frame, "SetItemIDAndPrice", ns:Guard("Shopping quantity", function(_, itemID)
		C_Timer.After(0, ns:Guard("Shopping quantity", function() SH.OnBuyFrameItem(itemID) end))
	end))
end)

ns:WhenLoaded("Blizzard_Professions", function()
	local form = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
	if not (form and form.Init) then return end
	hooksecurefunc(form, "Init", ns:Guard("Shopping craft count", function(_, recipeInfo)
		local id = recipeInfo and recipeInfo.recipeID
		C_Timer.After(0, ns:Guard("Shopping craft count", function() SH.OnRecipeShown(id) end))
	end))
end)

-- Leaves the current mat for later and goes to the next one.
function SH:Skip()
	local m = SH.current
	if not (SH.list and m) then return end
	skipped[m.id] = true
	choose(nextMat(m))
end

-- What the main button says.
function SH:ButtonText()
	local m = SH.current
	if SH.state == "done" or not m then return "Done" end
	if m.kind == "craft" then return "Craft " .. P.ItemName(m.id) .. " (" .. SH.Remaining(m) .. "x)" end
	return "Find " .. P.ItemName(m.id)
end

-- What a row of the list is worth: `need` x its price per unit, or nil without a price. A buy
-- row uses its price (vendor or AH, the cheaper); a craft row what crafting one costs (from its
-- own mats, see Crafting.UnitCost), so mats you already have still count. The recipe itself
-- (need 0) has none.
function SH.MatCost(m, priceOf, recipeOf)
	priceOf = priceOf or C.MatPrice
	if m.kind == "craft" then
		if not m.need or m.need == 0 then return nil end
		local unit = C.UnitCost(m.id, priceOf, recipeOf or C.RecipeOf)
		return unit and math.floor(m.need * unit + 0.5) or nil
	end
	local unit = priceOf(m.id)
	return unit and m.need * unit or nil
end

-- Totals for the list: { cost, left, missing, net, profit }.
--   cost    what all the mats of the crafts are worth, including what you already have (the
--           same mats cost as the crafts window, times the crafts), nil when nothing is priced
--   missing mats without a price (left out of cost)
--   left    what the mats still to buy cost (vendor mats included)
--   net     what the crafted items sell for after the AH cut and deposit, nil without a price
--   profit  net - cost, nil without a price for the crafted item or its mats
function SH.Totals(list, priceOf, outputPrice, recipeOf)
	priceOf = priceOf or C.MatPrice
	local t = { left = 0 }
	for _, m in ipairs(list.mats) do
		local unit = priceOf(m.id)
		if unit then t.left = t.left + SH.Remaining(m) * unit end
	end
	local s = C.CraftSummary(list.recipe, priceOf, recipeOf or C.RecipeOf, (outputPrice or C.AHPrice)(list.output))
	t.cost = s.cost and s.cost * list.crafts or nil
	t.missing = s.missing or 0
	if s.net then
		t.net = s.net * list.crafts
		if t.cost then t.profit = t.net - t.cost end
	end
	return t
end

-- Purchases (made by the auction house's own buttons) -------------------------------

-- Counts a purchase of `qty` x `itemID` when it is on the list, and moves on when that mat is done.
local function count(itemID, qty)
	local m = matOf(itemID)
	if not m then return end
	bought[itemID] = (bought[itemID] or 0) + qty
	ns:Debug("shopping: bought", itemID, qty)
	if SH.current == m and SH.Remaining(m) == 0 then
		local n = nextMat(m)
		choose(n)
		if n then SH.message = "Bought " .. qty .. "x " .. P.ItemName(itemID) .. "." .. nextLine(n) end
		return ns:Send("ShoppingChanged")
	end
	if SH.current == m then
		SH.offer = nil
		return set("idle", "Bought " .. qty .. "x. Still " .. SH.Remaining(m) .. " to buy: search again.")
	end
	ns:Send("ShoppingChanged")
end

-- Crafts ---------------------------------------------------------------------------

-- Counts `n` crafts of the step `m`, and moves on when it is done.
local function countCrafts(m, n)
	made[m.id] = (made[m.id] or 0) + n
	ns:Debug("shopping: crafted", m.id, n)
	if SH.current == m and SH.Remaining(m) == 0 then
		local nxt = nextMat(m)
		choose(nxt)
		if nxt then SH.message = "Crafted " .. P.ItemName(m.id) .. "." .. nextLine(nxt) end
		return ns:Send("ShoppingChanged")
	end
	if SH.current == m then return set("idle", instructions(m)) end
	ns:Send("ShoppingChanged")
end

-- A recipe ID is the spell ID of its craft.
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
	if unit ~= "player" or not SH.list then return end
	for _, m in ipairs(SH.list.steps or {}) do
		if m.recipeID and m.recipeID == spellID then return countCrafts(m, 1) end
	end
end)

-- Craft steps without a recipe ID: count from the bags while the step is current.
ns:On("BAG_UPDATE_DELAYED", function()
	local m = SH.current
	if not (SH.list and m and m.kind == "craft" and not m.recipeID and m.base) then return end
	local done = math.floor((owned(m.id) - m.base) / m.makes + 1e-6)
	local n = done - (made[m.id] or 0)
	if n > 0 then countCrafts(m, n) end
end)

-- The profession window opening or switching changes what a craft step says.
local function professionChanged()
	local m = SH.current
	if SH.list and m and m.kind == "craft" then set(SH.state, instructions(m)) end
end
ns:On("TRADE_SKILL_SHOW", professionChanged)
ns:On("TRADE_SKILL_LIST_UPDATE", professionChanged)

-- Purchases, continued ----------------------------------------------------------------

-- Called after the auction house confirms a commodity purchase (hooked, see below).
function SH.OnConfirmCommodities(itemID, qty)
	ns:Debug("shopping: confirm commodities", itemID, qty)
	pending = { id = itemID, qty = qty }
end

-- Called after the auction house places a bid or buyout on an item auction.
function SH.OnPlaceBid(auctionID, bid)
	local AH = C_AuctionHouse
	local info = AH and AH.GetAuctionInfoByID and ns.Try(AH.GetAuctionInfoByID, auctionID)
	local id = info and info.itemKey and info.itemKey.itemID
	if not id then id = SH.current and SH.current.id end
	ns:Debug("shopping: place bid", auctionID, bid, id)
	if id then pendingBids[auctionID] = { id = id, qty = math.max(1, (info and info.quantity) or 1) } end
end

if C_AuctionHouse and hooksecurefunc then
	hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", ns:Guard("shopping", function(...) SH.OnConfirmCommodities(...) end))
	hooksecurefunc(C_AuctionHouse, "PlaceBid", ns:Guard("shopping", function(...) SH.OnPlaceBid(...) end))
end

ns:On("COMMODITY_PURCHASE_SUCCEEDED", function()
	local p = pending
	pending = nil
	if p then count(p.id, p.qty) end
end)

ns:On("COMMODITY_PURCHASE_FAILED", function()
	ns:Debug("shopping: COMMODITY_PURCHASE_FAILED")
	pending = nil
end)

ns:On("AUCTION_HOUSE_PURCHASE_COMPLETED", function(auctionID)
	local p = pendingBids[auctionID]
	pendingBids[auctionID] = nil
	if p then count(p.id, p.qty) end
end)

-- Advice from the listings the auction house shows -----------------------------------

local function noOffer(m, cheapest)
	local cap = capFor(m.id)
	if not cap then
		SH.offer = nil
		return set("idle", "No market price for " .. P.ItemName(m.id) .. " yet, so no cap. Check the price yourself.")
	end
	SH.offer = nil
	set("idle", "Nothing at or under your cap of " .. Money(cap) .. " each"
		.. (cheapest and (" (cheapest: " .. Money(cheapest) .. ")") or "")
		.. ". Skip it, or raise the cap with /ka buycap.")
end

ns:On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
	local m = SH.current
	if not (m and m.kind ~= "craft" and m.id == itemID and SH.list) then return end
	local AH = C_AuctionHouse
	if not AH.HasFullCommoditySearchResults(itemID) then return end
	local listings = {}
	for i = 1, AH.GetNumCommoditySearchResults(itemID) do
		local r = AH.GetCommoditySearchResultInfo(itemID, i)
		if r and r.unitPrice and r.quantity then
			listings[#listings + 1] = { r.unitPrice, r.quantity, r.containsOwnerItem }
		end
	end
	local cap = capFor(itemID)
	if not cap then return noOffer(m) end
	local want = SH.Remaining(m)
	local qty, total = SH.CommodityOffer(listings, want, cap)
	if qty == 0 then return noOffer(m, listings[1] and listings[1][1]) end
	SH.offer = { qty = qty, total = total }
	local filled = fillQuantity(itemID, qty)
	local msg = (filled and ("Quantity set to " .. qty .. ". Check it and click Buy Now: about ")
		or ("Set the quantity to " .. qty .. " and click Buy Now: about ")) .. Money(total)
		.. " (" .. Money(math.floor(total / qty)) .. " each, cap " .. Money(cap) .. ")."
	if qty < want then msg = msg .. " Only " .. qty .. " of " .. want .. " are under your cap." end
	set("idle", cannotAfford(total) or msg)
end)

ns:On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
	local m = SH.current
	if not (m and m.kind ~= "craft" and itemKey and m.id == itemKey.itemID and SH.list) then return end
	local AH = C_AuctionHouse
	if not AH.HasFullItemSearchResults(itemKey) then return end
	local cap = capFor(m.id)
	if not cap then return noOffer(m) end
	local auctions, cheapest = {}, nil
	for i = 1, AH.GetNumItemSearchResults(itemKey) do
		local r = AH.GetItemSearchResultInfo(itemKey, i)
		if r and r.auctionID and r.buyoutAmount and r.buyoutAmount > 0 then
			local q = math.max(1, r.quantity or 1)
			auctions[#auctions + 1] = { r.auctionID, r.buyoutAmount, q, r.containsOwnerItem }
			local unit = r.buyoutAmount / q
			if not cheapest or unit < cheapest then cheapest = unit end
		end
	end
	local a = SH.ItemOffer(auctions, SH.Remaining(m), cap)
	if not a then return noOffer(m, cheapest and math.floor(cheapest)) end
	SH.offer = { qty = a[3], total = a[2] }
	set("idle", cannotAfford(a[2]) or ("Buy out the " .. a[3] .. "x for " .. Money(a[2]) .. " (cap "
		.. Money(cap) .. " each)."))
end)

-- The auction house's price quote, shown before you confirm: warn when it is over the cap.
ns:On("COMMODITY_PRICE_UPDATED", function(unitPrice, totalPrice)
	ns:Debug("shopping: COMMODITY_PRICE_UPDATED", unitPrice, totalPrice)
	local m = SH.current
	if not (m and m.kind ~= "craft" and SH.list) then return end
	local cap = capFor(m.id)
	if cap and unitPrice > cap then
		local msg = "Careful: " .. Money(unitPrice) .. " each is over your cap of " .. Money(cap)
			.. ". Cancel unless you want to pay that."
		ns:Print(msg)
		if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then ns.Try(PlaySound, SOUNDKIT.RAID_WARNING) end
		set("idle", msg)
	end
end)

-- The auction house refusing something (not enough money, item gone, ...): say why.
ns:On("AUCTION_HOUSE_SHOW_ERROR", function(code)
	ns:Debug("shopping: AUCTION_HOUSE_SHOW_ERROR", code)
	pending = nil
	if SH.list then set(SH.state, "The auction house refused: " .. SH.ErrorText(code) .. ". Nothing was bought.") end
end)

-- Should the game ever block something because of this addon, say so and log it.
ns:On("ADDON_ACTION_BLOCKED", function(addon, func)
	ns:Debug("ADDON_ACTION_BLOCKED", addon, func)
	if addon ~= ADDON then return end
	if autoFill() and time() - lastAuto <= SH.AUTO_WINDOW then
		ns.db.settings.autoFill = false
		ns:Print("the game blocked " .. tostring(func) .. " after the shopping list filled in a search or a "
			.. "quantity, so that is off now (/ka autofill turns it back on). Type the quantity or count "
			.. "yourself (or /reload), then click again.")
		if SH.list and SH.current then set(SH.state, instructions(SH.current)) end
		return
	end
	ns:Print("the game blocked " .. tostring(func) .. ". Type /reload, then search the auction house by hand.")
end)

ns:On("AUCTION_HOUSE_SHOW", function()
	if SH.list and SH.current then set(SH.state, instructions(SH.current)) end
end)

ns:On("AUCTION_HOUSE_CLOSED", function()
	pending = nil
	if SH.list and SH.state ~= "done" and not (SH.current and SH.current.kind == "craft") then
		SH.offer = nil
		set("idle", "Open the auction house to keep buying.")
	end
end)
